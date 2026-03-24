#!/bin/bash
# Project Host — Full System Diagnostics Sweep
# Run: bash scripts/sweep.sh
# Validates every major subsystem configuration against expected values.
# Configure expected values in sweep_config.sh or set environment variables.

set -euo pipefail

# -------------------------------------------------------------------
# CONFIGURATION
# Override these values by setting environment variables or creating
# a sweep_config.sh file in the same directory.
# -------------------------------------------------------------------

# GPU
EXPECTED_DRIVER_VERSION="${EXPECTED_DRIVER_VERSION:-590}"
EXPECTED_POWER_LIMIT="${EXPECTED_POWER_LIMIT:-140}"
EXPECTED_PERSISTENCE_MODE="${EXPECTED_PERSISTENCE_MODE:-Enabled}"
EXPECTED_BAR1_TOTAL="${EXPECTED_BAR1_TOTAL:-16384}"
EXPECTED_PCIE_GEN="${EXPECTED_PCIE_GEN:-4}"

# GPU Direct Memory
EXPECTED_UVM_CACHE_SYSMEM="${EXPECTED_UVM_CACHE_SYSMEM:-1}"
EXPECTED_UVM_CACHE_PEERMEM="${EXPECTED_UVM_CACHE_PEERMEM:-1}"
EXPECTED_UVM_PREFETCH_THRESHOLD="${EXPECTED_UVM_PREFETCH_THRESHOLD:-75}"

# CUDA
EXPECTED_CUDA="${EXPECTED_CUDA:-cuda}"

# Ollama
EXPECTED_OLLAMA_SERVICE="${EXPECTED_OLLAMA_SERVICE:-active}"

# Docker
EXPECTED_DOCKER_RUNTIME="${EXPECTED_DOCKER_RUNTIME:-nvidia}"

# CPU
EXPECTED_CPU_GOVERNOR="${EXPECTED_CPU_GOVERNOR:-performance}"
EXPECTED_CPU_TURBO="${EXPECTED_CPU_TURBO:-0}"

# Memory
EXPECTED_SWAPPINESS="${EXPECTED_SWAPPINESS:-10}"
EXPECTED_HUGEPAGES="${EXPECTED_HUGEPAGES:-4096}"
EXPECTED_THP="${EXPECTED_THP:-madvise}"
EXPECTED_THP_DEFRAG="${EXPECTED_THP_DEFRAG:-madvise}"
EXPECTED_KSM="${EXPECTED_KSM:-0}"
EXPECTED_COMPACTION="${EXPECTED_COMPACTION:-0}"
EXPECTED_NUMA_BALANCING="${EXPECTED_NUMA_BALANCING:-0}"
EXPECTED_SWAP_DEVICES_MIN="${EXPECTED_SWAP_DEVICES_MIN:-2}"

# I/O
EXPECTED_NVME_SCHEDULER="${EXPECTED_NVME_SCHEDULER:-none}"
EXPECTED_NVME_READAHEAD_KB="${EXPECTED_NVME_READAHEAD_KB:-2048}"
EXPECTED_HDD_SCHEDULER="${EXPECTED_HDD_SCHEDULER:-mq-deadline}"

# Network
EXPECTED_RMEM_MAX="${EXPECTED_RMEM_MAX:-16777216}"
EXPECTED_WMEM_MAX="${EXPECTED_WMEM_MAX:-16777216}"
EXPECTED_TCP_FASTOPEN="${EXPECTED_TCP_FASTOPEN:-3}"

# Boot
EXPECTED_BOOT_ASPM="${EXPECTED_BOOT_ASPM:-pcie_aspm=off}"
EXPECTED_BOOT_ZSWAP="${EXPECTED_BOOT_ZSWAP:-zswap.enabled=0}"
EXPECTED_BOOT_NVIDIA_DRM="${EXPECTED_BOOT_NVIDIA_DRM:-nvidia-drm.modeset=1}"
EXPECTED_BOOT_IOMMU="${EXPECTED_BOOT_IOMMU:-intel_iommu=on}"

# Wayland
EXPECTED_SESSION_TYPE="${EXPECTED_SESSION_TYPE:-wayland}"

# -------------------------------------------------------------------
# Load user configuration if present
# -------------------------------------------------------------------
CONFIG_FILE="$(dirname "$0")/sweep_config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    echo "Loaded configuration from $CONFIG_FILE"
fi

# -------------------------------------------------------------------
# Output formatting
# -------------------------------------------------------------------
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
check "Driver" "$EXPECTED_DRIVER_VERSION" "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'N/A')"
check "Power Limit" "$EXPECTED_POWER_LIMIT" "$(nvidia-smi -q -d power 2>/dev/null | grep 'Current Power Limit' | head -1 | awk '{print $5}')"
check "Persistence" "$EXPECTED_PERSISTENCE_MODE" "$(nvidia-smi -q 2>/dev/null | grep 'Persistence Mode' | awk '{print $4}')"
check "BAR1 Total" "$EXPECTED_BAR1_TOTAL" "$(nvidia-smi -q 2>/dev/null | grep -A1 'BAR1 Memory' | grep Total | awk '{print $3}')"
check "PCIe Gen" "$EXPECTED_PCIE_GEN" "$(nvidia-smi -q 2>/dev/null | grep -A5 'GPU Link Info' | grep 'Current' | head -1 | awk '{print $3}')"

echo ""
echo "--- GPU Direct Memory ---"
check "UVM cache_sysmem" "$EXPECTED_UVM_CACHE_SYSMEM" "$(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_sysmem 2>/dev/null || echo '0')"
check "UVM cache_peermem" "$EXPECTED_UVM_CACHE_PEERMEM" "$(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_peermem 2>/dev/null || echo '0')"
check "UVM prefetch threshold" "$EXPECTED_UVM_PREFETCH_THRESHOLD" "$(cat /sys/module/nvidia_uvm/parameters/uvm_perf_prefetch_threshold 2>/dev/null || echo 'N/A')"
check "nvidia_fs loaded" "nvidia_fs" "$(lsmod | grep nvidia_fs | awk '{print $1}' || echo 'not loaded')"

echo ""
echo "--- CUDA ---"
check "CUDA" "$EXPECTED_CUDA" "$(nvcc --version 2>/dev/null | tail -1 || echo 'N/A')"
check "LD_LIBRARY_PATH" "cuda" "$(echo $LD_LIBRARY_PATH 2>/dev/null || echo 'N/A')"

echo ""
echo "--- Ollama ---"
check "Service" "$EXPECTED_OLLAMA_SERVICE" "$(systemctl is-active ollama 2>/dev/null || echo 'inactive')"
OLLAMA_TAGS=$(curl -sf http://localhost:11434/api/tags 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('models',[])))" 2>/dev/null || echo "N/A")
[[ "$OLLAMA_TAGS" != "N/A" ]] && pass "Models loaded" "$OLLAMA_TAGS model(s)" || warn "Ollama API" "not reachable"

echo ""
echo "--- Docker ---"
check "Runtime" "$EXPECTED_DOCKER_RUNTIME" "$(docker info 2>/dev/null | grep 'Default Runtime' | awk '{print $3}' || echo 'N/A')"

echo ""
echo "--- CPU ---"
check "Governor" "$EXPECTED_CPU_GOVERNOR" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
check "Turbo" "$EXPECTED_CPU_TURBO" "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)"

echo ""
echo "--- Memory ---"
check "Swappiness" "$EXPECTED_SWAPPINESS" "$(sysctl -n vm.swappiness 2>/dev/null)"
check "HugePages" "$EXPECTED_HUGEPAGES" "$(grep HugePages_Total /proc/meminfo | awk '{print $2}')"
check "THP" "$EXPECTED_THP" "$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)"
check "THP defrag" "$EXPECTED_THP_DEFRAG" "$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)"
check "KSM" "$EXPECTED_KSM" "$(cat /sys/kernel/mm/ksm/run 2>/dev/null)"
check "Compaction" "$EXPECTED_COMPACTION" "$(sysctl -n vm.compaction_proactiveness 2>/dev/null)"
check "NUMA balancing" "$EXPECTED_NUMA_BALANCING" "$(sysctl -n kernel.numa_balancing 2>/dev/null)"

echo ""
echo "--- Swap ---"
SWAP_COUNT=$(swapon --show --noheadings 2>/dev/null | wc -l)
[[ "$SWAP_COUNT" -ge $EXPECTED_SWAP_DEVICES_MIN ]] && pass "Swap devices" "$SWAP_COUNT active" || fail "Swap devices" "≥$EXPECTED_SWAP_DEVICES_MIN" "$SWAP_COUNT"
check "swapspace daemon" "active" "$(systemctl is-active swapspace 2>/dev/null || echo 'inactive')"

echo ""
echo "--- I/O ---"
check "NVMe scheduler" "$EXPECTED_NVME_SCHEDULER" "$(cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null)"
check "NVMe readahead" "$EXPECTED_NVME_READAHEAD_KB" "$(cat /sys/block/nvme0n1/queue/read_ahead_kb 2>/dev/null)"
check "HDD scheduler" "$EXPECTED_HDD_SCHEDULER" "$(cat /sys/block/sda/queue/scheduler 2>/dev/null)"

echo ""
echo "--- Network ---"
check "rmem_max" "$EXPECTED_RMEM_MAX" "$(sysctl -n net.core.rmem_max 2>/dev/null)"
check "wmem_max" "$EXPECTED_WMEM_MAX" "$(sysctl -n net.core.wmem_max 2>/dev/null)"
check "TCP FastOpen" "$EXPECTED_TCP_FASTOPEN" "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)"

echo ""
echo "--- Boot ---"
CMDLINE=$(cat /proc/cmdline)
check "ASPM off" "$EXPECTED_BOOT_ASPM" "$CMDLINE"
check "zswap disabled" "$EXPECTED_BOOT_ZSWAP" "$CMDLINE"
check "nvidia-drm" "$EXPECTED_BOOT_NVIDIA_DRM" "$CMDLINE"
check "IOMMU" "$EXPECTED_BOOT_IOMMU" "$CMDLINE"

echo ""
echo "--- Wayland ---"
check "Session type" "$EXPECTED_SESSION_TYPE" "$(echo $XDG_SESSION_TYPE 2>/dev/null || echo 'N/A')"

echo ""
echo "--- Thermals ---"
CPU_TEMP=$(sensors 2>/dev/null | grep 'Package id 0' | awk '{print $4}' | tr -d '+°C')
GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null)
echo "  CPU Package: ${CPU_TEMP}°C  |  GPU: ${GPU_TEMP}°C"

echo ""
echo "======================================="
echo "  Sweep complete."
echo "======================================="
