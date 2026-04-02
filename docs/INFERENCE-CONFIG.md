# Inference Configuration Reference

System configuration for running 70B+ parameter LLMs on the Project Host workstation (i7-13700F, 96GB DDR5, RTX 4060 Ti 16GB).

Last validated: 2026-04-01

---

## Configuration Profile: `workstation` (Default)

Optimized for mixed-use: desktop session + Chrome + Claude Code sessions + LLM inference via Ollama. Prioritizes thermal safety and stability over raw throughput.

### GPU Power & Clocks

| Setting | Value | Rationale |
|---------|-------|-----------|
| Power limit | **140W** | Prevents thermal throttle oscillation at 150W+. GPU finds a stable clock within this budget. |
| Clock lock | **None** | Let the GPU settle at its natural frequency under the power cap. Forced floors (e.g. `-lgc 2500`) cause P-state instability under sustained inference. |
| Persistence mode | Enabled | Avoids driver reinit latency on each CUDA call |

**Service:** `/etc/systemd/system/nvidia-powercap.service`
```ini
[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi -pm ENABLED
ExecStart=/usr/bin/nvidia-smi -pl 140
RemainAfterExit=yes
```

### Ollama Service Configuration

**Service override:** `/etc/systemd/system/ollama.service.d/override.conf`
```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_MODELS=/home/active/inference/ollama"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="GGML_CUDA_ENABLE_UNIFIED_MEMORY=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_LLM_LIBRARY=cuda_v12"
CPUAffinity=0-15
CPUQuota=1568%
OOMScoreAdjust=-900
IOWeight=900
```

| Setting | Value | Rationale |
|---------|-------|-----------|
| `OLLAMA_LLM_LIBRARY=cuda_v12` | Forces CUDA 12 backend | Ollama 0.18+ ships cuda_v12 and cuda_v13 backends. The system has CUDA 12.6 installed; v13 fails silently, causing CPU-only fallback. |
| `CPUAffinity=0-15` | All 16 cores | Spreads inference across P-cores and E-cores to prevent thermal hotspots. Previous `0-7` pinned everything to P-cores (90°C). |
| `CPUQuota=1568%` | 16 cores × 98% | Caps each core below 100% utilization. At 100%, the i7-13700F P-cores hit 90°C+ under sustained inference. 98% cap provides thermal headroom. |
| `OLLAMA_KV_CACHE_TYPE=q8_0` | 8-bit KV cache | Halves KV cache memory vs f16, allowing more model layers in VRAM. |
| `OLLAMA_NUM_PARALLEL=2` | 2 concurrent requests | Doubles KV cache size but enables pipelining. |
| `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1` | UVM overcommit | Allows Ollama to schedule more layers to GPU than fit in VRAM, with UVM handling overflow to system RAM. |

**Important:** `OLLAMA_NUM_GPU` is NOT a valid Ollama environment variable (confirmed via Ollama source code, issue #11437). GPU layer count must be set per-model via Modelfile `PARAMETER num_gpu 99` or per-request via API `options.num_gpu`.

### Memory Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| `vm.nr_hugepages` | **0** | HugePages reserve memory exclusively. With 96GB RAM shared between desktop + inference, the 32GB reservation (16384 pages) starved other processes. Disabled in favor of THP madvise. |
| `vm.swappiness` | 1 | Minimal swap pressure — prefer keeping model weights in RAM. |
| `vm.overcommit_memory` | 1 | Required for `cudaMallocManaged` UVM allocations. |
| `vm.max_map_count` | 1048576 | Required for large mmap'd model files. |

**Persisted in:** `/etc/sysctl.d/99-inference.conf`

### CUDA Version Map

Multiple CUDA versions coexist. Understanding which layer uses which prevents silent fallback to CPU inference.

| Layer | CUDA Version | Purpose |
|-------|-------------|---------|
| Driver capability | 13.1 (`nvidia-smi`) | Maximum supported — matches installed toolkit |
| System toolkit | 13.1 (`nvcc`, `/usr/local/cuda-13.1/`) | For compiling vLLM, PyTorch, custom CUDA code |
| Ollama `cuda_v12` | 12.8 (bundled at `/usr/local/lib/ollama/cuda_v12/`) | Ollama runtime — forced via `OLLAMA_LLM_LIBRARY=cuda_v12` |
| Ollama `cuda_v13` | 13.1 (bundled) | **MUST NOT USE** — fails silently, CPU-only fallback |

`OLLAMA_LLM_LIBRARY=cuda_v12` is mandatory. Without it, Ollama tries `cuda_v13` first, which fails to load `libggml-base.so.0`, causing silent fallback to CPU with 0 VRAM detected.

See `docs/reference/cuda.md` for full linker path details and per-backend CUDA source mapping.

### CUDA / GPU Access

**nvidia-caps device permissions:** The NVIDIA compute capability device (`/dev/nvidia-caps/nvidia-cap1`) must be readable by the `render` group. Without this, `cuInit()` returns error 999 for non-root users (including the `ollama` service user).

**udev rule:** `/etc/udev/rules.d/71-nvidia-caps.rules`
```
KERNEL=="nvidia-cap[0-9]*", SUBSYSTEM=="nvidia-caps", MODE="0660", GROUP="render"
```

**Linker paths:** Ollama's bundled libraries require `/usr/local/lib/ollama` in the linker cache.

**Config:** `/etc/ld.so.conf.d/ollama.conf`
```
/usr/local/lib/ollama
/usr/local/lib/ollama/cuda_v12
```
Run `sudo ldconfig` after creating.

### Xid 154 Recovery

If `cuInit()` returns 999 system-wide and `dmesg` shows:
```
NVRM: uvm encountered global fatal error 0x60, requiring os reboot to recover.
NVRM: Xid 154, GPU recovery action changed to 0x2 (Node Reboot Required)
```
The GPU's UVM subsystem has fatally crashed. **Reboot is the only recovery.** This can be triggered by power instability, driver bugs, or UVM overcommit failures.

---

## Configuration Profile: `inference-only`

For dedicated inference sessions where the desktop is not actively used. Trades desktop responsiveness for maximum throughput.

| Setting | Difference from `workstation` |
|---------|-------------------------------|
| Power limit | 150W (card's rated TDP) |
| Clock lock | `-lgc 2100,3105` (floor at 2100 MHz) |
| `CPUAffinity` | `0-7` (P-cores only for max single-thread perf) |
| `CPUQuota` | `784%` (8 cores × 98%) |
| `preempt=none` | Add to GRUB for lowest scheduling latency |
| `vm.nr_hugepages` | 4096 (8GB) if running a single model repeatedly |

---

## Configuration Profile: `benchmark`

For isolated performance testing. Not suitable for daily use.

| Setting | Difference from `workstation` |
|---------|-------------------------------|
| Power limit | 165W (card maximum) |
| Clock lock | `-lgc 2500,3105` |
| `CPUAffinity` | `0-15` (all cores) |
| `CPUQuota` | `1600%` (100% per core — accept thermal risk) |
| `OLLAMA_NUM_PARALLEL` | 1 (single request, no KV cache doubling) |
| `preempt=none` | Required |

---

## Lessons Learned (2026-04-01 Session)

1. **`OLLAMA_NUM_GPU=99` does nothing.** It was never a valid Ollama environment variable. Previous agents set it based on outdated community advice. The correct mechanism is `PARAMETER num_gpu 99` in the Modelfile.

2. **HugePages starve mixed workloads.** 32GB reserved for hugepages left only 62GB for everything else. With 3 Claude Code sessions + Chrome + desktop consuming ~30GB, Ollama's scheduler saw insufficient free memory and refused to allocate GPU layers.

3. **CPU thermal protection is mandatory.** The i7-13700F's P-cores (0-7) hit 90°C under sustained inference load. Capping at 98% utilization via `CPUQuota` and spreading across all cores via `CPUAffinity=0-15` keeps temps under 80°C.

4. **nvidia-cap1 permissions break CUDA for non-root.** After driver updates, `/dev/nvidia-caps/nvidia-cap1` resets to `cr--------` (root only). The udev rule ensures the `render` group retains access.

5. **Ollama's cuda_v13 backend fails silently.** When `libggml-base.so.0` isn't in the linker cache, the CUDA backend fails to load and Ollama silently falls back to CPU-only inference. The `OLLAMA_LLM_LIBRARY=cuda_v12` env var forces the working backend.

6. **GPU power oscillation at 150W.** At 150W with a 2500 MHz clock floor, the RTX 4060 Ti enters a throttle→boost→throttle cycle. Dropping to 140W with no clock floor lets it find a stable operating point.

7. **AirLLM is not useful for this hardware.** It solves 4GB VRAM constraints via layer-by-layer disk streaming. With 16GB VRAM + 96GB RAM + UVM, Ollama's native layer splitting is faster by orders of magnitude.
