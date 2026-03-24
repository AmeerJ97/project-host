[< Back to Index](README.md)

## 3. NVIDIA GPU

**Driver:** 590.48.01
**CUDA Runtime:** 13.1
**Card:** RTX (16GB VRAM)

### Power Limit

**File:** `/etc/systemd/system/nvidia-powerlimit.service`

```ini
[Unit]
Description=Set NVIDIA GPU Power Limit to 140W
After=nvidia-persistenced.service
Requires=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pl 140
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

> **Note:** An older service `/etc/systemd/system/nvidia-powercap.service` exists (sets 150W). The `nvidia-powerlimit.service` runs after it and overrides the cap to 140W.

### Persistence Mode

Enabled via `nvidia-persistenced` — keeps the driver loaded between GPU calls, eliminating cold-start latency.

### Environment Variables

**File:** `/etc/environment`
```
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
```

### PCIe Link

| Property | Value |
|----------|-------|
| Link Speed | Gen 4 |
| Link Width | x8 |
| ASPM | Off (kernel param) |
| Bandwidth | ~30 GB/s bidirectional |

### Resizable BAR

| Property | Value |
|----------|-------|
| BAR1 Size | 16384 MiB |
| Status | Full 16GB VRAM addressable by CPU |

**Verify:**
```bash
# Power limit
nvidia-smi -q -d power | grep "Power Limit"
# PCIe link
nvidia-smi -q -d pcie | grep -E "Link|Gen"
# BAR1
nvidia-smi -q -d BAR1
# Driver version
nvidia-smi --query-gpu=driver_version --format=csv,noheader
# Persistence mode
nvidia-smi -q | grep "Persistence Mode"
```
