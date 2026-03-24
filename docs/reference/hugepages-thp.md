[< Back to Index](README.md)

## 9. Memory Subsystem (HugePages, THP, KSM)

### HugePages

- **Count:** 4096 pages x 2MB = **8 GB** reserved
- **Configured in:** `/etc/sysctl.d/99-inference.conf` (`vm.nr_hugepages = 4096`)
- Used by GPU driver pinned buffers and large model allocations

### Transparent Huge Pages (THP)

- **Mode:** `madvise` (set via GRUB kernel param `transparent_hugepage=madvise`)
- **Defrag:** `madvise` (set via tmpfiles)
- Only processes that explicitly call `madvise(MADV_HUGEPAGE)` get THP — prevents compaction stalls in unaware applications

### KSM (Kernel Same-page Merging)

- **Status:** Disabled
- KSM scans for duplicate pages to merge — useful for VMs but adds CPU overhead inappropriate for inference workloads

### Persistence

**File:** `/etc/tmpfiles.d/99-inference.conf`
```
w /sys/kernel/mm/ksm/run - - - - 0
w /sys/kernel/mm/transparent_hugepage/defrag - - - - madvise
```

**Verify:**
```bash
grep HugePages /proc/meminfo
cat /sys/kernel/mm/transparent_hugepage/enabled
cat /sys/kernel/mm/transparent_hugepage/defrag
cat /sys/kernel/mm/ksm/run
```
