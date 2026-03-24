[< Back to Index](README.md)

## 5. CUDA

**Toolkit:** CUDA 13.0 installed at `/usr/local/cuda-13.0/`
**Also present:** `/usr/local/cuda-13`, `/usr/local/cuda-13.1`
**cuDNN:** 9.20.0.48 (built for CUDA 12.9, forward-compatible)

### Library Paths

**Files in `/etc/ld.so.conf.d/`:**
- `000_cuda.conf`
- `987_cuda-13.conf`
- `gds-13-1.conf`

### Shell Environment

**File:** `~/.bashrc`
```bash
export PATH=/usr/local/cuda-13.0/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda-13.0/lib64:$LD_LIBRARY_PATH
export TF_FORCE_GPU_ALLOW_GROWTH=true
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
```

| Variable | Purpose |
|----------|---------|
| `PATH` | Makes `nvcc`, `cuda-gdb`, etc. available |
| `LD_LIBRARY_PATH` | Runtime linker finds CUDA shared libs |
| `TF_FORCE_GPU_ALLOW_GROWTH` | TensorFlow allocates VRAM incrementally instead of grabbing all at init |
| `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` | PyTorch uses expandable memory segments — reduces fragmentation for variable-size tensors |

**Verify:**
```bash
nvcc --version
ldconfig -p | grep cuda | head -5
python3 -c "import torch; print(torch.cuda.is_available(), torch.version.cuda)"
```
