[< Back to Index](README.md)

## 6. Ollama

> **WARNING:** This file was stale as of 2026-04-01. It has been updated to match `docs/INFERENCE-CONFIG.md`, which is the source of truth for validated Ollama configuration. If these ever conflict again, INFERENCE-CONFIG.md wins.

**Service file:** `/etc/systemd/system/ollama.service`
**Override:** `/etc/systemd/system/ollama.service.d/override.conf`

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_MODELS=/home/active/inference/ollama"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="GGML_CUDA_ENABLE_UNIFIED_MEMORY=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_LLM_LIBRARY=cuda_v12"
CPUAffinity=0-15
CPUQuota=1568%
OOMScoreAdjust=-900
IOWeight=900
LimitMEMLOCK=infinity
LimitNOFILE=65536
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `OLLAMA_HOST` | `0.0.0.0` | Listen on all interfaces (LAN access from k3s nodes) |
| `OLLAMA_MODELS` | `/home/active/inference/ollama` | Model storage on Gateway tier (NVMe) for fast loading |
| `OLLAMA_FLASH_ATTENTION` | `1` | Enable Flash Attention — reduces VRAM usage and improves throughput |
| `OLLAMA_KEEP_ALIVE` | `24h` | Keep models loaded in memory for 24 hours — avoids reload latency |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | 8-bit KV cache — halves KV cache memory vs f16, allowing more layers in VRAM |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | Single model resident — prevents VRAM contention on 16GB card |
| `OLLAMA_NUM_PARALLEL` | `2` | 2 concurrent requests — doubles KV cache but enables pipelining |
| `OLLAMA_LLM_LIBRARY` | `cuda_v12` | **Mandatory.** Forces CUDA 12 backend. Without this, Ollama tries cuda_v13 first which fails silently, causing CPU-only fallback |
| `GGML_CUDA_ENABLE_UNIFIED_MEMORY` | `1` | Allow GGML to use CUDA unified memory — enables models larger than VRAM |
| `CPUAffinity` | `0-15` | All 16 cores — spreads load across P-cores and E-cores to prevent thermal hotspots |
| `CPUQuota` | `1568%` | 16 cores × 98% — caps each core below 100% for thermal headroom |
| `OOMScoreAdjust` | `-900` | Strongly resist OOM killer |
| `IOWeight` | `900` | High I/O priority for model loading |
| `LimitMEMLOCK` | `infinity` | Allow unlimited memory locking (required for pinned buffers) |
| `LimitNOFILE` | `65536` | High file descriptor limit for concurrent connections |

### Critical: `OLLAMA_NUM_GPU` Is NOT Valid

`OLLAMA_NUM_GPU` is **not a valid Ollama server environment variable** (confirmed via Ollama source code, GitHub issue #11437). Previous configurations included `OLLAMA_NUM_GPU=99` — it was silently ignored.

GPU layer count must be set per-model via:
- **Modelfile:** `PARAMETER num_gpu 99`
- **API request:** `"options": {"num_gpu": 99}`

### Shell Environment

`~/.bashrc` also sets:
```bash
export OLLAMA_MODELS=/home/active/inference/ollama
export HF_HOME=/home/apps/models/huggingface
```

### GPU Layer Offload Recommendations

| Model Size | Quantization | Recommended `num_gpu` | Notes |
|------------|-------------|----------------------|-------|
| ≤ 13B | Any | 99 (all layers) | Fits entirely in 16GB VRAM |
| 32B | Q4_K_M | 28-30 | ~10-12GB VRAM, rest in RAM via UVM |
| 70B | Q4_K_M | 20-30 | ~8-12GB VRAM, rest in RAM via UVM |

### Pre-Inference Verification

**Always confirm GPU layers before sending inference requests:**
```bash
# Check Ollama logs for layer loading
journalctl -u ollama -n 50 | grep -i "layer\|gpu\|vram"

# Verify GPU is being used (should show >30W, >500MHz during inference)
nvidia-smi --query-gpu=power.draw,clocks.gr --format=csv,noheader

# If 0 layers loaded or 0 VRAM: check OLLAMA_LLM_LIBRARY, ldconfig, nvidia-smi
```
