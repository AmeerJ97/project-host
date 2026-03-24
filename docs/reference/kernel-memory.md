[< Back to Index](README.md)

## 8. Kernel Memory Management (sysctl)

**File:** `/etc/sysctl.d/99-inference.conf`

### Memory

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `vm.compaction_proactiveness` | `0` | Disable proactive memory compaction — prevents random latency spikes during inference |
| `kernel.numa_balancing` | `0` | Disable automatic NUMA page migration — single-socket system, balancing adds overhead for no benefit |
| `vm.swappiness` | `10` | Prefer keeping pages in RAM; only swap under real pressure |
| `vm.nr_hugepages` | `4096` | Pre-allocate 4096 x 2MB = 8GB of static huge pages |
| `vm.max_map_count` | `1048576` | High mmap limit — required by Elasticsearch, some ML frameworks, and large model loads |

### I/O

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `vm.dirty_background_bytes` | `1610612736` (1.5 GB) | Start background writeback when 1.5GB of dirty pages accumulate — large buffer for burst writes |
| `vm.dirty_bytes` | `4294967296` (4 GB) | Force synchronous writeback at 4GB dirty — prevents OOM from runaway buffered writes |
| `vm.vfs_cache_pressure` | `80` | Slightly prefer reclaiming dentry/inode caches over page cache — balances FS metadata and data caching |

### Filesystem

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `fs.inotify.max_user_watches` | `524288` | High inotify watch limit — needed for IDEs, file watchers, build tools |
| `fs.inotify.max_user_instances` | `384` | Enough inotify instances for multiple dev tools running simultaneously |

### Network

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `net.core.rmem_max` | `16777216` (16 MB) | Maximum receive buffer — large buffers for high-throughput LAN transfers |
| `net.core.wmem_max` | `16777216` (16 MB) | Maximum send buffer |
| `net.core.rmem_default` | `1048576` (1 MB) | Default receive buffer — 8x kernel default |
| `net.core.wmem_default` | `1048576` (1 MB) | Default send buffer |
| `net.core.netdev_max_backlog` | `5000` | Network device backlog queue — prevents packet drops during bursts |
| `net.ipv4.tcp_rmem` | `4096 1048576 16777216` | TCP receive buffer: min 4K, default 1M, max 16M |
| `net.ipv4.tcp_wmem` | `4096 1048576 16777216` | TCP send buffer: min 4K, default 1M, max 16M |
| `net.ipv4.tcp_fastopen` | `3` | Enable TCP Fast Open for both client (1) and server (2) — reduces connection latency |

**Verify:**
```bash
sysctl vm.swappiness vm.nr_hugepages vm.compaction_proactiveness kernel.numa_balancing
sysctl net.ipv4.tcp_fastopen net.core.rmem_max
```
