[< Back to Index](README.md)

## 18. Custom systemd Services

| Service | Description | Status |
|---------|-------------|--------|
| `ollama.service` | LLM inference server (Ollama) | Active, enabled |
| `nvidia-powerlimit.service` | GPU power cap at 140W | Active, enabled |
| `nvidia-powercap.service` | Older GPU cap (150W) — superseded by powerlimit | Superseded |
| `nvidia-persistenced.service` | NVIDIA persistence daemon | Active, enabled |
| `swapspace.service` | Dynamic L3 swap manager | Active, enabled |
| `cpu-governor.service` | Set CPU governor to `performance` | Active, enabled |
| `thp-madvise.service` | Apply THP madvise settings | Active, enabled |
| `conduit.service` | User application (Conduit) | — |
| `prism.service` | User application (Prism) | — |
| `fullmetal-watchdog.service` | User application (watchdog) | — |
| `project-host-monitor.service` | Thermal monitoring (if deployed) | — |
| `ps4-*.service` | PS4-related services | — |

**Verify:**
```bash
systemctl list-units --type=service --state=running | grep -E "ollama|nvidia|swap|cpu-gov|thp|conduit|prism|fullmetal|project-host|ps4"
```
