[< Back to Index](README.md)

## 7. Docker / Container Runtime

**File:** `/etc/docker/daemon.json`

```json
{
    "data-root": "/home/active/apps/docker-data",
    "storage-driver": "overlay2",
    "default-runtime": "nvidia",
    "insecure-registries": ["192.168.2.11:32080"],
    "runtimes": {
        "nvidia": {
            "args": [],
            "path": "nvidia-container-runtime"
        }
    }
}
```

| Setting | Value | Purpose |
|---------|-------|---------|
| `data-root` | `/home/active/apps/docker-data` | Images/layers on NVMe (vg_gateway/lv_apps_state) for fast pulls |
| `storage-driver` | `overlay2` | Standard Linux overlay filesystem — efficient layer sharing |
| `default-runtime` | `nvidia` | Every container gets GPU access by default — no `--gpus` flag needed |
| `insecure-registries` | `192.168.2.11:32080` | Local Gitea container registry on k3s cluster (no TLS on LAN) |

**Verify:**
```bash
docker info | grep -E "Runtime|Root|Storage"
docker run --rm nvidia/cuda:13.0-base-ubuntu24.04 nvidia-smi 2>/dev/null | head -5
```
