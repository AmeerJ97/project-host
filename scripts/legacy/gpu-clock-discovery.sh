#!/bin/bash
# GPU Clock + Power Discovery Script for Project Host
# Finds the stable GPU clock frequency at 140W under sustained inference load.
# Run this AFTER confirming Ollama is loading layers to GPU.

set -euo pipefail

MODEL="${1:-qwen3:32b}"
POWER_LIMIT=140
SAMPLE_INTERVAL=1
DURATION=60

echo "=== GPU Clock Discovery ==="
echo "Model: $MODEL"
echo "Power limit: ${POWER_LIMIT}W"
echo "Duration: ${DURATION}s"
echo ""

# Verify GPU state
echo "--- Pre-test GPU state ---"
nvidia-smi --query-gpu=power.draw,clocks.gr,temperature.gpu,pstate --format=csv,noheader
echo ""

# Verify Ollama has GPU layers
echo "--- Checking Ollama GPU layers ---"
LAYERS=$(journalctl -u ollama --no-pager -n 100 2>/dev/null | grep -oP 'loaded \K\d+(?=/)' | tail -1)
TOTAL=$(journalctl -u ollama --no-pager -n 100 2>/dev/null | grep -oP 'loaded \d+/\K\d+' | tail -1)
if [ -z "$LAYERS" ] || [ "$LAYERS" = "0" ]; then
    echo "WARNING: No GPU layers detected in Ollama logs."
    echo "Check: journalctl -u ollama -n 50 | grep -i layer"
    echo "Aborting — GPU must have layers loaded before clock discovery."
    exit 1
fi
echo "GPU layers: $LAYERS / $TOTAL"
echo ""

# Remove any existing clock lock for clean measurement
echo "--- Removing any existing clock lock ---"
nvidia-smi -rgc 2>/dev/null || true
sleep 2

echo "--- Starting inference load ---"
# Fire a sustained inference request in background
curl -s http://localhost:11434/api/generate -d "{
  \"model\": \"$MODEL\",
  \"prompt\": \"Write a comprehensive analysis of the history of computing from the 1940s to present day, covering major breakthroughs, key figures, and technological shifts. Be extremely detailed and thorough.\",
  \"stream\": false,
  \"options\": {\"num_gpu\": 99, \"num_ctx\": 4096}
}" > /dev/null 2>&1 &
CURL_PID=$!

echo "Inference PID: $CURL_PID"
echo "Sampling GPU state every ${SAMPLE_INTERVAL}s for ${DURATION}s..."
echo ""
echo "Time | Power (W) | Clock (MHz) | Temp (°C) | P-State | GPU Util %"
echo "-----|-----------|-------------|-----------|---------|----------"

# Sample GPU metrics during inference
CLOCKS=()
for i in $(seq 1 $DURATION); do
    DATA=$(nvidia-smi --query-gpu=power.draw,clocks.gr,temperature.gpu,pstate,utilization.gpu --format=csv,noheader,nounits 2>/dev/null)
    POWER=$(echo "$DATA" | cut -d',' -f1 | tr -d ' ')
    CLOCK=$(echo "$DATA" | cut -d',' -f2 | tr -d ' ')
    TEMP=$(echo "$DATA" | cut -d',' -f3 | tr -d ' ')
    PSTATE=$(echo "$DATA" | cut -d',' -f4 | tr -d ' ')
    UTIL=$(echo "$DATA" | cut -d',' -f5 | tr -d ' ')
    
    printf "%4ds | %9s | %11s | %9s | %7s | %s%%\n" "$i" "$POWER" "$CLOCK" "$TEMP" "$PSTATE" "$UTIL"
    
    # Collect clocks after initial ramp (skip first 10s)
    if [ "$i" -gt 10 ]; then
        CLOCKS+=("$CLOCK")
    fi
    
    # Check if inference is still running
    if ! kill -0 $CURL_PID 2>/dev/null; then
        echo ""
        echo "Inference completed at ${i}s"
        break
    fi
    
    sleep $SAMPLE_INTERVAL
done

# Kill inference if still running
kill $CURL_PID 2>/dev/null || true
wait $CURL_PID 2>/dev/null || true

echo ""
echo "=== Results ==="

if [ ${#CLOCKS[@]} -gt 0 ]; then
    # Find the most common (mode) clock frequency
    MODE_CLOCK=$(printf '%s\n' "${CLOCKS[@]}" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    MIN_CLOCK=$(printf '%s\n' "${CLOCKS[@]}" | sort -n | head -1)
    MAX_CLOCK=$(printf '%s\n' "${CLOCKS[@]}" | sort -n | tail -1)
    
    echo "Clock range: ${MIN_CLOCK} - ${MAX_CLOCK} MHz"
    echo "Most stable clock: ${MODE_CLOCK} MHz"
    echo ""
    echo "Recommended lock command:"
    echo "  sudo nvidia-smi -lgc ${MODE_CLOCK},${MODE_CLOCK}"
    echo ""
    echo "To apply permanently, add to nvidia-powercap.service:"
    echo "  ExecStart=/usr/bin/nvidia-smi -lgc ${MODE_CLOCK},${MODE_CLOCK}"
else
    echo "ERROR: No clock samples collected. Inference may not have started."
    echo "Check: journalctl -u ollama -n 20"
fi
