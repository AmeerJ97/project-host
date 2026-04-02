#!/usr/bin/env bash
# =============================================================================
# Project Host — Master System Sweep v5.0
# Comprehensive verification of ALL system configurations.
#
# Usage: ./scripts/master-sweep.sh [--no-color] [--profile NAME]
#
# Profiles: workstation (default), inference-only, benchmark
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse arguments ─────────────────────────────────────────────────────────
NO_COLOR=false
PROFILE="workstation"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-color) NO_COLOR=true; shift ;;
        --profile)  PROFILE="$2"; shift 2 ;;
        *)          shift ;;
    esac
done

# ── Load profile ────────────────────────────────────────────────────────────
PROFILE_FILE="${SCRIPT_DIR}/profiles/${PROFILE}.conf"
if [[ ! -f "$PROFILE_FILE" ]]; then
    echo "ERROR: Profile '${PROFILE}' not found at ${PROFILE_FILE}" >&2
    echo "Available profiles: $(ls "${SCRIPT_DIR}/profiles/"*.conf 2>/dev/null | xargs -I{} basename {} .conf | tr '\n' ' ')" >&2
    exit 1
fi
source "$PROFILE_FILE"

# ── Colors (Claude TUI palette) ─────────────────────────────────────────────
if $NO_COLOR; then
    T="" F="" W="" I="" D="" B="" A="" S="" NC=""
else
    T='\033[38;2;127;187;179m'   # Teal (pass/accent)
    F='\033[38;2;230;126;128m'   # Soft red (fail)
    W='\033[38;2;229;192;123m'   # Warm amber (warn)
    I='\033[38;2;133;146;137m'   # Muted sage (info)
    D='\033[2;37m'               # Dim grey
    B='\033[1m'                  # Bold
    A='\033[38;2;167;192;128m'   # Soft green (headers)
    S='\033[38;2;157;169;160m'   # Subtle grey (separators)
    NC='\033[0m'
fi

# ── Counters ─────────────────────────────────────────────────────────────────
TOTAL=0; OK=0; BAD=0; MEH=0

# ── Helpers ──────────────────────────────────────────────────────────────────
ok() {
    TOTAL=$((TOTAL+1)); OK=$((OK+1))
    printf "  ${T}●${NC}  %-48s ${D}%s${NC}\n" "$1" "$2"
}

no() {
    TOTAL=$((TOTAL+1)); BAD=$((BAD+1))
    printf "  ${F}●${NC}  %-48s ${F}%s${NC}  ${D}(want: %s)${NC}\n" "$1" "$2" "$3"
    [[ -n "${4:-}" ]] && printf "     ${W}→${NC} ${D}%s${NC}\n" "$4" || true
}

meh() {
    TOTAL=$((TOTAL+1)); MEH=$((MEH+1))
    printf "  ${W}●${NC}  %-48s ${W}%s${NC}\n" "$1" "$2"
    [[ -n "${3:-}" ]] && printf "     ${D}→ %s${NC}\n" "$3" || true
}

eq() {
    local n="$1" a="$2" e="$3" f="${4:-}"
    [[ "$a" == "$e" ]] && ok "$n" "$a" || no "$n" "$a" "$e" "$f"
}

has() {
    local n="$1" h="$2" s="$3" f="${4:-}"
    [[ "$h" == *"$s"* ]] && ok "$n" "present" || no "$n" "missing" "$s" "$f"
}

gte() {
    local n="$1" a="$2" m="$3" f="${4:-}"
    [[ "$a" -ge "$m" ]] 2>/dev/null && ok "$n" "$a" || no "$n" "$a" "≥$m" "$f"
}

sec() {
    echo ""
    printf "  ${B}${A}┌─ %s ─${NC}\n" "$1"
    printf "  ${S}│${NC}\n"
}

sep() {
    printf "  ${S}│${NC}\n"
}

info() {
    printf "  ${I}●${NC}  %-48s ${D}%s${NC}\n" "$1" "$2"
}

# ── Header ───────────────────────────────────────────────────────────────────
echo ""
printf "${B}${T}"
cat << 'BANNER'
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║           PROJECT HOST — MASTER SYSTEM SWEEP              ║
    ║           Unified Memory Fabric Architecture              ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
BANNER
printf "${NC}"
printf "    ${I}%s  •  Kernel %s  •  v5.0${NC}\n" "$(date '+%Y-%m-%d %H:%M')" "$(uname -r)"
printf "    ${I}i7-13700F  •  96GB DDR5  •  RTX 4060 Ti 16GB  •  1TB NVMe Gen4${NC}\n"
printf "    ${W}Profile: %s${NC}\n" "$PROFILE"

# ═════════════════════════════════════════════════════════════════════════════
# 1. GPU — Driver & Power
# ═════════════════════════════════════════════════════════════════════════════
sec "GPU — Driver & Power"

DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "N/A")
has "Driver version" "$DRIVER" "590" "sudo apt install nvidia-driver-590"

PL=$(nvidia-smi -q -d power 2>/dev/null | awk '/Current Power Limit/{print $5; exit}')
eq "Power limit" "${PL:-N/A} W" "${EXPECT_POWER_LIMIT} W" "Check nvidia-powercap.service"

PM=$(nvidia-smi -q 2>/dev/null | awk '/Persistence Mode/{print $4; exit}')
eq "Persistence mode" "${PM:-N/A}" "Enabled" "sudo nvidia-smi -pm 1"

SVC=$(systemctl is-active nvidia-persistenced 2>/dev/null || echo "inactive")
eq "nvidia-persistenced" "$SVC" "active" "sudo systemctl enable --now nvidia-persistenced"

PCAP_RESULT=$(systemctl show nvidia-powercap --property=Result 2>/dev/null | cut -d= -f2)
eq "nvidia-powercap service" "${PCAP_RESULT:-N/A}" "success" "sudo systemctl restart nvidia-powercap"

sep

# ═════════════════════════════════════════════════════════════════════════════
# 2. GPU — PCIe & BAR1
# ═════════════════════════════════════════════════════════════════════════════
sec "GPU — PCIe Link & BAR1"

BAR1=$(nvidia-smi -q 2>/dev/null | awk '/BAR1 Memory Usage/{f=1} f && /Total/{print $3; exit}')
eq "BAR1 (Resizable BAR)" "${BAR1:-N/A} MiB" "16384 MiB" "Enable Above 4G Decoding + rBAR in BIOS"

PCIE_MAX=$(nvidia-smi -q 2>/dev/null | awk '/PCIe Generation/{f=1} f && /Max/{print $3; exit}')
eq "PCIe Gen (max)" "${PCIE_MAX:-N/A}" "4" "Set PCIe to Gen4 in BIOS"

PCIE_WIDTH=$(nvidia-smi -q 2>/dev/null | awk '/Link Width/{f=1} f && /Max/{gsub(/x/,""); print $3; exit}')
eq "PCIe Width (max)" "${PCIE_WIDTH:-N/A}" "8" "Check physical slot"

MPS=$(sudo lspci -s 01:00.0 -vvv 2>/dev/null | grep -oP 'MaxPayload \K[0-9]+' | head -1)
eq "Max Payload Size" "${MPS:-N/A} bytes" "256 bytes" "Hardware limit"

MRRS=$(sudo lspci -s 01:00.0 -vvv 2>/dev/null | grep -oP 'MaxReadReq \K[0-9]+' | head -1)
TOTAL=$((TOTAL+1))
if [[ "${MRRS:-0}" -ge 512 ]]; then
    OK=$((OK+1)); printf "  ${T}●${NC}  %-48s ${D}%s bytes${NC}\n" "Max Read Request Size" "$MRRS"
else
    BAD=$((BAD+1)); printf "  ${F}●${NC}  %-48s ${F}%s bytes${NC}  ${D}(want: ≥512)${NC}\n" "Max Read Request Size" "${MRRS:-N/A}"
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# 3. GPU — UVM & Direct Memory
# ═════════════════════════════════════════════════════════════════════════════
sec "GPU — UVM & GPU Direct Memory"

UVM_CACHE=$(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_sysmem 2>/dev/null || echo "N/A")
eq "UVM cache_sysmem" "$UVM_CACHE" "1" "modprobe option: uvm_exp_gpu_cache_sysmem=1"

UVM_PEER=$(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_peermem 2>/dev/null || echo "N/A")
eq "UVM cache_peermem" "$UVM_PEER" "1" "modprobe option: uvm_exp_gpu_cache_peermem=1 (GPU L2 caches RAM-resident model weights)"

# Verify NVreg_InitializeSystemMemoryAllocations is NOT 0 (causes Xid 154 with init_on_alloc=0)
INIT_ALLOC=$(cat /proc/driver/nvidia/params 2>/dev/null | awk '/InitializeSystemMemoryAllocations/{print $2}')
if [[ "${INIT_ALLOC:-1}" == "0" ]]; then
    no "NVreg_InitializeSystemMemoryAllocations" "0" "1" "CRITICAL: causes Xid 154 with init_on_alloc=0 in GRUB"
else
    ok "NVreg_InitializeSystemMemoryAllocations" "${INIT_ALLOC:-1}"
fi

UVM_PREFETCH=$(cat /sys/module/nvidia_uvm/parameters/uvm_perf_prefetch_threshold 2>/dev/null || echo "N/A")
eq "UVM prefetch threshold" "$UVM_PREFETCH" "75" "modprobe option: uvm_perf_prefetch_threshold=75"

NVIDIA_FS=$(lsmod 2>/dev/null | awk '/^nvidia_fs/{print "loaded"; exit}')
if [[ "${NVIDIA_FS:-not loaded}" == "loaded" ]]; then
    ok "nvidia_fs (GDS)" "loaded"
else
    meh "nvidia_fs (GDS)" "not loaded (optional on GeForce)" "sudo apt install nvidia-gds-12-6 && sudo modprobe nvidia_fs"
fi

# CUDA compute access — caps permissions are advisory (not required since InitializeSystemMemoryAllocations=1)
CAP1_PERM=$(stat -c '%a' /dev/nvidia-caps/nvidia-cap1 2>/dev/null || echo "000")
if [[ "${CAP1_PERM:0:2}" == "66" ]] || [[ "$CAP1_PERM" == "666" ]]; then
    ok "nvidia-cap1 permissions" "${CAP1_PERM} (render group)"
else
    meh "nvidia-cap1 permissions" "${CAP1_PERM} (CUDA works via InitializeSystemMemoryAllocations=1)" ""
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# 4. NVIDIA modprobe — All Options
# ═════════════════════════════════════════════════════════════════════════════
sec "NVIDIA Module Options"

NV_CONF=$(cat /etc/modprobe.d/nvidia.conf 2>/dev/null || echo "")
for opt in \
    "NVreg_EnableStreamMemOPs=1" \
    "NVreg_EnableResizableBar=1" \
    "NVreg_PreserveVideoMemoryAllocations=1" \
    "NVreg_EnableGpuFirmware=1" \
    "NVreg_EnablePCIERelaxedOrderingMode=1" \
    "NVreg_UsePageAttributeTable=1" \
    "NVreg_InitializeSystemMemoryAllocations=1"; do
    has "$opt" "$NV_CONF" "$opt" "Add to /etc/modprobe.d/nvidia.conf"
done

NV_DRM=$(cat /etc/modprobe.d/nvidia-drm.conf 2>/dev/null || echo "")
has "nvidia-drm modeset=1" "$NV_DRM" "modeset=1" "Add to /etc/modprobe.d/nvidia-drm.conf"
has "nvidia-drm fbdev=1"   "$NV_DRM" "fbdev=1"   "Add to /etc/modprobe.d/nvidia-drm.conf"

sep

# ═════════════════════════════════════════════════════════════════════════════
# 5. GRUB — Kernel Boot Parameters
# ═════════════════════════════════════════════════════════════════════════════
sec "GRUB — Kernel Boot Parameters"

CMD=$(cat /proc/cmdline 2>/dev/null)
for flag in \
    "nvidia-drm.modeset=1" \
    "pcie_aspm=off" \
    "zswap.enabled=0" \
    "transparent_hugepage=madvise" \
    "intel_iommu=on" \
    "iommu=pt" \
    "init_on_alloc=0" \
    "nvme.poll_queues=4"; do
    has "GRUB: $flag" "$CMD" "$flag" "Add to GRUB_CMDLINE_LINUX_DEFAULT, sudo update-grub"
done

# preempt model — advisory only
if [[ "$CMD" == *"preempt=none"* ]]; then
    ok "GRUB: preempt=none" "set (lowest latency)"
elif [[ "$(sudo dmesg 2>/dev/null | grep -oP 'PREEMPT\(\K[^)]+' | head -1)" == "voluntary" ]]; then
    meh "GRUB: preempt model" "voluntary (desktop-friendly)" "Add preempt=none for pure inference workloads"
else
    meh "GRUB: preempt model" "$(sudo dmesg 2>/dev/null | grep -oP 'PREEMPT\(\K[^)]+' | head -1 || echo 'unknown')" ""
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# 6. sysctl — Memory
# ═════════════════════════════════════════════════════════════════════════════
sec "Kernel sysctl — Memory"

eq "vm.swappiness"             "$(sysctl -n vm.swappiness 2>/dev/null)"             "${EXPECT_SWAPPINESS}" "Persist in /etc/sysctl.d/99-inference.conf"
eq "vm.overcommit_memory"      "$(sysctl -n vm.overcommit_memory 2>/dev/null)"      "1"       "Required for cudaMallocManaged UVM"
eq "vm.overcommit_ratio"       "$(sysctl -n vm.overcommit_ratio 2>/dev/null)"       "80"      "Persist in /etc/sysctl.d/99-inference.conf"
eq "vm.nr_hugepages"           "$(sysctl -n vm.nr_hugepages 2>/dev/null)"           "${EXPECT_HUGEPAGES}" "sysctl vm.nr_hugepages=${EXPECT_HUGEPAGES}"
eq "vm.compaction_proactiveness" "$(sysctl -n vm.compaction_proactiveness 2>/dev/null)" "0"    "Prevents latency spikes"
eq "kernel.numa_balancing"     "$(sysctl -n kernel.numa_balancing 2>/dev/null)"     "0"       "Single-socket, no benefit"
eq "vm.max_map_count"          "$(sysctl -n vm.max_map_count 2>/dev/null)"          "1048576" "Required for large mmap models"
eq "vm.vfs_cache_pressure"     "$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)"     "50"      "Retain dentry/inode cache"
eq "vm.dirty_background_bytes" "$(sysctl -n vm.dirty_background_bytes 2>/dev/null)" "1610612736" "1.5GB background writeback"
eq "vm.dirty_bytes"            "$(sysctl -n vm.dirty_bytes 2>/dev/null)"            "4294967296"  "4GB sync writeback ceiling"

sep

# ═════════════════════════════════════════════════════════════════════════════
# 7. sysctl — Network
# ═════════════════════════════════════════════════════════════════════════════
sec "Kernel sysctl — Network"

eq "net.ipv4.tcp_fastopen"  "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)"  "3"        ""
eq "net.core.rmem_max"      "$(sysctl -n net.core.rmem_max 2>/dev/null)"      "16777216"  ""
eq "net.core.wmem_max"      "$(sysctl -n net.core.wmem_max 2>/dev/null)"      "16777216"  ""
eq "net.core.netdev_max_backlog" "$(sysctl -n net.core.netdev_max_backlog 2>/dev/null)" "5000" ""

sep

# ═════════════════════════════════════════════════════════════════════════════
# 8. Memory — THP, HugePages, KSM
# ═════════════════════════════════════════════════════════════════════════════
sec "Memory — THP, HugePages & KSM"

THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)
has "THP mode" "$THP" "[madvise]" "GRUB: transparent_hugepage=madvise"

DEFRAG=$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null)
has "THP defrag" "$DEFRAG" "[madvise]" "echo madvise > /sys/kernel/mm/transparent_hugepage/defrag"

KSM=$(cat /sys/kernel/mm/ksm/run 2>/dev/null || echo "N/A")
eq "KSM disabled" "$KSM" "0" "echo 0 > /sys/kernel/mm/ksm/run"

HP_TOTAL=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
HP_FREE=$(grep HugePages_Free /proc/meminfo | awk '{print $2}')
eq "HugePages total" "$HP_TOTAL" "${EXPECT_HUGEPAGES}" "sysctl vm.nr_hugepages=${EXPECT_HUGEPAGES}"
info "HugePages utilization" "$HP_FREE free of $HP_TOTAL"

sep

# ═════════════════════════════════════════════════════════════════════════════
# 9. CPU — Governor, Turbo, C-states
# ═════════════════════════════════════════════════════════════════════════════
sec "CPU — Governor, Turbo & C-states"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
eq "CPU governor" "$GOV" "performance" "cpupower frequency-set -g performance"

PSTATE=$(cat /sys/devices/system/cpu/intel_pstate/status 2>/dev/null)
eq "intel_pstate mode" "$PSTATE" "active" "Driver config"

TURBO=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
eq "Turbo enabled (no_turbo=0)" "$TURBO" "0" ""

# C-states
for state_dir in /sys/devices/system/cpu/cpu0/cpuidle/state*/; do
    state_name=$(cat "${state_dir}name" 2>/dev/null || continue)
    state_num=$(basename "$state_dir" | grep -oP '[0-9]+')
    state_disabled=$(cat "${state_dir}disable" 2>/dev/null || echo "N/A")
    if [[ "$state_num" -le 1 ]]; then
        ok "C-state $state_name (state$state_num)" "enabled (expected)"
    else
        if [[ "$state_disabled" == "1" ]]; then
            ok "C-state $state_name (state$state_num)" "disabled"
        else
            meh "C-state $state_name (state$state_num)" "enabled — consider disabling" "cpupower idle-set -d $state_num"
        fi
    fi
done

sep

# ═════════════════════════════════════════════════════════════════════════════
# 10. Swap — L3 Memory Fabric
# ═════════════════════════════════════════════════════════════════════════════
sec "Swap — L3 Memory Fabric"

SWAP_N=$(swapon --show --noheadings 2>/dev/null | wc -l)
gte "Active swap devices" "$SWAP_N" "2" "sudo swapon -a"

STATIC=$(swapon --show --noheadings 2>/dev/null | awk '/swapfile_static/{print "active"; exit}')
eq "Static NVMe swap (32G, prio 10)" "${STATIC:-missing}" "active" "sudo swapon -p 10 /home/active/temp/swapfile_static.img"

LVM=$(swapon --show --noheadings 2>/dev/null | awk '/dm-/{print "active"; exit}')
eq "LVM swap partition (32G, prio -2)" "${LVM:-missing}" "active" "sudo swapon /dev/vg_gateway/lv_swap"

SVC_SS=$(systemctl is-active swapspace 2>/dev/null || echo "inactive")
eq "swapspace daemon (dynamic L3)" "$SVC_SS" "active" "sudo systemctl enable --now swapspace"

ZSWAP=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null)
eq "zswap disabled" "$ZSWAP" "N" "zswap.enabled=0 in GRUB (avoids CPU overhead)"

TOTAL_SWAP=$(free -g | awk '/^Swap:/{print $2}')
info "Total swap capacity" "$TOTAL_SWAP GB total"

sep

# ═════════════════════════════════════════════════════════════════════════════
# 11. I/O — Schedulers & NVMe Tuning
# ═════════════════════════════════════════════════════════════════════════════
sec "I/O — Schedulers & NVMe Tuning"

NVME_SCHED=$(cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null)
has "NVMe scheduler" "$NVME_SCHED" "[none]" "echo none > /sys/block/nvme0n1/queue/scheduler"

NVME_RA=$(cat /sys/block/nvme0n1/queue/read_ahead_kb 2>/dev/null)
eq "NVMe read-ahead" "${NVME_RA} KB" "2048 KB" "udev rule: ATTR{queue/read_ahead_kb}=\"2048\""

NVME_RQ=$(cat /sys/block/nvme0n1/queue/rq_affinity 2>/dev/null)
eq "NVMe rq_affinity" "$NVME_RQ" "2" "echo 2 > /sys/block/nvme0n1/queue/rq_affinity"

NVME_NR=$(cat /sys/block/nvme0n1/queue/nr_requests 2>/dev/null)
info "NVMe nr_requests" "$NVME_NR"

for disk in sda sdb; do
    if [[ -b /dev/$disk ]]; then
        SCHED=$(cat /sys/block/$disk/queue/scheduler 2>/dev/null)
        has "HDD $disk scheduler" "$SCHED" "[mq-deadline]" "echo mq-deadline > /sys/block/$disk/queue/scheduler"
    fi
done

sep

# ═════════════════════════════════════════════════════════════════════════════
# 12. Ollama — Full Configuration
# ═════════════════════════════════════════════════════════════════════════════
sec "Ollama — Service & Configuration"

SVC_OL=$(systemctl is-active ollama 2>/dev/null || echo "inactive")
eq "Ollama service" "$SVC_OL" "active" "sudo systemctl start ollama"

OVR="/etc/systemd/system/ollama.service.d/override.conf"
if [[ -f "$OVR" ]]; then
    OVR_TXT=$(cat "$OVR")
    for var in "${EXPECT_OLLAMA_VARS[@]}"; do
        has "Ollama: $var" "$OVR_TXT" "$var" "Add to $OVR"
    done
else
    no "Ollama override.conf" "missing" "present" "Create $OVR"
fi

# Ollama linker paths
GGML_BASE=$(ldconfig -p 2>/dev/null | grep "libggml-base.so.0" | head -1)
if [[ -n "$GGML_BASE" ]]; then
    ok "libggml-base.so.0 in ldconfig" "registered"
else
    no "libggml-base.so.0 in ldconfig" "missing" "registered" "Add /usr/local/lib/ollama to /etc/ld.so.conf.d/ollama.conf && sudo ldconfig"
fi

OLLAMA_API=$(curl -sf --max-time 3 http://localhost:11434/api/tags 2>/dev/null \
    | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('models',[])))" 2>/dev/null \
    || echo "unreachable")
if [[ "$OLLAMA_API" != "unreachable" ]]; then
    ok "Ollama API" "$OLLAMA_API model(s) available"
else
    meh "Ollama API" "unreachable at :11434" "sudo systemctl restart ollama"
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# 13. Docker
# ═════════════════════════════════════════════════════════════════════════════
sec "Docker — Runtime"

DOCKER_RT=$(docker info 2>/dev/null | awk '/Default Runtime/{print $3}')
if [[ -n "$DOCKER_RT" ]]; then
    eq "Docker default runtime" "$DOCKER_RT" "nvidia" "Configure in /etc/docker/daemon.json"
else
    meh "Docker runtime" "Docker not running" "Docker Desktop or docker.service needed"
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# 14. systemd Services
# ═════════════════════════════════════════════════════════════════════════════
sec "systemd — Key Services"

for svc in ollama nvidia-persistenced swapspace; do
    ST=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    eq "$svc" "$ST" "active" "sudo systemctl enable --now $svc"
done

for svc in nvidia-powercap thp-madvise cpu-governor; do
    RES=$(systemctl show "$svc" --property=Result 2>/dev/null | cut -d= -f2)
    if [[ "$RES" == "success" ]]; then
        ok "$svc (oneshot)" "success"
    else
        ST=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        [[ "$ST" == "active" ]] && ok "$svc" "active" || no "$svc" "${RES:-unknown}" "success" "sudo systemctl restart $svc"
    fi
done

sep

# ═════════════════════════════════════════════════════════════════════════════
# 15. Environment
# ═════════════════════════════════════════════════════════════════════════════
sec "Environment & Wayland"

# Check CUDA in PATH — also check user's .bashrc if running as root/sudo
CUDA_PATH_CHECK="$(echo $PATH)"
if [[ ! "$CUDA_PATH_CHECK" == *"/usr/local/cuda"* ]] && [[ -f /home/aj/.bashrc ]]; then
    CUDA_PATH_CHECK=$(grep -oP '/usr/local/cuda[^\s:]*' /home/aj/.bashrc 2>/dev/null | head -1)
fi
has "CUDA in PATH" "$CUDA_PATH_CHECK" "/usr/local/cuda" "export PATH=/usr/local/cuda/bin:\$PATH"

SESSION=$(echo ${XDG_SESSION_TYPE:-unknown})
if [[ "$SESSION" == "wayland" ]]; then
    ok "Session type" "wayland"
elif [[ "$SESSION" == "unknown" ]]; then
    meh "Session type" "unknown (CLI/SSH — wayland expected in desktop)" ""
else
    no "Session type" "$SESSION" "wayland" "KDE Wayland session expected"
fi

GBM=$(cat /etc/environment 2>/dev/null | grep GBM_BACKEND | cut -d= -f2)
eq "GBM_BACKEND" "${GBM:-N/A}" "nvidia-drm" "Add to /etc/environment"

sep

# ═════════════════════════════════════════════════════════════════════════════
# 16. Network & Firewall
# ═════════════════════════════════════════════════════════════════════════════
sec "Network & Firewall"

UFW=$(sudo ufw status 2>/dev/null | awk 'NR==1{print $2}')
eq "UFW firewall" "${UFW:-unknown}" "active" "sudo ufw enable"

HOST_IP=$(ip -4 addr show 2>/dev/null | awk '/192\.168\.2\./{print $2}' | cut -d/ -f1 | head -1)
[[ -n "$HOST_IP" ]] && ok "LAN IP" "$HOST_IP" || meh "LAN IP" "not found (expected 192.168.2.10)" ""

sep

# ═════════════════════════════════════════════════════════════════════════════
# 17. Thermals & Resources
# ═════════════════════════════════════════════════════════════════════════════
sec "Thermals & Resources"

CPU_TEMP=$(sensors 2>/dev/null | awk '/Package id 0/{gsub(/[+°C]/,"",$4); print $4}' || echo "N/A")
GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null || echo "N/A")
GPU_FAN=$(nvidia-smi --query-gpu=fan.speed --format=csv,noheader 2>/dev/null || echo "N/A")
GPU_PWR=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader 2>/dev/null || echo "N/A")
GPU_CLK=$(nvidia-smi --query-gpu=clocks.current.graphics --format=csv,noheader 2>/dev/null || echo "N/A")
GPU_MEM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null || echo "N/A")

# CPU temp is a real check — flag if above 80°C
CPU_TEMP_INT=${CPU_TEMP%.*}
if [[ "$CPU_TEMP_INT" -le 80 ]] 2>/dev/null; then
    ok "CPU Package temp" "${CPU_TEMP}°C"
elif [[ "$CPU_TEMP_INT" -le 90 ]] 2>/dev/null; then
    meh "CPU Package temp" "${CPU_TEMP}°C (above 80°C high threshold)" "Check cooling / reduce CPU load"
else
    no "CPU Package temp" "${CPU_TEMP}°C" "≤80°C" "CRITICAL: near thermal shutdown (100°C). Stop heavy workloads."
fi

info "GPU temp" "${GPU_TEMP}°C"
info "GPU fan" "$GPU_FAN"
info "GPU power draw" "$GPU_PWR"
info "GPU clock" "$GPU_CLK"
info "GPU VRAM used" "$GPU_MEM_USED"

MEM_USED=$(free -h | awk '/^Mem:/{print $3}')
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_AVAIL=$(free -h | awk '/^Mem:/{print $7}')
SWAP_USED=$(free -h | awk '/^Swap:/{print $3}')
SWAP_TOTAL=$(free -h | awk '/^Swap:/{print $2}')
info "System RAM" "$MEM_USED / $MEM_TOTAL (${MEM_AVAIL} available)"
info "Swap" "$SWAP_USED / $SWAP_TOTAL"

sep

# ═════════════════════════════════════════════════════════════════════════════
# 18. CUDA Version Coherence (v5.0)
# ═════════════════════════════════════════════════════════════════════════════
sec "CUDA — Version Coherence"

NVCC_VER=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9.]+' || echo "N/A")
info "System toolkit (nvcc)" "$NVCC_VER"

DRIVER_CUDA=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "N/A")
info "Driver" "$DRIVER_CUDA (supports CUDA up to 13.1)"

# Check LD_LIBRARY_PATH references a valid CUDA toolkit
LD_LP="${LD_LIBRARY_PATH:-}"
if [[ -z "$LD_LP" ]] && [[ -f /home/aj/.bashrc ]]; then
    LD_LP=$(grep "LD_LIBRARY_PATH.*cuda" /home/aj/.bashrc 2>/dev/null | tail -1 || echo "")
fi
# Verify referenced CUDA dirs actually exist
STALE_CUDA=""
for cuda_ref in $(echo "$LD_LP" | tr ':' '\n' | grep "cuda-" | sort -u); do
    cuda_dir=$(echo "$cuda_ref" | sed 's|/lib64||')
    if [[ ! -d "$cuda_dir" ]]; then
        STALE_CUDA="$cuda_ref"
        break
    fi
done
if [[ -n "$STALE_CUDA" ]]; then
    no "LD_LIBRARY_PATH" "references non-existent $STALE_CUDA" "valid paths only" "Remove stale entries from ~/.bashrc"
else
    ok "LD_LIBRARY_PATH" "all CUDA references valid"
fi

# Check Ollama LLM library
OLLAMA_LIB=$(systemctl show ollama --property=Environment 2>/dev/null | grep -oP 'OLLAMA_LLM_LIBRARY=\K[^ ]+' || echo "N/A")
eq "Ollama LLM library" "$OLLAMA_LIB" "cuda_v12" "CRITICAL: cuda_v13 fails silently → CPU-only fallback"

# Check ollama-cuda.conf for stale cuda_v13 linker path
OLLAMA_CUDA_CONF=$(cat /etc/ld.so.conf.d/ollama-cuda.conf 2>/dev/null || echo "")
if [[ "$OLLAMA_CUDA_CONF" == *"cuda_v13"* ]]; then
    meh "ollama-cuda.conf" "contains cuda_v13 linker path (stale)" "Review /etc/ld.so.conf.d/ollama-cuda.conf"
else
    ok "ollama-cuda.conf" "no stale cuda_v13 references"
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# 19. Storage Pressure (v5.0)
# ═════════════════════════════════════════════════════════════════════════════
sec "Storage — Pressure"

for mp in "/" "/home/active/inference" "/home/active/temp" "/home/active/apps" "/home/apps/models"; do
    if mountpoint -q "$mp" 2>/dev/null || [[ "$mp" == "/" ]]; then
        USE_PCT=$(df --output=pcent "$mp" 2>/dev/null | tail -1 | tr -d ' %')
        FREE_H=$(df -h --output=avail "$mp" 2>/dev/null | tail -1 | tr -d ' ')
        if [[ "${USE_PCT:-0}" -ge 95 ]]; then
            no "Disk $mp" "${USE_PCT}% (${FREE_H} free)" "<95%" "CRITICAL: near full"
        elif [[ "${USE_PCT:-0}" -ge 85 ]]; then
            meh "Disk $mp" "${USE_PCT}% (${FREE_H} free)" "Consider cleanup"
        else
            ok "Disk $mp" "${USE_PCT}% (${FREE_H} free)"
        fi
    fi
done

sep

# ═════════════════════════════════════════════════════════════════════════════
# 20. NVMe Staging Zones (v5.0)
# ═════════════════════════════════════════════════════════════════════════════
sec "NVMe — Model Staging Zones"

STAGING_BASE="/home/active/inference/staging"
for zone in vllm trtllm unsloth llamacpp; do
    if [[ -d "${STAGING_BASE}/${zone}" ]]; then
        ZONE_SIZE=$(du -sh "${STAGING_BASE}/${zone}" 2>/dev/null | awk '{print $1}')
        ok "staging/${zone}" "${ZONE_SIZE}"
    else
        no "staging/${zone}" "missing" "directory exists" "mkdir -p ${STAGING_BASE}/${zone}"
    fi
done

OLLAMA_DIR="/home/active/inference/ollama"
if [[ -d "$OLLAMA_DIR" ]]; then
    OLLAMA_SIZE=$(du -sh "$OLLAMA_DIR" 2>/dev/null | awk '{print $1}')
    ok "ollama/" "$OLLAMA_SIZE"
else
    no "ollama/" "missing" "directory exists" "Ollama should manage this directory"
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# 21. PCIe ASPM (v5.0)
# ═════════════════════════════════════════════════════════════════════════════
sec "PCIe — ASPM Status"

ASPM_STATUS=$(sudo lspci -vvs 00:01.0 2>/dev/null | grep -oP 'LnkCtl:.*ASPM \K\w+' || echo "unknown")
if [[ "$ASPM_STATUS" == "Disabled" ]]; then
    ok "ASPM on GPU root port" "Disabled"
else
    no "ASPM on GPU root port" "$ASPM_STATUS" "Disabled" "Disable ASPM in BIOS: Settings → Advanced → PCI Subsystem Settings"
fi

sep

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo ""
printf "  ${B}${T}┌──────────────────────────────────────────────────────────────┐${NC}\n"
printf "  ${B}${T}│${NC}                                                              ${B}${T}│${NC}\n"
printf "  ${B}${T}│${NC}   ${B}SWEEP RESULTS${NC}  %-42s  ${B}${T}│${NC}\n" "(profile: $PROFILE)"
printf "  ${B}${T}│${NC}                                                              ${B}${T}│${NC}\n"
printf "  ${B}${T}│${NC}   Total checks    ${B}%-4d${NC}                                       ${B}${T}│${NC}\n" "$TOTAL"
printf "  ${B}${T}│${NC}   ${T}Passed${NC}          ${B}%-4d${NC}                                       ${B}${T}│${NC}\n" "$OK"

if [[ "$BAD" -gt 0 ]]; then
    printf "  ${B}${T}│${NC}   ${F}Failed${NC}          ${B}%-4d${NC}  ${F}← action required${NC}                  ${B}${T}│${NC}\n" "$BAD"
else
    printf "  ${B}${T}│${NC}   ${F}Failed${NC}          ${B}%-4d${NC}                                       ${B}${T}│${NC}\n" "$BAD"
fi

if [[ "$MEH" -gt 0 ]]; then
    printf "  ${B}${T}│${NC}   ${W}Warnings${NC}        ${B}%-4d${NC}                                       ${B}${T}│${NC}\n" "$MEH"
fi

printf "  ${B}${T}│${NC}                                                              ${B}${T}│${NC}\n"

PCT=$((OK * 100 / TOTAL))
BAR_LEN=40
FILLED=$((PCT * BAR_LEN / 100))
EMPTY=$((BAR_LEN - FILLED))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

if [[ "$PCT" -ge 95 ]]; then BAR_COLOR="$T"
elif [[ "$PCT" -ge 80 ]]; then BAR_COLOR="$W"
else BAR_COLOR="$F"; fi

printf "  ${B}${T}│${NC}   ${BAR_COLOR}${BAR}${NC} ${B}%d%%${NC}         ${B}${T}│${NC}\n" "$PCT"
printf "  ${B}${T}│${NC}                                                              ${B}${T}│${NC}\n"

if [[ "$BAD" -eq 0 && "$MEH" -eq 0 ]]; then
    printf "  ${B}${T}│${NC}   ${T}${B}All systems nominal. Project Host fully configured.${NC}        ${B}${T}│${NC}\n"
elif [[ "$BAD" -eq 0 ]]; then
    printf "  ${B}${T}│${NC}   ${W}${B}Operational with %d advisory warning(s).${NC}                    ${B}${T}│${NC}\n" "$MEH"
else
    printf "  ${B}${T}│${NC}   ${F}${B}%d check(s) failed — review FIX instructions above.${NC}        ${B}${T}│${NC}\n" "$BAD"
fi

printf "  ${B}${T}│${NC}                                                              ${B}${T}│${NC}\n"
printf "  ${B}${T}└──────────────────────────────────────────────────────────────┘${NC}\n"
echo ""

exit "$BAD"
