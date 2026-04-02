#!/usr/bin/env bash
# =============================================================================
# Project Host — System Health Check
# Verifies all documented configuration parameters post-boot.
# Color-coded results with fix instructions for every failure.
#
# Usage: ./scripts/health-check.sh [--no-color] [--section GPU|KERNEL|...]
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--no-color" ]]; then
    PASS=""; FAIL=""; WARN=""; INFO=""; DIM=""; BOLD=""; NC=""
else
    PASS='\033[0;32m'       # Green
    FAIL='\033[0;31m'       # Red
    WARN='\033[1;33m'       # Yellow
    INFO='\033[0;36m'       # Cyan
    DIM='\033[2;37m'        # Dim grey
    BOLD='\033[1m'          # Bold
    NC='\033[0m'            # Reset
fi

# ── Counters ──────────────────────────────────────────────────────────────────
CHECKS=0; PASSED=0; FAILED=0; WARNED=0

# ── Helpers ───────────────────────────────────────────────────────────────────

# check NAME ACTUAL EXPECTED [FIX]
# Prints a pass/fail row. Exact string match.
check() {
    local name="$1" actual="$2" expected="$3" fix="${4:-}"
    CHECKS=$((CHECKS+1))
    if [[ "$actual" == "$expected" ]]; then
        PASSED=$((PASSED+1))
        printf "  ${PASS}✔${NC}  %-42s ${DIM}%s${NC}\n" "$name" "$actual"
    else
        FAILED=$((FAILED+1))
        printf "  ${FAIL}✘${NC}  %-42s ${FAIL}%s${NC}  ${DIM}(expected: %s)${NC}\n" "$name" "$actual" "$expected"
        if [[ -n "$fix" ]]; then
            printf "     ${WARN}↳ FIX:${NC} %s\n" "$fix"
        fi
    fi
}

# check_contains NAME ACTUAL SUBSTRING [FIX]
check_contains() {
    local name="$1" actual="$2" substring="$3" fix="${4:-}"
    CHECKS=$((CHECKS+1))
    if [[ "$actual" == *"$substring"* ]]; then
        PASSED=$((PASSED+1))
        printf "  ${PASS}✔${NC}  %-42s ${DIM}%s${NC}\n" "$name" "$actual"
    else
        FAILED=$((FAILED+1))
        printf "  ${FAIL}✘${NC}  %-42s ${FAIL}MISSING: %s${NC}\n" "$name" "$substring"
        printf "     ${DIM}full value: %s${NC}\n" "$actual"
        if [[ -n "$fix" ]]; then
            printf "     ${WARN}↳ FIX:${NC} %s\n" "$fix"
        fi
    fi
}

# check_gte NAME ACTUAL MIN [FIX]
check_gte() {
    local name="$1" actual="$2" min="$3" fix="${4:-}"
    CHECKS=$((CHECKS+1))
    if [[ "$actual" -ge "$min" ]] 2>/dev/null; then
        PASSED=$((PASSED+1))
        printf "  ${PASS}✔${NC}  %-42s ${DIM}%s${NC}\n" "$name" "$actual"
    else
        FAILED=$((FAILED+1))
        printf "  ${FAIL}✘${NC}  %-42s ${FAIL}%s${NC}  ${DIM}(expected: ≥ %s)${NC}\n" "$name" "$actual" "$min"
        if [[ -n "$fix" ]]; then
            printf "     ${WARN}↳ FIX:${NC} %s\n" "$fix"
        fi
    fi
}

# warn NAME MSG NOTE
warn() {
    local name="$1" msg="$2" note="${3:-}"
    WARNS=$((WARNED+1))
    WARNED=$((WARNED+1))
    printf "  ${WARN}⚠${NC}  %-42s ${WARN}%s${NC}\n" "$name" "$msg"
    if [[ -n "$note" ]]; then
        printf "     ${DIM}↳ %s${NC}\n" "$note"
    fi
}

section() {
    echo ""
    printf "${BOLD}${INFO}══ %s ══${NC}\n" "$1"
}

# ── Header ────────────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}${INFO}"
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║             PROJECT HOST — SYSTEM HEALTH CHECK                      ║"
printf "║  %-68s║\n" "$(date '+%A %Y-%m-%d %H:%M:%S %Z')"
printf "║  %-68s║\n" "Kernel: $(uname -r)"
echo "╚══════════════════════════════════════════════════════════════════════╝"
printf "${NC}"

# =============================================================================
# 1. GPU — NVIDIA Driver & Power
# =============================================================================
section "1 · GPU — Driver, Power & Persistence"

DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "N/A")
check "Driver Version" "$DRIVER" "590.48.01" \
    "Install correct driver: sudo apt install nvidia-driver-590"

POWER_LIMIT=$(nvidia-smi -q -d power 2>/dev/null | awk '/Current Power Limit/{print $5; exit}' || echo "N/A")
check "GPU Power Limit" "${POWER_LIMIT} W" "140.00 W" \
    "Apply cap: sudo nvidia-smi -pl 140  |  Then fix boot race: add 'Restart=on-failure' to /etc/systemd/system/nvidia-powerlimit.service and run sudo systemctl daemon-reload"

PERSISTENCE=$(nvidia-smi -q 2>/dev/null | awk '/Persistence Mode/{print $4; exit}' || echo "N/A")
check "Persistence Mode" "$PERSISTENCE" "Enabled" \
    "Enable: sudo nvidia-smi -pm 1  |  Ensure nvidia-persistenced.service is enabled: sudo systemctl enable --now nvidia-persistenced"

SVC_PERSIST=$(systemctl is-active nvidia-persistenced 2>/dev/null || echo "inactive")
check "nvidia-persistenced service" "$SVC_PERSIST" "active" \
    "sudo systemctl enable --now nvidia-persistenced"

SVC_POWERLIMIT=$(systemctl is-active nvidia-powerlimit 2>/dev/null || echo "inactive")
if [[ "$SVC_POWERLIMIT" == "active" ]]; then
    check "nvidia-powerlimit service" "$SVC_POWERLIMIT" "active"
else
    # oneshot services show 'inactive' after successful exit — check the result
    POWERLIMIT_RESULT=$(systemctl show nvidia-powerlimit --property=Result 2>/dev/null | cut -d= -f2)
    if [[ "$POWERLIMIT_RESULT" == "success" ]]; then
        PASSED=$((PASSED+1)); CHECKS=$((CHECKS+1))
        printf "  ${PASS}✔${NC}  %-42s ${DIM}%s (oneshot, exited cleanly)${NC}\n" "nvidia-powerlimit service" "success"
    else
        FAILED=$((FAILED+1)); CHECKS=$((CHECKS+1))
        printf "  ${FAIL}✘${NC}  %-42s ${FAIL}%s (result: %s)${NC}\n" "nvidia-powerlimit service" "$SVC_POWERLIMIT" "$POWERLIMIT_RESULT"
        printf "     ${WARN}↳ FIX:${NC} sudo systemctl start nvidia-powerlimit  |  If dependency error: sudo nvidia-smi -pl 140 then check nvidia-persistenced started cleanly\n"
    fi
fi

# =============================================================================
# 2. GPU — BAR1 & PCIe
# =============================================================================
section "2 · GPU — BAR1 & PCIe Link"

BAR1=$(sudo lspci -vv -s 01:00.0 2>/dev/null | awk '/Memory.*prefetchable.*size=/{match($0,/size=([0-9]+)([MG])/,a); if(a[2]=="G") print a[1]*1024; else print a[1]; exit}' 2>/dev/null || echo "")
if [[ -z "$BAR1" ]]; then
    # Fallback: parse nvidia-smi BAR1 section
    BAR1=$(nvidia-smi -q 2>/dev/null | awk '/BAR1 Memory Usage/{found=1} found && /Total/{gsub(" MiB",""); print $NF; exit}' || echo "N/A")
fi
check "BAR1 Total (Resizable BAR)" "$BAR1 MiB" "16384 MiB" \
    "Enable 'Above 4G Decoding' + 'Resizable BAR' in BIOS, then reboot"

PCIE_GEN=$(sudo lspci -vv -s 01:00.0 2>/dev/null | awk '/LnkSta:/{for(i=1;i<=NF;i++) if($i~/Speed/) {gsub("GT/s,","",$(i+1)); print $(i+1); exit}}' || echo "N/A")
# Translate GT/s to Gen number: 2.5=Gen1, 5=Gen2, 8=Gen3, 16=Gen4, 32=Gen5
case "$PCIE_GEN" in
    "16") PCIE_GEN_LABEL="Gen4 (16GT/s)" ; PCIE_GEN_CHECK="Gen4 (16GT/s)" ;;
    "32") PCIE_GEN_LABEL="Gen5 (32GT/s)" ; PCIE_GEN_CHECK="Gen4 (16GT/s)" ;;  # faster than expected = ok
    "8")  PCIE_GEN_LABEL="Gen3 (8GT/s)"  ; PCIE_GEN_CHECK="" ;;
    *)    PCIE_GEN_LABEL="$PCIE_GEN GT/s" ; PCIE_GEN_CHECK="" ;;
esac
check "PCIe Link Speed" "$PCIE_GEN_LABEL" "Gen4 (16GT/s)" \
    "Set PCIe speed to Gen4 in BIOS | Verify 'pcie_aspm=off' is in GRUB cmdline"

PCIE_WIDTH=$(sudo lspci -vv -s 01:00.0 2>/dev/null | awk '/LnkSta:/{for(i=1;i<=NF;i++) if($i~/Width/) {gsub(",","",$(i+1)); print $(i+1); exit}}' || echo "N/A")
check "PCIe Link Width" "$PCIE_WIDTH" "x8" \
    "Check motherboard slot — this CPU supports max x8 (shared lanes). Verify no BIOS setting is limiting it."

# =============================================================================
# 3. GPU — UVM / GPU Direct Memory
# =============================================================================
section "3 · GPU — UVM & GPU Direct Memory"

UVM_CACHE=$(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_sysmem 2>/dev/null || echo "N/A")
check "UVM cache_sysmem" "$UVM_CACHE" "1" \
    "Add to /etc/modprobe.d/nvidia-uvm-optimized.conf: 'options nvidia-uvm uvm_exp_gpu_cache_sysmem=1' then sudo update-initramfs -u && reboot"

UVM_PREFETCH=$(cat /sys/module/nvidia_uvm/parameters/uvm_perf_prefetch_threshold 2>/dev/null || echo "N/A")
check "UVM prefetch_threshold" "$UVM_PREFETCH" "75" \
    "Add to /etc/modprobe.d/nvidia-uvm-optimized.conf: 'options nvidia-uvm uvm_perf_prefetch_threshold=75'"

NVIDIA_FS=$(lsmod 2>/dev/null | awk '/^nvidia_fs/{print "loaded"; exit}')
check "nvidia_fs module (GPU Direct Storage)" "${NVIDIA_FS:-not loaded}" "loaded" \
    "sudo modprobe nvidia_fs | For persistence add 'nvidia_fs' to /etc/modules"

CHECKS=$((CHECKS+1))
if grep -q "uvm_exp_gpu_cache_sysmem=1" /etc/modprobe.d/nvidia-uvm-optimized.conf 2>/dev/null; then
    PASSED=$((PASSED+1))
    printf "  ${PASS}✔${NC}  %-42s ${DIM}present${NC}\n" "UVM modprobe config exists"
else
    FAILED=$((FAILED+1))
    printf "  ${FAIL}✘${NC}  %-42s ${FAIL}missing or incomplete${NC}\n" "UVM modprobe config exists"
    printf "     ${WARN}↳ FIX:${NC} Create /etc/modprobe.d/nvidia-uvm-optimized.conf — see docs/reference/gpu-direct-memory.md\n"
fi

# =============================================================================
# 4. GRUB / Kernel Boot Parameters
# =============================================================================
section "4 · GRUB / Kernel Boot Parameters"

CMDLINE=$(cat /proc/cmdline 2>/dev/null || echo "")
# For GRUB checks, show just the flag name and present/missing — not the full cmdline
grub_check() {
    local flag="$1" fix="$2"
    CHECKS=$((CHECKS+1))
    if [[ "$CMDLINE" == *"$flag"* ]]; then
        PASSED=$((PASSED+1))
        printf "  ${PASS}✔${NC}  %-42s ${DIM}present${NC}\n" "GRUB: $flag"
    else
        FAILED=$((FAILED+1))
        printf "  ${FAIL}✘${NC}  %-42s ${FAIL}MISSING${NC}\n" "GRUB: $flag"
        printf "     ${WARN}↳ FIX:${NC} %s\n" "$fix"
    fi
}
grub_check "nvidia-drm.modeset=1" "Add to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub then sudo update-grub && reboot"
grub_check "pcie_aspm=off"        "Add to GRUB_CMDLINE_LINUX_DEFAULT — prevents PCIe link-speed downshifts"
grub_check "zswap.enabled=0"      "Add to GRUB_CMDLINE_LINUX_DEFAULT — zswap causes CPU spikes during inference"
grub_check "transparent_hugepage=madvise" "Add to GRUB_CMDLINE_LINUX_DEFAULT"
grub_check "intel_iommu=on"       "Add 'intel_iommu=on iommu=pt' to GRUB_CMDLINE_LINUX_DEFAULT"
grub_check "iommu=pt"             "Add 'iommu=pt' alongside 'intel_iommu=on' in GRUB_CMDLINE_LINUX_DEFAULT"

# =============================================================================
# 5. Kernel sysctl — Memory
# =============================================================================
section "5 · Kernel sysctl — Memory"

check "vm.swappiness" "$(sysctl -n vm.swappiness 2>/dev/null)" "10" \
    "sudo sysctl -w vm.swappiness=10 | Persist in /etc/sysctl.d/99-inference.conf"
check "vm.nr_hugepages" "$(sysctl -n vm.nr_hugepages 2>/dev/null)" "4096" \
    "sudo sysctl -w vm.nr_hugepages=4096 | Persist in /etc/sysctl.d/99-inference.conf"
check "vm.compaction_proactiveness" "$(sysctl -n vm.compaction_proactiveness 2>/dev/null)" "0" \
    "sudo sysctl -w vm.compaction_proactiveness=0 | Persist in /etc/sysctl.d/99-inference.conf"
check "kernel.numa_balancing" "$(sysctl -n kernel.numa_balancing 2>/dev/null)" "0" \
    "sudo sysctl -w kernel.numa_balancing=0 | Persist in /etc/sysctl.d/99-inference.conf"
check "vm.max_map_count" "$(sysctl -n vm.max_map_count 2>/dev/null)" "1048576" \
    "sudo sysctl -w vm.max_map_count=1048576 | Persist in /etc/sysctl.d/99-inference.conf"
check "vm.dirty_background_bytes" "$(sysctl -n vm.dirty_background_bytes 2>/dev/null)" "1610612736" \
    "sudo sysctl -w vm.dirty_background_bytes=1610612736 | Persist in /etc/sysctl.d/99-inference.conf"
check "vm.dirty_bytes" "$(sysctl -n vm.dirty_bytes 2>/dev/null)" "4294967296" \
    "sudo sysctl -w vm.dirty_bytes=4294967296 | Persist in /etc/sysctl.d/99-inference.conf"
check "vm.vfs_cache_pressure" "$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)" "80" \
    "sudo sysctl -w vm.vfs_cache_pressure=80 | Persist in /etc/sysctl.d/99-inference.conf"

# =============================================================================
# 6. Kernel sysctl — Network
# =============================================================================
section "6 · Kernel sysctl — Network"

check "net.ipv4.tcp_fastopen" "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)" "3" \
    "sudo sysctl -w net.ipv4.tcp_fastopen=3 | Persist in /etc/sysctl.d/99-inference.conf"
check "net.core.rmem_max" "$(sysctl -n net.core.rmem_max 2>/dev/null)" "16777216" \
    "sudo sysctl -w net.core.rmem_max=16777216 | Persist in /etc/sysctl.d/99-inference.conf"
check "net.core.wmem_max" "$(sysctl -n net.core.wmem_max 2>/dev/null)" "16777216" \
    "sudo sysctl -w net.core.wmem_max=16777216 | Persist in /etc/sysctl.d/99-inference.conf"

# =============================================================================
# 7. Kernel sysctl — Filesystem
# =============================================================================
section "7 · Kernel sysctl — Filesystem"

check "fs.inotify.max_user_watches" "$(sysctl -n fs.inotify.max_user_watches 2>/dev/null)" "524288" \
    "sudo sysctl -w fs.inotify.max_user_watches=524288 | Persist in /etc/sysctl.d/99-inference.conf"

# =============================================================================
# 8. THP, HugePages & KSM
# =============================================================================
section "8 · Memory — THP, HugePages & KSM"

THP_ENABLED=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "N/A")
check_contains "THP mode (madvise)" "$THP_ENABLED" "[madvise]" \
    "Add 'transparent_hugepage=madvise' to GRUB cmdline | Or: echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"

THP_DEFRAG=$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || echo "N/A")
check_contains "THP defrag (madvise)" "$THP_DEFRAG" "[madvise]" \
    "echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/defrag | Persist via /etc/tmpfiles.d/99-inference.conf"

KSM=$(cat /sys/kernel/mm/ksm/run 2>/dev/null || echo "N/A")
check "KSM disabled (run=0)" "$KSM" "0" \
    "echo 0 | sudo tee /sys/kernel/mm/ksm/run | Persist via /etc/tmpfiles.d/99-inference.conf"

HUGEPAGES=$(grep HugePages_Total /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
check "HugePages_Total (4096 × 2MB = 8GB)" "$HUGEPAGES" "4096" \
    "sudo sysctl -w vm.nr_hugepages=4096 | Persist in /etc/sysctl.d/99-inference.conf | Note: requires contiguous memory — works best at boot"

# =============================================================================
# 9. CPU
# =============================================================================
section "9 · CPU — Governor & Turbo"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
check "CPU Governor" "$GOV" "performance" \
    "sudo cpupower frequency-set -g performance | Persist via cpu-governor.service: sudo systemctl enable --now cpu-governor"

TURBO=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "N/A")
check "Intel Turbo enabled (no_turbo=0)" "$TURBO" "0" \
    "echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo"

SVC_CPUGOV=$(systemctl is-active cpu-governor 2>/dev/null || echo "inactive")
check "cpu-governor service" "$SVC_CPUGOV" "active" \
    "sudo systemctl enable --now cpu-governor"

# =============================================================================
# 10. Swap / L3 Memory Fabric
# =============================================================================
section "10 · Swap — L3 Memory Fabric"

SWAP_COUNT=$(swapon --show --noheadings 2>/dev/null | wc -l || echo "0")
check_gte "Active swap devices (≥ 2)" "$SWAP_COUNT" "2" \
    "Check fstab entries for /dev/vg_gateway/lv_swap and /home/active/temp/swapfile_static.img | sudo swapon -a"

STATIC_SWAP=$(swapon --show --noheadings 2>/dev/null | awk '/swapfile_static/{print "active"; exit}' || echo "missing")
check "Static NVMe swap file (32G prio 10)" "$STATIC_SWAP" "active" \
    "Verify file exists: ls -lh /home/active/temp/swapfile_static.img | If missing: sudo dd if=/dev/zero of=/home/active/temp/swapfile_static.img bs=1G count=32 && sudo mkswap /home/active/temp/swapfile_static.img && sudo swapon -p 10 /home/active/temp/swapfile_static.img"

LVM_SWAP=$(swapon --show --noheadings 2>/dev/null | awk '/dm-/{print "active"; exit}' || echo "missing")
check "LVM swap partition (32G prio -2)" "$LVM_SWAP" "active" \
    "sudo swapon -p -2 /dev/vg_gateway/lv_swap | Verify entry in /etc/fstab"

SVC_SWAPSPACE=$(systemctl is-active swapspace 2>/dev/null || echo "inactive")
check "swapspace service (dynamic L3)" "$SVC_SWAPSPACE" "active" \
    "sudo systemctl enable --now swapspace | Verify config: cat /etc/swapspace.conf"

DYNAMIC_DIR_EXISTS=$([[ -d /home/active/temp/dynamic_swap ]] && echo "yes" || echo "no")
check "Dynamic swap dir exists" "$DYNAMIC_DIR_EXISTS" "yes" \
    "sudo mkdir -p /home/active/temp/dynamic_swap | Update /etc/swapspace.conf: swappath=/home/active/temp/dynamic_swap"

# =============================================================================
# 11. I/O Subsystem
# =============================================================================
section "11 · I/O — Schedulers & Readahead"

NVME_SCHED=$(cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null || echo "N/A")
check_contains "NVMe scheduler (none)" "$NVME_SCHED" "[none]" \
    "echo none | sudo tee /sys/block/nvme0n1/queue/scheduler | Persist via /etc/udev/rules.d/99-nvme-readahead.rules"

NVME_RA=$(cat /sys/block/nvme0n1/queue/read_ahead_kb 2>/dev/null || echo "N/A")
check "NVMe read-ahead (2048 KB)" "$NVME_RA" "2048" \
    "echo 2048 | sudo tee /sys/block/nvme0n1/queue/read_ahead_kb | Persist: add udev rule ACTION==\"add|change\",KERNEL==\"nvme[0-9]*\",ATTR{queue/read_ahead_kb}=\"2048\" to /etc/udev/rules.d/99-nvme-readahead.rules"

# Check HDDs (sda, sdb) if present
for disk in sda sdb; do
    if [[ -b /dev/$disk ]]; then
        SCHED=$(cat /sys/block/$disk/queue/scheduler 2>/dev/null || echo "N/A")
        check_contains "HDD $disk scheduler (mq-deadline)" "$SCHED" "[mq-deadline]" \
            "echo mq-deadline | sudo tee /sys/block/$disk/queue/scheduler | Persist via udev rule for rotational storage"
    fi
done

# =============================================================================
# 12. Systemd Services
# =============================================================================
section "12 · systemd Services"

for svc in ollama nvidia-persistenced swapspace fullmetal-watchdog; do
    SVC_STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    check "$svc service" "$SVC_STATE" "active" \
        "sudo systemctl enable --now $svc"
done

# thp-madvise and cpu-governor are oneshot — check result
for svc in thp-madvise cpu-governor; do
    SVC_STATE=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    RESULT=$(systemctl show "$svc" --property=Result 2>/dev/null | cut -d= -f2)
    if [[ "$RESULT" == "success" || "$SVC_STATE" == "active" ]]; then
        PASSED=$((PASSED+1)); CHECKS=$((CHECKS+1))
        printf "  ${PASS}✔${NC}  %-42s ${DIM}%s (oneshot/exited)${NC}\n" "$svc service" "$RESULT"
    else
        FAILED=$((FAILED+1)); CHECKS=$((CHECKS+1))
        printf "  ${FAIL}✘${NC}  %-42s ${FAIL}%s (result: %s)${NC}\n" "$svc service" "$SVC_STATE" "$RESULT"
        printf "     ${WARN}↳ FIX:${NC} sudo systemctl restart %s  |  Check logs: journalctl -u %s\n" "$svc" "$svc"
    fi
done

# =============================================================================
# 13. Ollama Configuration
# =============================================================================
section "13 · Ollama — Configuration & API"

OVERRIDE_FILE="/etc/systemd/system/ollama.service.d/override.conf"
OVERRIDE_EXISTS=$([[ -f "$OVERRIDE_FILE" ]] && echo "yes" || echo "no")
check "Ollama override.conf exists" "$OVERRIDE_EXISTS" "yes" \
    "Create /etc/systemd/system/ollama.service.d/override.conf — see docs/reference/ollama.md for contents"

if [[ -f "$OVERRIDE_FILE" ]]; then
    OVERRIDE=$(cat "$OVERRIDE_FILE")
    for var in "OLLAMA_HOST=0.0.0.0" "OLLAMA_FLASH_ATTENTION=1" "OLLAMA_NUM_GPU=99" \
               "OLLAMA_KEEP_ALIVE=24h" "OLLAMA_MAX_LOADED_MODELS=2" "OLLAMA_NUM_PARALLEL=4" \
               "CUDA_VISIBLE_DEVICES=0" "GGML_CUDA_ENABLE_UNIFIED_MEMORY=1"; do
        CHECKS=$((CHECKS+1))
        if grep -qF "$var" "$OVERRIDE_FILE"; then
            PASSED=$((PASSED+1))
            printf "  ${PASS}✔${NC}  %-42s ${DIM}set${NC}\n" "Ollama env: $var"
        else
            FAILED=$((FAILED+1))
            printf "  ${FAIL}✘${NC}  %-42s ${FAIL}missing${NC}\n" "Ollama env: $var"
            printf "     ${WARN}↳ FIX:${NC} Add Environment=\"%s\" to %s then sudo systemctl daemon-reload && sudo systemctl restart ollama\n" "$var" "$OVERRIDE_FILE"
        fi
    done
fi

OLLAMA_MODELS_PATH=$(systemctl show ollama --property=Environment 2>/dev/null | tr ' ' '\n' | grep OLLAMA_MODELS | cut -d= -f2 || echo "")
MODELS_DIR_OK=$([[ -d "${OLLAMA_MODELS_PATH:-/home/apps/models/ollama}" ]] && echo "yes" || echo "no")
check "Ollama models dir exists" "$MODELS_DIR_OK" "yes" \
    "Create dir: sudo mkdir -p /home/apps/models/ollama | Update OLLAMA_MODELS in override.conf"

OLLAMA_API=$(curl -s --max-time 3 http://localhost:11434/api/tags 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('models',[])))" 2>/dev/null || echo "unreachable")
if [[ "$OLLAMA_API" == "unreachable" ]]; then
    FAILED=$((FAILED+1)); CHECKS=$((CHECKS+1))
    printf "  ${FAIL}✘${NC}  %-42s ${FAIL}%s${NC}\n" "Ollama API" "unreachable at :11434"
    printf "     ${WARN}↳ FIX:${NC} sudo systemctl restart ollama | Check: journalctl -u ollama -n 30\n"
else
    PASSED=$((PASSED+1)); CHECKS=$((CHECKS+1))
    printf "  ${PASS}✔${NC}  %-42s ${DIM}%s model(s) available${NC}\n" "Ollama API" "$OLLAMA_API"
fi

# =============================================================================
# 14. Firewall
# =============================================================================
section "14 · Network & Firewall"

UFW_STATUS=$(sudo ufw status 2>/dev/null | awk 'NR==1{print $2}' || echo "unknown")
check "UFW firewall status" "$UFW_STATUS" "active" \
    "sudo ufw enable | Then allow LAN: sudo ufw allow from 192.168.2.0/24"

HOST_IP=$(ip -4 addr show 2>/dev/null | awk '/192\.168\.2\./{print $2}' | cut -d/ -f1 | head -1 || echo "unknown")
if [[ -n "$HOST_IP" && "$HOST_IP" != "unknown" ]]; then
    PASSED=$((PASSED+1)); CHECKS=$((CHECKS+1))
    printf "  ${PASS}✔${NC}  %-42s ${DIM}%s${NC}\n" "LAN IP" "$HOST_IP"
else
    WARNED=$((WARNED+1)); CHECKS=$((CHECKS+1))
    printf "  ${WARN}⚠${NC}  %-42s ${WARN}not found${NC}\n" "LAN IP (expected 192.168.2.10)"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
printf "${BOLD}${INFO}══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  SUMMARY${NC}\n"
echo ""
printf "  Total checks  : ${BOLD}%d${NC}\n" "$CHECKS"
printf "  ${PASS}Passed${NC}        : ${BOLD}%d${NC}\n" "$PASSED"
if [[ "$FAILED" -gt 0 ]]; then
    printf "  ${FAIL}Failed${NC}        : ${BOLD}%d${NC}  ← action required\n" "$FAILED"
else
    printf "  ${FAIL}Failed${NC}        : ${BOLD}%d${NC}\n" "$FAILED"
fi
if [[ "$WARNED" -gt 0 ]]; then
    printf "  ${WARN}Warnings${NC}      : ${BOLD}%d${NC}\n" "$WARNED"
fi
echo ""

if [[ "$FAILED" -eq 0 ]]; then
    printf "  ${PASS}${BOLD}✔ All systems nominal. Project Host is fully configured.${NC}\n"
else
    printf "  ${FAIL}${BOLD}✘ %d check(s) failed. Review FIX instructions above.${NC}\n" "$FAILED"
fi
printf "${BOLD}${INFO}══════════════════════════════════════════════════════════════${NC}\n"
echo ""

# Exit with failure code if any checks failed (useful for CI/cron alerting)
exit "$FAILED"
