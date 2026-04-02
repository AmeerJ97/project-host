#!/bin/bash
# Project Host — Full System Diagnostics Sweep
# Run: bash scripts/sweep.sh
# Validates every major subsystem configuration against expected values.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}PASS${NC}  $1: $2"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1: expected '$2', got '$3'"; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $1: $2"; }

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        pass "$name" "$actual"
    else
        fail "$name" "$expected" "$actual"
    fi
}

echo "======================================="
echo "  Project Host — Diagnostics Sweep"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================="
echo ""

echo "--- GPU ---"
check "Driver" "590" "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'N/A')"
check "Power Limit" "140" "$(nvidia-smi -q -d power 2>/dev/null | grep 'Current Power Limit' | head -1 | awk '{print $5}')"
check "Persistence" "Enabled" "$(nvidia-smi -q 2>/dev/null | grep 'Persistence Mode' | awk '{print $4}')"
check "BAR1 Total" "16384" "$(nvidia-smi -q 2>/dev/null | grep -A1 'BAR1 Memory' | grep Total | awk '{print $3}')"
check "PCIe Gen" "4" "$(nvidia-smi -q 2>/dev/null | grep -A5 'GPU Link Info' | grep 'Current' | head -1 | awk '{print $3}')"

echo ""
echo "--- GPU Direct Memory ---"
check "UVM cache_sysmem" "1" "$(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_sysmem 2>/dev/null || echo '0')"
check "UVM cache_peermem" "1" "$(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_peermem 2>/dev/null || echo '0')"
check "UVM prefetch threshold" "75" "$(cat /sys/module/nvidia_uvm/parameters/uvm_perf_prefetch_threshold 2>/dev/null || echo 'N/A')"
check "nvidia_fs loaded" "nvidia_fs" "$(lsmod | grep nvidia_fs | awk '{print $1}' || echo 'not loaded')"

echo ""
echo "--- CUDA ---"
check "CUDA" "cuda" "$(nvcc --version 2>/dev/null | tail -1 || echo 'N/A')"
check "LD_LIBRARY_PATH" "cuda" "$(echo $LD_LIBRARY_PATH 2>/dev/null || echo 'N/A')"

echo ""
echo "--- Ollama ---"
check "Service" "active" "$(systemctl is-active ollama 2>/dev/null || echo 'inactive')"
OLLAMA_TAGS=$(curl -sf http://localhost:11434/api/tags 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('models',[])))" 2>/dev/null || echo "N/A")
[[ "$OLLAMA_TAGS" != "N/A" ]] && pass "Models loaded" "$OLLAMA_TAGS model(s)" || warn "Ollama API" "not reachable"

echo ""
echo "--- Docker ---"
check "Runtime" "nvidia" "$(docker info 2>/dev/null | grep 'Default Runtime' | awk '{print $3}' || echo 'N/A')"

echo ""
echo "--- CPU ---"
check "Governor" "performance" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
check "Turbo" "0" "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)"

echo ""
echo "--- Memory ---"
check "Swappiness" "10" "$(sysctl -n vm.swappiness 2>/dev/null)"
check "HugePages" "4096" "$(grep HugePages_Total /proc/meminfo | awk '{print $2}')"
check "THP" "madvise" "$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
check "THP defrag" "madvise" "$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)"
check "KSM" "0" "$(cat /sys/kernel/mm/ksm/run 2>/dev/null)"
check "Compaction" "0" "$(sysctl -n vm.compaction_proactiveness 2>/dev/null)"
check "NUMA balancing" "0" "$(sysctl -n kernel.numa_balancing 2>/dev/null)"

echo ""
echo "--- Swap ---"
SWAP_COUNT=$(swapon --show --noheadings 2>/dev/null | wc -l)
[[ "$SWAP_COUNT" -ge 2 ]] && pass "Swap devices" "$SWAP_COUNT active" || fail "Swap devices" "≥2" "$SWAP_COUNT"
check "swapspace daemon" "active" "$(systemctl is-active swapspace 2>/dev/null || echo 'inactive')"

echo ""
echo "--- I/O ---"
check "NVMe scheduler" "none" "$(cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null)"
check "NVMe readahead" "2048" "$(cat /sys/block/nvme0n1/queue/read_ahead_kb 2>/dev/null)"
check "HDD scheduler" "mq-deadline" "$(cat /sys/block/sda/queue/scheduler 2>/dev/null)"

echo ""
echo "--- Network ---"
check "rmem_max" "16777216" "$(sysctl -n net.core.rmem_max 2>/dev/null)"
check "wmem_max" "16777216" "$(sysctl -n net.core.wmem_max 2>/dev/null)"
check "TCP FastOpen" "3" "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)"

echo ""
echo "--- Boot ---"
CMDLINE=$(cat /proc/cmdline)
check "ASPM off" "pcie_aspm=off" "$CMDLINE"
check "zswap disabled" "zswap.enabled=0" "$CMDLINE"
check "nvidia-drm" "nvidia-drm.modeset=1" "$CMDLINE"
check "IOMMU" "intel_iommu=on" "$CMDLINE"

echo ""
echo "--- Wayland ---"
check "Session type" "wayland" "$(echo $XDG_SESSION_TYPE 2>/dev/null || echo 'N/A')"

echo ""
echo "--- Thermals ---"
CPU_TEMP=$(sensors 2>/dev/null | grep 'Package id 0' | awk '{print $4}' | tr -d '+°C')
GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null)
echo "  CPU Package: ${CPU_TEMP}°C  |  GPU: ${GPU_TEMP}°C"

echo ""
echo "======================================="
echo "  Sweep complete."
echo "======================================="
