#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=============================================================="
echo -e "   RTX 4060 Ti & 96GB DDR5 AI MAXIMIZATION CHECKLIST"
echo -e "==============================================================${NC}"

# 1. Check Resizable BAR (Critical for 96GB Overflows)
BAR_SIZE=$(nvidia-smi -q -d MEMORY | grep -A 3 "BAR1" | grep "Total" | awk '{print $3}')
echo -n "1. Resizable BAR (ReBAR) Status: "
if [ "$BAR_SIZE" == "16384" ]; then
    echo -e "${GREEN}OPTIMIZED ($BAR_SIZE MiB)${NC}"
else
    echo -e "${RED}THROTTLED ($BAR_SIZE MiB)${NC} -> Enable 'Above 4G Decoding' & 'Re-Size BAR' in motherboard BIOS."
fi

# 2. Check PCIe Link Speed (The 16GT/s Gen4 Target)
LINK_SPEED=$(sudo lspci -vv -s 01:00.0 | grep "LnkSta:" | grep -o "Speed [^,]*" | cut -d' ' -f2)
echo -n "2. PCIe Link Speed: "
if [[ "$LINK_SPEED" == "16GT/s" ]]; then
    echo -e "${GREEN}OPTIMIZED ($LINK_SPEED - Gen4)${NC}"
else
    echo -e "${RED}DOWNGRADED ($LINK_SPEED)${NC} -> Set PCIe to 'Gen4' in BIOS & check 'pcie_aspm=off' in GRUB."
fi

# 3. Check NVIDIA Persistence Mode
PM_MODE=$(nvidia-smi -q | grep "Persistence Mode" | awk '{print $4}')
echo -n "3. Driver Persistence Mode: "
if [ "$PM_MODE" == "Enabled" ]; then
    echo -e "${GREEN}ENABLED${NC}"
else
    echo -e "${YELLOW}DISABLED${NC} -> Run: sudo nvidia-smi -pm 1"
fi

# 4. Check GPU Clock Lock (2500MHz Target)
CUR_CLK=$(nvidia-smi --query-gpu=clocks.gr --format=csv,noheader,nounits)
echo -n "4. GPU Clock State: "
if [ "$CUR_CLK" -ge 2400 ]; then
    echo -e "${GREEN}LOCKED ($CUR_CLK MHz)${NC}"
else
    echo -e "${YELLOW}IDLE/DYNAMIC ($CUR_CLK MHz)${NC} -> Run: sudo nvidia-smi -lgc 2500"
fi

# 5. Check System RAM (The 96GB DDR5)
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
echo -n "5. System RAM Capacity: "
if [ "$TOTAL_RAM" -ge 90 ]; then
    echo -e "${GREEN}READY ($TOTAL_RAM GB DDR5)${NC}"
else
    echo -e "${RED}UNDER-REPORTED ($TOTAL_RAM GB)${NC} -> Check mismatched stick seating."
fi

# 6. Check GRUB Parameters
GRUB_CHECK=$(cat /proc/cmdline)
echo -n "6. Linux Kernel Optimization: "
if [[ $GRUB_CHECK == *"pcie_aspm=off"* ]] && [[ $GRUB_CHECK == *"nvidia-drm.modeset=1"* ]]; then
    echo -e "${GREEN}CONFIGURED${NC}"
else
    echo -e "${RED}MISSING FLAGS${NC} -> Add 'pcie_aspm=off' and 'pci=realloc' to /etc/default/grub."
fi

# 7. Check GSP Firmware (Offloading GPU overhead)
GSP_CHECK=$(sudo cat /proc/driver/nvidia/params | grep EnableGpuFirmware | awk '{print $2}')
echo -n "7. NVIDIA GSP Firmware: "
if [ "$GSP_CHECK" == "1" ]; then
    echo -e "${GREEN}ACTIVE${NC}"
else
    echo -e "${YELLOW}INACTIVE ($GSP_CHECK)${NC} -> Add 'options nvidia NVreg_EnableGpuFirmware=1' to modprobe."
fi

echo -e "${CYAN}==============================================================${NC}"
