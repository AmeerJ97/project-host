[< Back to Index](README.md)

## 1. BIOS / Firmware

**Location:** UEFI Setup (reboot → DEL/F2)

### CPU Power Limits

| Setting | Value | Rationale |
|---------|-------|-----------|
| PL1 (Sustained) | 200W | Full sustained power for all-core workloads |
| PL2 (Burst) | 220W | Short-burst headroom above PL1 |
| IccMax | 307A | Maximum current delivery — prevents throttling under AVX-512 |
| Lite Load Mode | 9 | Lightest VRM load line — reduces Vdroop, stabilizes voltage |
| CEP (Current Excursion Protection) | Disabled | Prevents spurious throttling during transient current spikes |

### Memory

| Setting | Value | Rationale |
|---------|-------|-----------|
| Speed | 5200 MT/s | Validated stable speed for this kit |
| Gear | Gear 1 | 1:1 memory controller ratio — lowest latency |
| CAS Latency | CL40 | Tight primary timing at 5200 |
| Voltage | 1.25V | Slight overvolt for stability at rated speed |
| Command Rate | 2T | Stability margin with 4 DIMMs / high capacity |

**Memory Fallback Ladder** (if instability occurs):

```
5200 CL40 Gear1 1.25V 2T  ← current
  ↓ fail
5200 CL42 Gear1 1.25V 2T  ← loosen timings
  ↓ fail
4800 CL40 Gear1 1.20V 2T  ← drop speed
  ↓ fail
4800 CL40 Gear2 1.20V 2T  ← drop to Gear 2
  ↓ fail
4400 CL38 Gear2 1.20V 2T  ← safe fallback
```

### PCIe

| Setting | Value | Rationale |
|---------|-------|-----------|
| PCIe Gen | Gen 4 (forced) | Prevents downclocking; GPU needs consistent bandwidth |
| Resizable BAR | Enabled | Full VRAM addressable by CPU (16GB BAR1) |
| Above 4G Decoding | Enabled | Required for ReBAR to function |

### Virtualization

| Setting | Value | Rationale |
|---------|-------|-----------|
| VT-x | Enabled | Hardware virtualization for KVM/QEMU |
| VT-d | Enabled | IOMMU for device passthrough |

**Verify:**
```bash
# Memory speed
sudo dmidecode -t memory | grep -E "Speed|Configured"
# Virtualization
grep -E "vmx|svm" /proc/cpuinfo | head -1
# ReBAR
nvidia-smi -q -d BAR1 | grep "Total"
```
