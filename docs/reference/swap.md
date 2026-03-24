[< Back to Index](README.md)

## 10. Swap / L3 Memory Fabric

Three tiers provide graduated overflow from RAM to storage:

```mermaid
graph TD
    RAM["System RAM<br/>96 GB"] -->|overflow| T2["Tier 1: Static NVMe File<br/>/home/active/temp/swapfile_static.img<br/>32 GB — priority 10"]
    RAM -->|overflow| T1["Tier 2: LVM Partition<br/>/dev/vg_gateway/lv_swap<br/>32 GB — priority -2"]
    RAM -->|overflow| T3["Tier 3: Dynamic Swap<br/>/home/active/temp/dynamic_swap/<br/>4–32 GB per file — swapspace daemon"]

    style RAM fill:#2d5016,stroke:#4a8529,color:#fff
    style T2 fill:#1a3a5c,stroke:#2a6496,color:#fff
    style T1 fill:#5c3a1a,stroke:#966a2a,color:#fff
    style T3 fill:#4a1a1a,stroke:#962a2a,color:#fff
```

### Tier 1: Static NVMe Swap File (highest priority)

- **Path:** `/home/active/temp/swapfile_static.img`
- **Size:** 32 GB
- **Priority:** 10
- **Configured in:** `/etc/fstab`
- NVMe-speed swap — first to be used

### Tier 2: LVM Partition (always on)

- **Device:** `/dev/vg_gateway/lv_swap`
- **Size:** 32 GB
- **Priority:** -2
- **Configured in:** `/etc/fstab`
- Fallback after static file fills

### Tier 3: Dynamic (swapspace daemon)

**File:** `/etc/swapspace.conf`
```
swappath="/home/active/temp/dynamic_swap"
lower_freelimit=20
upper_freelimit=60
freetarget=30
min_swapsize=4g
max_swapsize=32g
cooldown=300
```

| Setting | Value | Purpose |
|---------|-------|---------|
| `swappath` | `/home/active/temp/dynamic_swap` | Directory for dynamic swap files |
| `lower_freelimit` | `20` | Create swap when free memory drops below 20% |
| `upper_freelimit` | `60` | Remove swap when free memory exceeds 60% |
| `freetarget` | `30` | Target 30% free memory when creating swap |
| `min_swapsize` | `4g` | Minimum swap file size |
| `max_swapsize` | `32g` | Maximum swap file size |
| `cooldown` | `300` | Wait 5 minutes between swap adjustments |

**Verify:**
```bash
swapon --show
systemctl status swapspace
free -h
```
