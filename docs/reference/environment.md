[< Back to Index](README.md)

## 17. Environment Variables

Consolidated from `/etc/environment`, `~/.bashrc`, and systemd service overrides.

### System-wide (`/etc/environment`)

| Variable | Value | Purpose |
|----------|-------|---------|
| `GBM_BACKEND` | `nvidia-drm` | Wayland GBM backend for NVIDIA |
| `__GLX_VENDOR_LIBRARY_NAME` | `nvidia` | Force NVIDIA GLX vendor library |
| `ELECTRON_OZONE_PLATFORM_HINT` | `auto` | Electron apps auto-detect Wayland/X11 |
| `_JAVA_AWT_WM_NONREPARENTING` | `1` | Java AWT compatibility with tiling/Wayland WMs |

### User Shell (`~/.bashrc`)

| Variable | Value | Purpose |
|----------|-------|---------|
| `PATH` | CUDA 13.1 toolkit `bin/` prepended | CUDA binaries (nvcc, cuda-gdb) |
| `LD_LIBRARY_PATH` | CUDA 13.1 toolkit `lib64/` prepended | CUDA shared libraries |
| `TF_FORCE_GPU_ALLOW_GROWTH` | `true` | TensorFlow incremental VRAM allocation |
| `PYTORCH_CUDA_ALLOC_CONF` | `expandable_segments:True` | PyTorch memory management |
| `XDG_CACHE_HOME` | App cache tier (NVMe) | Redirects cache from root to dedicated LV |
| `XDG_DATA_HOME` | App data tier (NVMe) | Redirects data from root to dedicated LV |
| `XDG_STATE_HOME` | App state tier (NVMe) | Redirects state from root to dedicated LV |
| `HF_HOME` | Model archive (HDD) | Hugging Face cache on cold storage |
| `OLLAMA_MODELS` | Model staging (NVMe) | Ollama models on hot storage (matches systemd service) |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` | Enable Claude Code agent teams |
| `CLAUDE_CODE_SPAWN_BACKEND` | `tmux` | Claude Code uses tmux for subagent spawning |

### Ollama systemd Service

| Variable | Value |
|----------|-------|
| `OLLAMA_HOST` | `0.0.0.0` |
| `CUDA_VISIBLE_DEVICES` | `0` |
| `GGML_CUDA_ENABLE_UNIFIED_MEMORY` | `1` |

(Full list in Section 6.)

**Verify:**
```bash
env | sort
cat /etc/environment
grep -E "^export" ~/.bashrc
systemctl show ollama --property=Environment
```
