[< Back to Index](README.md)

## 19. Diagnostics Checklist

Run as a sweep to verify all subsystems are correctly configured.

| # | Subsystem | Command | Expected |
|---|-----------|---------|----------|
| 1 | GPU Driver | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` | `590.48.01` |
| 2 | GPU Power Limit | `nvidia-smi -q -d power \| grep "Current Power Limit"` | `140.00 W` |
| 3 | GPU Persistence | `nvidia-smi -q \| grep "Persistence Mode"` | `Enabled` |
| 4 | GPU BAR1 | `nvidia-smi -q -d BAR1 \| grep Total` | `16384 MiB` |
| 5 | PCIe Link | `nvidia-smi -q -d pcie \| grep "Current.*Gen"` | `Gen 4` |
| 6 | CUDA | `nvcc --version` | `cuda_13.0` |
| 7 | UVM Cache | `cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_sysmem` | `1` |
| 8 | Ollama | `systemctl is-active ollama` | `active` |
| 9 | Ollama API | `curl -s http://localhost:11434/api/tags \| jq '.models \| length'` | `≥ 0` |
| 10 | Docker Runtime | `docker info 2>/dev/null \| grep "Default Runtime"` | `nvidia` |
| 11 | CPU Governor | `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` | `performance` |
| 12 | Turbo | `cat /sys/devices/system/cpu/intel_pstate/no_turbo` | `0` |
| 13 | Swappiness | `sysctl -n vm.swappiness` | `10` |
| 14 | HugePages | `grep HugePages_Total /proc/meminfo` | `4096` |
| 15 | THP | `cat /sys/kernel/mm/transparent_hugepage/enabled` | `[madvise]` |
| 16 | KSM | `cat /sys/kernel/mm/ksm/run` | `0` |
| 17 | Swap | `swapon --show --noheadings \| wc -l` | `≥ 2` |
| 18 | NVMe Scheduler | `cat /sys/block/nvme0n1/queue/scheduler` | `[none]` |
| 19 | NVMe Readahead | `cat /sys/block/nvme0n1/queue/read_ahead_kb` | `2048` |
| 20 | IOMMU | `dmesg \| grep -i "IOMMU enabled"` | Match found |
| 21 | NUMA Balancing | `sysctl -n kernel.numa_balancing` | `0` |
| 22 | Firewall | `sudo ufw status \| head -1` | `Status: active` |
| 23 | Compaction | `sysctl -n vm.compaction_proactiveness` | `0` |
| 24 | TCP FastOpen | `sysctl -n net.ipv4.tcp_fastopen` | `3` |
| 25 | GRUB Params | `cat /proc/cmdline` | Contains `zswap.enabled=0 pcie_aspm=off` |

### One-liner Sweep Script

```bash
echo "=== Project Host Diagnostics ===" && \
echo "1. GPU Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader)" && \
echo "2. Power Limit: $(nvidia-smi -q -d power 2>/dev/null | grep 'Current Power Limit' | awk '{print $5,$6}')" && \
echo "3. Persistence: $(nvidia-smi -q 2>/dev/null | grep 'Persistence Mode' | awk '{print $4}')" && \
echo "4. BAR1: $(nvidia-smi -q -d BAR1 2>/dev/null | grep Total | awk '{print $3,$4}')" && \
echo "5. CUDA: $(nvcc --version 2>/dev/null | tail -1)" && \
echo "6. UVM cache_sysmem: $(cat /sys/module/nvidia_uvm/parameters/uvm_exp_gpu_cache_sysmem 2>/dev/null || echo 'N/A')" && \
echo "7. Ollama: $(systemctl is-active ollama)" && \
echo "8. Docker Runtime: $(docker info 2>/dev/null | grep 'Default Runtime' | awk '{print $3}')" && \
echo "9. CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)" && \
echo "10. Swappiness: $(sysctl -n vm.swappiness)" && \
echo "11. HugePages: $(grep HugePages_Total /proc/meminfo | awk '{print $2}')" && \
echo "12. THP: $(cat /sys/kernel/mm/transparent_hugepage/enabled)" && \
echo "13. KSM: $(cat /sys/kernel/mm/ksm/run)" && \
echo "14. Swap count: $(swapon --show --noheadings | wc -l)" && \
echo "15. NVMe scheduler: $(cat /sys/block/nvme0n1/queue/scheduler)" && \
echo "16. NVMe readahead: $(cat /sys/block/nvme0n1/queue/read_ahead_kb) KB" && \
echo "17. NUMA balancing: $(sysctl -n kernel.numa_balancing)" && \
echo "18. TCP FastOpen: $(sysctl -n net.ipv4.tcp_fastopen)" && \
echo "19. Compaction: $(sysctl -n vm.compaction_proactiveness)" && \
echo "=== Done ==="
```
