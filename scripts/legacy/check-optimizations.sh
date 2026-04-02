#!/usr/bin/env bash
# =============================================================================
# Project Host — Optimization Verification (v3.0)
# Checks only the NEW optimizations applied during the 2026-03-27 tuning session.
# These are the delta checks — things that changed from v2.1 to v3.0.
#
# Usage: ./scripts/check-optimizations.sh [--no-color]
# =============================================================================

set -euo pipefail

# ── Colors (Claude TUI inspired) ────────────────────────────────────────────
if [[ "${1:-}" == "--no-color" ]]; then
    C_PASS="" C_FAIL="" C_WARN="" C_INFO="" C_DIM="" C_BOLD="" C_ACCENT="" NC=""
else
    C_PASS='\033[38;2;127;187;179m'   # Teal green (Claude accent)
    C_FAIL='\033[38;2;230;126;128m'   # Soft red
    C_WARN='\033[38;2;229;192;123m'   # Warm amber
    C_INFO='\033[38;2;133;146;137m'   # Muted sage
    C_DIM='\033[2;37m'                # Dim grey
    C_BOLD='\033[1m'                  # Bold
    C_ACCENT='\033[38;2;167;192;128m' # Soft green (Claude secondary)
    NC='\033[0m'                      # Reset
fi

# ── Counters ─────────────────────────────────────────────────────────────────
CHECKS=0; PASSED=0; FAILED=0; WARNED=0

# ── Helpers ──────────────────────────────────────────────────────────────────
pass() {
    CHECKS=$((CHECKS+1)); PASSED=$((PASSED+1))
    printf "  ${C_PASS}●${NC}  %-46s ${C_DIM}%s${NC}\n" "$1" "$2"
}
fail() {
    CHECKS=$((CHECKS+1)); FAILED=$((FAILED+1))
    printf "  ${C_FAIL}●${NC}  %-46s ${C_FAIL}%s${NC}  ${C_DIM}(expected: %s)${NC}\n" "$1" "$2" "$3"
    if [[ -n "${4:-}" ]]; then
        printf "     ${C_WARN}→${NC} ${C_DIM}%s${NC}\n" "$4"
    fi
}
warn_msg() {
    CHECKS=$((CHECKS+1)); WARNED=$((WARNED+1))
    printf "  ${C_WARN}●${NC}  %-46s ${C_WARN}%s${NC}\n" "$1" "$2"
}

check_eq() {
    local name="$1" actual="$2" expected="$3" fix="${4:-}"
    if [[ "$actual" == "$expected" ]]; then
        pass "$name" "$actual"
    else
        fail "$name" "$actual" "$expected" "$fix"
    fi
}

check_contains() {
    local name="$1" haystack="$2" needle="$3" fix="${4:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$name" "present"
    else
        fail "$name" "missing" "$needle" "$fix"
    fi
}

section() {
    echo ""
    printf "${C_BOLD}${C_ACCENT}  ┌─ %s${NC}\n" "$1"
}

# ── Header ───────────────────────────────────────────────────────────────────
echo ""
printf "${C_BOLD}${C_PASS}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════════════════════════╗
  ║        PROJECT HOST — OPTIMIZATION VERIFICATION v3.0         ║
  ║        Delta checks from 2026-03-27 tuning session           ║
  ╚═══════════════════════════════════════════════════════════════╝
BANNER
printf "${NC}"
printf "  ${C_DIM}%s  •  Kernel %s${NC}\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$(uname -r)"

# ═══════════════════════════════════════════════════════════════════════════════
# 1. GRUB — New kernel boot parameters
# ═══════════════════════════════════════════════════════════════════════════════
section "GRUB — New Boot Parameters"

CMDLINE=$(cat /proc/cmdline 2>/dev/null)
check_contains "init_on_alloc=0"     "$CMDLINE" "init_on_alloc=0"     "Add to GRUB_CMDLINE_LINUX_DEFAULT, run sudo update-grub"
check_contains "nvme.poll_queues=4"  "$CMDLINE" "nvme.poll_queues=4"  "Add to GRUB_CMDLINE_LINUX_DEFAULT, run sudo update-grub"
check_contains "preempt=none"        "$CMDLINE" "preempt=none"        "Add to GRUB_CMDLINE_LINUX_DEFAULT, run sudo update-grub"

# ═══════════════════════════════════════════════════════════════════════════════
# 2. NVIDIA modprobe — New driver options
# ═══════════════════════════════════════════════════════════════════════════════
section "NVIDIA Module — New Driver Options"

NVIDIA_CONF=$(cat /etc/modprobe.d/nvidia.conf 2>/dev/null || echo "")
check_contains "NVreg_EnablePCIERelaxedOrderingMode=1"  "$NVIDIA_CONF" "NVreg_EnablePCIERelaxedOrderingMode=1"  "Add to /etc/modprobe.d/nvidia.conf, rebuild initramfs"
check_contains "NVreg_UsePageAttributeTable=1"           "$NVIDIA_CONF" "NVreg_UsePageAttributeTable=1"           "Add to /etc/modprobe.d/nvidia.conf, rebuild initramfs"
check_contains "NVreg_InitializeSystemMemoryAllocations=0" "$NVIDIA_CONF" "NVreg_InitializeSystemMemoryAllocations=0" "Add to /etc/modprobe.d/nvidia.conf, rebuild initramfs"

# Verify runtime (only works after reboot with new initramfs)
PAT_RUNTIME=$(cat /proc/driver/nvidia/params 2>/dev/null | awk '/UsePageAttributeTable/{print $2}' || echo "N/A")
if [[ "$PAT_RUNTIME" == "1" ]]; then
    pass "PAT active (runtime)" "1"
elif [[ "$PAT_RUNTIME" == "N/A" ]]; then
    warn_msg "PAT active (runtime)" "requires reboot to verify"
else
    fail "PAT active (runtime)" "$PAT_RUNTIME" "1" "Reboot required after initramfs update"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 3. sysctl — Changed values
# ═══════════════════════════════════════════════════════════════════════════════
section "sysctl — Updated Parameters"

check_eq "vm.swappiness"       "$(sysctl -n vm.swappiness 2>/dev/null)"       "1"  "sudo sysctl -w vm.swappiness=1"
check_eq "vm.overcommit_memory" "$(sysctl -n vm.overcommit_memory 2>/dev/null)" "1"  "sudo sysctl -w vm.overcommit_memory=1"
check_eq "vm.overcommit_ratio"  "$(sysctl -n vm.overcommit_ratio 2>/dev/null)"  "80" "sudo sysctl -w vm.overcommit_ratio=80"
check_eq "vm.vfs_cache_pressure" "$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)" "50" "sudo sysctl -w vm.vfs_cache_pressure=50"
check_eq "vm.nr_hugepages"     "$(sysctl -n vm.nr_hugepages 2>/dev/null)"     "16384" "sudo sysctl -w vm.nr_hugepages=16384"

# ═══════════════════════════════════════════════════════════════════════════════
# 4. Ollama — Updated configuration
# ═══════════════════════════════════════════════════════════════════════════════
section "Ollama — Updated Configuration"

OVERRIDE="/etc/systemd/system/ollama.service.d/override.conf"
if [[ -f "$OVERRIDE" ]]; then
    OVR=$(cat "$OVERRIDE")
    check_contains "OLLAMA_MAX_LOADED_MODELS=1"  "$OVR" "OLLAMA_MAX_LOADED_MODELS=1"  "Reduced from 2 to prevent VRAM contention"
    check_contains "OLLAMA_NUM_PARALLEL=2"       "$OVR" "OLLAMA_NUM_PARALLEL=2"       "Reduced from 4 to lower PCIe pressure"
    check_contains "OLLAMA_KV_CACHE_TYPE=q8_0"   "$OVR" "OLLAMA_KV_CACHE_TYPE=q8_0"   "Saves ~2GB VRAM for more GPU layers"
    check_contains "CPUAffinity=0-7"             "$OVR" "CPUAffinity=0-7"             "Pin to P-cores for inference"
    check_contains "OOMScoreAdjust=-900"         "$OVR" "OOMScoreAdjust=-900"         "Protect from OOM killer"
    check_contains "IOWeight=900"                "$OVR" "IOWeight=900"                "Prioritize inference I/O"
    check_contains "Nice=-5"                     "$OVR" "Nice=-5"                     "Scheduling priority"
else
    fail "Ollama override.conf" "missing" "present" "Create /etc/systemd/system/ollama.service.d/override.conf"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 5. NVMe — Updated tuning
# ═══════════════════════════════════════════════════════════════════════════════
section "NVMe — Updated Tuning"

RQ_AFF=$(cat /sys/block/nvme0n1/queue/rq_affinity 2>/dev/null || echo "N/A")
check_eq "NVMe rq_affinity" "$RQ_AFF" "2" "echo 2 | sudo tee /sys/block/nvme0n1/queue/rq_affinity"

UDEV_RULES=$(cat /etc/udev/rules.d/99-nvme-readahead.rules 2>/dev/null || echo "")
check_contains "rq_affinity" "$UDEV_RULES" "rq_affinity" "Add ATTR{queue/rq_affinity}=\"2\" to udev rule"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. CPU C-states
# ═══════════════════════════════════════════════════════════════════════════════
section "CPU — C-State Configuration"

C2_DISABLE=$(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable 2>/dev/null || echo "N/A")
if [[ "$C2_DISABLE" == "1" ]]; then
    pass "C2 deep sleep disabled" "disabled"
else
    warn_msg "C2 deep sleep" "still enabled (disable after reboot or via cpupower idle-set -d 2)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
printf "${C_BOLD}${C_PASS}  ┌─────────────────────────────────────────────────────────────┐${NC}\n"
printf "${C_BOLD}${C_PASS}  │${NC}  ${C_BOLD}RESULTS${NC}                                                     ${C_BOLD}${C_PASS}│${NC}\n"
printf "${C_BOLD}${C_PASS}  ├─────────────────────────────────────────────────────────────┤${NC}\n"
printf "${C_BOLD}${C_PASS}  │${NC}  Total    ${C_BOLD}%-4d${NC}                                                ${C_BOLD}${C_PASS}│${NC}\n" "$CHECKS"
printf "${C_BOLD}${C_PASS}  │${NC}  ${C_PASS}Passed${NC}   ${C_BOLD}%-4d${NC}                                                ${C_BOLD}${C_PASS}│${NC}\n" "$PASSED"
if [[ "$FAILED" -gt 0 ]]; then
    printf "${C_BOLD}${C_PASS}  │${NC}  ${C_FAIL}Failed${NC}   ${C_BOLD}%-4d${NC}  ${C_FAIL}← reboot required for most${NC}            ${C_BOLD}${C_PASS}│${NC}\n" "$FAILED"
else
    printf "${C_BOLD}${C_PASS}  │${NC}  ${C_FAIL}Failed${NC}   ${C_BOLD}%-4d${NC}                                                ${C_BOLD}${C_PASS}│${NC}\n" "$FAILED"
fi
if [[ "$WARNED" -gt 0 ]]; then
    printf "${C_BOLD}${C_PASS}  │${NC}  ${C_WARN}Pending${NC}  ${C_BOLD}%-4d${NC}  ${C_DIM}reboot to activate${NC}                      ${C_BOLD}${C_PASS}│${NC}\n" "$WARNED"
fi
printf "${C_BOLD}${C_PASS}  └─────────────────────────────────────────────────────────────┘${NC}\n"
echo ""

if [[ "$FAILED" -eq 0 && "$WARNED" -eq 0 ]]; then
    printf "  ${C_PASS}${C_BOLD}All v3.0 optimizations active.${NC}\n"
elif [[ "$FAILED" -eq 0 ]]; then
    printf "  ${C_WARN}${C_BOLD}Config written — reboot to activate pending changes.${NC}\n"
else
    printf "  ${C_FAIL}${C_BOLD}%d optimization(s) not applied. Review above.${NC}\n" "$FAILED"
fi
echo ""

exit "$FAILED"
