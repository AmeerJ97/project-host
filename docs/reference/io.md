[< Back to Index](README.md)

## 11. I/O Subsystem

### NVMe

| Setting | Value | Rationale |
|---------|-------|-----------|
| Scheduler | `none` | NVMe has its own internal scheduler — kernel scheduler adds zero-value overhead |
| Read-ahead | 2048 KB | 16x default (128 KB) — prefetches larger chunks for sequential model loading |

### HDD

| Setting | Value | Rationale |
|---------|-------|-----------|
| Scheduler | `mq-deadline` | Deadline-based scheduling reduces worst-case latency on rotational media |

### Persistence (NVMe read-ahead)

**File:** `/etc/udev/rules.d/99-nvme-readahead.rules`
```
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/read_ahead_kb}="2048"
```

**Verify:**
```bash
cat /sys/block/nvme0n1/queue/scheduler
cat /sys/block/nvme0n1/queue/read_ahead_kb
cat /sys/block/sda/queue/scheduler
```
