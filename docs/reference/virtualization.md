[< Back to Index](README.md)

## 16. Virtualization

### Stack

| Component | Detail |
|-----------|--------|
| Hypervisor | KVM/QEMU via libvirt |
| CPU Features | VT-x + VT-d (enabled in BIOS) |
| IOMMU | `intel_iommu=on iommu=pt` (GRUB) |
| Lightweight containers | systemd-nspawn available |

### Active VMs

| Name | OS | RAM | vCPUs | Storage |
|------|----|----|-------|---------|
| `citadel` | Ubuntu 24.04 (cloud image) | 16 GB | 8 | vg1/lv_vms at `/home/apps/vms` |

### VM Storage

VMs stored on `/home/apps/vms` (vg1/lv_vms, 500 GB on HDD).

**Verify:**
```bash
virsh list --all
virsh dominfo citadel
dmesg | grep -i iommu | head -5
```
