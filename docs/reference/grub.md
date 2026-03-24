[< Back to Index](README.md)

## 2. GRUB / Kernel Boot

**File:** `/etc/default/grub`

```
GRUB_CMDLINE_LINUX_DEFAULT='quiet splash nvidia-drm.modeset=1 pcie_aspm=off zswap.enabled=0 transparent_hugepage=madvise intel_iommu=on iommu=pt'
```

| Flag | Purpose |
|------|---------|
| `quiet splash` | Suppress boot messages, show splash screen |
| `nvidia-drm.modeset=1` | Enable kernel modesetting for NVIDIA — required for Wayland and proper display init |
| `pcie_aspm=off` | Disable PCIe Active State Power Management — prevents GPU link-speed downshifts that add latency |
| `zswap.enabled=0` | **Disable zswap entirely.** zswap runs compression across all CPU cores during swap-out, causing CPU spikes during LLM inference. Direct swap to NVMe is faster and more predictable for this workload. |
| `transparent_hugepage=madvise` | THP only for apps that explicitly request it via `madvise()` — prevents random compaction stalls |
| `intel_iommu=on` | Enable Intel IOMMU for device isolation (VT-d) |
| `iommu=pt` | IOMMU passthrough mode — devices not assigned to VMs get direct access, zero overhead for bare-metal GPU |

After editing, apply with:
```bash
sudo update-grub && sudo reboot
```

**Verify:**
```bash
cat /proc/cmdline
```
