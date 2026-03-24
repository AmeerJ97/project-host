# Inference Benchmarks (Coming Soon)

This section will contain detailed benchmark results for various model sizes and configurations on the Project Host system. The benchmarks will demonstrate performance characteristics of the tiered memory architecture and GPU optimization techniques described in this guide.

Benchmark data is currently being collected and validated — results will be published here once the validation suite is complete.

## Planned Measurements

- Token generation speeds (tok/s) for models ranging from 9B to 72B parameters
- VRAM utilization and PCIe bottleneck analysis
- Comparison between different optimization strategies (GPU layer splitting, unified memory, etc.)
- Cold-start latency improvements with NVMe staging

## Expected Architectural Insights

1. **PCIe x8 Gen4 bandwidth** (15.75 GB/s) is expected to be the primary bottleneck for models that overflow VRAM
2. **NVMe staging** is projected to reduce cold-start times significantly compared to HDD storage
3. **GPU layer optimization** may double prompt processing speed compared to conservative auto-splitting
4. **Unified Memory** should enable larger models to run that would otherwise OOM due to compute graph requirements

Refer to the architecture documentation for design principles that address these performance characteristics.