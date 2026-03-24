
# Project Host

A tiered-memory Linux workstation architecture that runs 70B+ parameter LLMs on consumer hardware.

> **Not just a config. Not just tuning.** A complete architectural blueprint that treats VRAM, DDR5 RAM, and NVMe swap as a **unified memory fabric** — enabling models 4× larger than the available VRAM to run with deterministic performance.

![Project Host Architecture](https://v3b.fal.media/files/b/0a936a2a/3TOvPS7UPYUntB_A_Kr6K_zJiW5yYL.png)

*Visual overview of the tiered memory hierarchy*

---

## The Core Idea

Consumer GPUs have limited VRAM (16 GB). LLMs need far more (70B+ parameters ≈ 40 GB). Instead of giving up or buying expensive hardware, **Project Host redesigns the memory hierarchy**:

- **Shell** — Disposable OS root (`/`) that can be reinstalled without touching data
- **Gateway** — NVMe-speed active runtime for configs, apps, and hot model staging  
- **Core** — Persistent SATA storage for projects, model library, and archives
- **GPU Direct Memory Path** — CUDA Unified Virtual Memory with L2-cache optimization

The result: **70B-parameter models run smoothly on an RTX 4060 Ti 16 GB** by transparently overflowing into 96 GB of DDR5 RAM and a 300 GB NVMe swap fabric.

---

## Architecture Overview

Three storage tiers + unified memory fabric:

```mermaid
graph TD
    subgraph Shell ["Shell (Disposable)"]
        ROOT["/ (ext4, 137 GB NVMe)<br>OS root — reinstallable"]
    end

    subgraph Gateway ["Gateway (NVMe LVM)"]
        CONFIGS["/home/active/configs<br>Identity, dotfiles"]
        APPS["/home/active/apps<br>Docker, app state"]
        INFERENCE["/home/active/inference<br>Hot model staging"]
        SWAP["L3 Swap Fabric<br>Static + Dynamic"]
    end

    subgraph Core ["Core (SATA LVM)"]
        DEV["/home/core<br>Development, projects"]
        MODELS["/home/apps/models<br>ML model library"]
        MEDIA["/home/media<br>Media archive"]
    end

    subgraph GPU_Path ["GPU Direct Memory Path"]
        VRAM["VRAM 16 GB<br>288 GB/s"]
        L2["GPU L2 Cache<br>cache_sysmem=1"]
        RAM["DDR5 96 GB<br>PCIe x8 Gen4"]
    end

    ROOT -.->|"disposable"| CONFIGS
    MODELS -->|"stage to NVMe"| INFERENCE
    INFERENCE -->|"mmap 3.6 GB/s"| RAM
    RAM -->|"15.75 GB/s"| L2
    L2 --> VRAM

    style Shell fill:#868e96,stroke:#333,color:#fff
    style Gateway fill:#fab005,stroke:#333,color:#000
    style Core fill:#339af0,stroke:#333,color:#fff
    style GPU_Path fill:#51cf66,stroke:#333,color:#fff
```

## Direct Memory Architecture

The core innovation is the **GPU Direct Memory Path** — a unified memory fabric that treats VRAM, DDR5 RAM, and NVMe swap as a single addressable space. Data moves via DMA bypass where possible, avoiding CPU bottlenecks:

```mermaid
graph TD
    subgraph Source[Storage Source]
        NVMe["NVMe Gen4 SSD<br/>~7 GB/s"]
    end
    
    subgraph Paths[Data Path Options]
        DMA["<b>DMA Bypass (GDS)</b><br/>NVMe → PCIe → GPU VRAM<br/>1 hop, ~7 GB/s"]
        CPU["<b>CPU Bounce</b><br/>NVMe → PCIe → RAM → PCIe → GPU VRAM<br/>2 hops, ~3‑5 GB/s"]
    end
    
    subgraph Destination[GPU Memory]
        VRAM["VRAM 16 GB<br/>288 GB/s"]
        L2["GPU L2 Cache<br/>cache_sysmem=1"]
        RAM["DDR5 96 GB<br/>83 GB/s"]
    end
    
    NVMe --> DMA
    NVMe --> CPU
    DMA --> VRAM
    CPU --> RAM
    RAM --> L2
    L2 --> VRAM
    
    style DMA fill:#76b900,stroke:#4a7a00,color:#fff
    style CPU fill:#e74c3c,stroke:#c0392b,color:#fff
    style VRAM fill:#51cf66,stroke:#333,color:#fff
    style L2 fill:#f1c40f,stroke:#333,color:#000
    style RAM fill:#339af0,stroke:#333,color:#fff
```

**Key advantage:** When GPUDirect Storage is available, the NVMe DMA engine writes directly into GPU BAR1, eliminating the CPU copy and doubling effective bandwidth.

---

## The Memory Hierarchy Cliff

Four tiers with **order-of-magnitude bandwidth drops** between each:

```mermaid
graph TD
    subgraph T0 ["T0: VRAM (GDDR6)"]
        VRAM["16 GB @ 288 GB/s"]
    end

    subgraph T1 ["T1: DDR5 RAM"]
        RAM["96 GB @ 83 GB/s"]
    end

    subgraph T2 ["T2: NVMe Gen4"]
        NVME["790.8 GB @ 3.6 GB/s"]
    end

    subgraph T3 ["T3: HDD 5400 RPM"]
        HDD["1 TB @ 0.1 GB/s"]
    end

    VRAM ---|"PCIe x8 Gen4<br>15.75 GB/s"| RAM
    RAM ---|"Memory bus<br>~83 GB/s internal"| NVME
    NVME ---|"SATA / staging copy<br>~0.1 GB/s"| HDD

    style T0 fill:#51cf66,stroke:#333,color:#fff
    style T1 fill:#339af0,stroke:#333,color:#fff
    style T2 fill:#fab005,stroke:#333,color:#000
    style T3 fill:#868e96,stroke:#333,color:#fff
```

**Key insight:** Bandwidth drops **3.5×** from VRAM→RAM, then **23×** from RAM→NVMe, then **36×** from NVMe→HDD. Inference performance is dominated by which tier holds the hot data.

---

## Smart Layer Placement

Not all model layers are equal. Attention layers (accessed every token) stay in VRAM; FFN layers (larger, less critical) overflow to RAM:

```mermaid
graph LR
    subgraph GPU_VRAM ["VRAM (16 GB)"]
        ATT["Attention Layers"]
        KV["KV Cache"]
    end

    subgraph DDR5_RAM ["DDR5 RAM (96 GB)"]
        FFN["FFN Layers"]
        EMB["Embeddings"]
        OVERFLOW["Overflow Layers"]
    end

    subgraph NVMe_Swap ["NVMe mmap (vg_gateway)"]
        COLD["Cold Model Regions<br>(paged on demand)"]
    end

    ATT ---|"always in VRAM<br>288 GB/s"| FFN
    FFN ---|"overflow path<br>3.6 GB/s"| COLD

    style GPU_VRAM fill:#51cf66,stroke:#333,color:#fff
    style DDR5_RAM fill:#339af0,stroke:#333,color:#fff
    style NVMe_Swap fill:#fab005,stroke:#333,color:#000
```

| Model | Total Size | GPU Layers | RAM Layers | Split | Throughput |
|-------|------------|------------|------------|-------|-------------|
| **7B-13B** | 4-8 GB (Q4) | All | None | 100% GPU | High |
| **32B Q4** | ~20 GB | 28 of 48 | 20 of 48 | ~58% GPU | Moderate |
| **70B Q4** | ~40 GB | 30 of 80 | 50 of 80 | ~37% GPU | Low |
| **120B+ Q4** | 60+ GB | ~14 | ~66+ | GPU+RAM+NVMe | Minimal |

---

## Hardware Topology

The architecture is built around explicit hardware constraints:

```mermaid
graph TD
    subgraph CPU_Complex ["CPU Complex"]
        CPU["i7-13700F<br>16C/24T, 5.2 GHz<br>PL1: 200W | PL2: 220W"]
    end

    subgraph Memory ["DDR5 Memory (96 GiB)"]
        direction LR
        CH_A["Channel A"]
        CH_B["Channel B"]
        A1["A1: 16GB 1R<br>(stub)"]
        A2["A2: 32GB 2R<br>(termination)"]
        B1["B1: 16GB 1R<br>(stub)"]
        B2["B2: 32GB 2R<br>(termination)"]
        CH_A --- A1 & A2
        CH_B --- B1 & B2
    end

    subgraph GPU_Subsystem ["GPU Subsystem"]
        PCIe["PCIe Gen4 x8<br>~15.75 GB/s unidirectional<br>ASPM=Off, ReBAR=On"]
        GPU["RTX 4060 Ti 16GB<br>AD106, SM89<br>Power Cap: 140W"]
        PCIe --- GPU
        VRAM["16 GB GDDR6<br>Single BAR Mapping"]
        GPU --- VRAM
    end

    subgraph Storage_Bus ["Storage Bus"]
        NVMe_Bus["NVMe Gen4 x4"]
        SATA_Bus["SATA III (6 Gbps)"]
        NVMe["nvme0n1<br>NVMe Gen4 SSD 1TB"]
        SDA["sda<br>SATA HDD 1.82TB 7200RPM"]
        SDB["sdb<br>SATA HDD 3.64TB 5400RPM"]
        NVMe_Bus --- NVMe
        SATA_Bus --- SDA & SDB
    end

    CPU --- CH_A & CH_B
    CPU --- PCIe
    CPU --- NVMe_Bus
    CPU --- SATA_Bus
```

> **Design choice:** Mixed-rank DDR5 modules placed according to daisy-chain topology — lighter single-rank modules at stubs, heavier dual-rank at termination points to prevent signal reflection.

---

## Documentation

**This is not a one-page tutorial.** It's a **complete architectural reference**:

| Document | What It Covers |
|----------|----------------|
| **[System Architecture](docs/architecture.md)** | Full hardware specs, storage topology, memory hierarchy, inference pipeline |
| **[Configuration Reference](docs/reference/README.md)** | **20+ subsystem guides:** BIOS, GRUB, GPU, CUDA, Ollama, Docker, kernel memory, huge pages, I/O schedulers, CPU governors, storage, compositor, network, virtualization, environment variables, systemd services |
|| **[GPU Direct Memory](docs/reference/gpu-direct-memory.md)** | UVM `cache_sysmem=1` optimization for oversubscribed models |
|| **[GPUDirect Storage & DMA Bypass](docs/guides/gds-dma.md)** | Deep dive into NVMe→GPU DMA path, PCIe topology, and GeForce compatibility limitations |
|| **[Swap / L3 Fabric](docs/reference/swap.md)** | Three-tier NVMe swap architecture (static + dynamic) |
| **[Inference Optimization](docs/guides/inference-benchmarks.md)** | Layer-split strategies, PCIe bottleneck analysis, cold-start optimization |
| **[Diagnostics](docs/reference/diagnostics.md)** | Full system verification checklist |

---

## Validation-First Design

The architecture includes **executable validation scripts** that verify every documented configuration:

```bash
./scripts/sweep.sh           # Comprehensive diagnostics sweep
./scripts/health-check.sh    # Detailed health check with fix instructions
./scripts/check_host.sh      # Quick GPU/RAM checklist
```

All scripts are **configurable** — edit `sweep_config.sh.example` with the hardware's expected values. The validation suite ensures the target system matches the documented architecture.

---

## Getting Started

This repository is a **blueprint**, not an installer. To adapt it:

1. **Study the architecture** — understand the tiered storage and memory hierarchy.
2. **Adjust for the target hardware** — modify BIOS settings, kernel parameters, and service overrides.
3. **Customize validation** — update expected values in `sweep_config.sh`.
4. **Run the validation suite** — verify the system matches the documented configuration.

**Goal:** Implement the **design principles**, not clone the exact hardware list:
- Disposable OS root
- Speed-separated storage tiers  
- Unified memory fabric (VRAM→RAM→NVMe)
- Automated validation

---

## Repository Structure

```
docs/                          # Complete architectural reference
├── architecture.md            # System architecture specification (v5.0)
├── reference/                 # 20+ subsystem configuration guides
└── guides/                    # Optimization guides

scripts/                       # Executable validation suite
├── sweep.sh                   # Configurable diagnostics sweep
├── sweep_config.sh.example    # Example configuration
├── health-check.sh            # Detailed health check with fix instructions
├── check_host.sh              # Quick GPU/RAM checklist
└── README.md                  # Scripts documentation

archive/                       # Historical drafts (git-ignored)
.gitignore                     # Excludes archive/ and private files
LICENSE                        # MIT License
```

---

## Hardware Used (Example)

| Component | Specification |
|-----------|--------------|
| **CPU** | Intel Core i7-13700F — 16C (8P/8E), 24T, 5.2 GHz Max Turbo |
| **RAM** | 96 GB DDR5-5200 (4 DIMMs, Gear 1, CL40) |
| **GPU** | NVIDIA RTX 4060 Ti 16 GB GDDR6 (Ada Lovelace, SM89) |
| **Storage** | 1 TB NVMe Gen4 + 1.82 TB 7200 RPM + 3.64 TB 5400 RPM |
| **Network** | 2.5 GbE + Wi-Fi 6E |

> **Note:** These specs reflect the hardware used to develop the architecture. The design principles apply to any modern CPU/GPU with sufficient RAM and fast storage.

---

## License

MIT License — free to adapt, modify, and redistribute for any purpose.

---

*Project Host is a working example of how to build a high-resilience, modular Linux workstation that balances software development needs with demanding LLM inference workloads on consumer hardware.*