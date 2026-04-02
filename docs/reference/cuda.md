[< Back to Index](README.md)

## 5. CUDA

### Version Landscape

The system has multiple CUDA versions at different layers. Understanding which version each component uses prevents silent failures.

| Layer | CUDA Version | Location | What It Means |
|-------|-------------|----------|---------------|
| **Driver capability** | 13.1 | `nvidia-smi` output, driver 590.48.01 | Maximum CUDA version the driver *can support*. |
| **System toolkit** | 13.1.115 | `/usr/local/cuda-13.1/` (nvcc, libraries, headers) | Compilation target for custom CUDA code (PyTorch, vLLM, etc.) |
| **Ollama cuda_v12** | 12.8.90 | `/usr/local/lib/ollama/cuda_v12/` | Ollama's bundled CUDA runtime. Used when `OLLAMA_LLM_LIBRARY=cuda_v12`. |
| **Ollama cuda_v13** | 13.0.96 | `/usr/local/lib/ollama/cuda_v13/` | **MUST NOT USE** — fails silently, causes CPU-only fallback (0 VRAM detected). |
| **Previous toolkit** | 12.6 | `/usr/local/cuda-12.6/` (still installed, available) | Previous system toolkit. Retained for compatibility. |
| **cuDNN** | 9.20.0.48 | System-wide | Forward-compatible with CUDA 12.9+. Works with toolkit 12.6 via minor-version compatibility. |

**Key insight:** `nvidia-smi` reporting "CUDA 13.1" does NOT mean CUDA 13.1 is installed. It means the driver *supports* applications compiled against CUDA up to 13.1. The actual toolkit for compilation is 12.6.

### Symlink Chain

```
/usr/local/cuda        → /etc/alternatives/cuda     → /usr/local/cuda-13.1
/usr/local/cuda-12     → /etc/alternatives/cuda-12   → /usr/local/cuda-12.6
/usr/local/cuda-13     → /etc/alternatives/cuda-13   → /usr/local/cuda-13.1
```

Both 12.6 and 13.1 are installed. The default symlink points to 13.1.

### Linker Configuration (`/etc/ld.so.conf.d/`)

| File | Paths | Status |
|------|-------|--------|
| `000_cuda.conf` | `/usr/local/cuda/targets/x86_64-linux/lib` | Correct — resolves to cuda-13.1 via symlink |
| `988_cuda-12.conf` | `/usr/local/cuda-12/targets/x86_64-linux/lib` | Correct — resolves to cuda-12.6 via symlink |
| `ollama.conf` | `/usr/local/lib/ollama`, `/usr/local/lib/ollama/cuda_v12` | Correct — Ollama's CUDA 12.8 runtime |
| `ollama-cuda.conf` | `/usr/local/lib/ollama/cuda_v13`, `/usr/local/cuda-13.1/lib64` | **STALE** — cuda_v13 should not be in linker path; `/usr/local/cuda-13.1` does not exist |

**TODO:** `ollama-cuda.conf` should be reviewed. It puts cuda_v13 libs in the linker cache, which could cause symbol conflicts. Since `OLLAMA_LLM_LIBRARY=cuda_v12` forces the correct backend, this hasn't caused runtime failures, but it's incorrect configuration.

### Shell Environment

**File:** `~/.bashrc`
```bash
# CUDA toolkit paths (system toolkit is 13.1; driver 590.48.01 supports up to 13.1)
export PATH=/usr/local/cuda-13.1/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.1/lib64:$LD_LIBRARY_PATH

# ML framework GPU settings
export TF_FORCE_GPU_ALLOW_GROWTH=true
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
```

| Variable | Purpose |
|----------|---------|
| `PATH` | Makes `nvcc` 13.1, `cuda-gdb`, etc. available |
| `LD_LIBRARY_PATH` | Runtime linker finds CUDA 13.1 shared libs |
| `TF_FORCE_GPU_ALLOW_GROWTH` | TensorFlow allocates VRAM incrementally instead of grabbing all at init |
| `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` | PyTorch uses expandable memory segments — reduces fragmentation for variable-size tensors |

### How Each Backend Finds CUDA

| Backend | CUDA Source | Library Selection |
|---------|------------|-------------------|
| **Ollama** | Bundled at `/usr/local/lib/ollama/cuda_v12/` | Forced via `OLLAMA_LLM_LIBRARY=cuda_v12` in systemd override. Uses libcudart.so.12.8.90. |
| **vLLM** | System toolkit `/usr/local/cuda-13.1/` | pip-installed torch links against system CUDA. PyTorch 2.11.0+cu130 (CUDA 13.0). |
| **TensorRT-LLM** | Docker container (nvcr.io) | Container ships its own CUDA runtime. Host GPU driver must support ≥ container CUDA version. |
| **Unsloth** | System toolkit `/usr/local/cuda-13.1/` | Same as vLLM — uses system PyTorch + CUDA. |
| **Direct llama.cpp** | System toolkit or bundled | Build-time: links against `/usr/local/cuda-13.1/`. Runtime: uses built-in copy. |

### Verify

```bash
# System toolkit version
nvcc --version  # Expected: cuda_13.1.r13.1/compiler.37061995_0

# Driver capability (NOT installed version)
nvidia-smi | grep "CUDA Version"  # Expected: 13.1

# Linker cache
ldconfig -p | grep libcudart  # Should show 13.1 (system), 12.8 (Ollama cuda_v12), 12.6 (legacy)

# Shell environment
echo $LD_LIBRARY_PATH  # Should reference cuda-13.1

# Ollama backend
systemctl show ollama --property=Environment | grep LLM_LIBRARY  # Expected: cuda_v12
```
