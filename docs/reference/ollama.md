[< Back to Index](README.md)

## 6. Ollama

**Service file:** `/etc/systemd/system/ollama.service`
**Override:** `/etc/systemd/system/ollama.service.d/override.conf`

```ini
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_MODELS=/home/apps/models/ollama"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_NUM_GPU=99"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="CUDA_VISIBLE_DEVICES=0"
Environment="GGML_CUDA_ENABLE_UNIFIED_MEMORY=1"
LimitMEMLOCK=infinity
LimitNOFILE=65536
```

| Variable | Value | Purpose |
|----------|-------|---------|
| `OLLAMA_HOST` | `0.0.0.0` | Listen on all interfaces (LAN access from k3s nodes) |
| `OLLAMA_MODELS` | `/home/apps/models/ollama` | Model storage on vg1/lv_models (3.64TB HDD) |
| `OLLAMA_FLASH_ATTENTION` | `1` | Enable Flash Attention — reduces VRAM usage and improves throughput |
| `OLLAMA_NUM_GPU` | `99` | Offload all possible layers to GPU (capped by VRAM) |
| `OLLAMA_KEEP_ALIVE` | `24h` | Keep models loaded in memory for 24 hours — avoids reload latency |
| `OLLAMA_MAX_LOADED_MODELS` | `2` | Up to 2 models resident simultaneously |
| `OLLAMA_NUM_PARALLEL` | `4` | Handle 4 concurrent inference requests |
| `CUDA_VISIBLE_DEVICES` | `0` | Pin to GPU 0 |
| `GGML_CUDA_ENABLE_UNIFIED_MEMORY` | `1` | Allow GGML to use CUDA unified memory — enables models larger than VRAM |
| `LimitMEMLOCK` | `infinity` | Allow unlimited memory locking (required for pinned buffers) |
| `LimitNOFILE` | `65536` | High file descriptor limit for concurrent connections |

### Shell Environment

`~/.bashrc` also sets:
```bash
export OLLAMA_MODELS=/home/apps/models/ollama
export HF_HOME=/home/apps/models/huggingface
```

### GPU Layer Offload Recommendations

| Model Size | Quantization | Recommended `num_gpu` | Notes |
|------------|-------------|----------------------|-------|
| ≤ 13B | Any | -1 (all layers) | Fits entirely in 16GB VRAM |
| 34B | Q4_K_M | 28 | ~10GB VRAM, rest in RAM |
| 70B | Q4_K_M | 30 | ~12GB VRAM, rest in RAM |
| 70B | Q8_0 | 14 | ~14GB VRAM, rest in RAM |

**Verify:**
```bash
systemctl status ollama
curl -s http://localhost:11434/api/tags | jq '.models[].name'
# Check loaded models
curl -s http://localhost:11434/api/ps | jq .
```
