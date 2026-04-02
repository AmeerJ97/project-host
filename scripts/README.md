# Scripts

Validation and diagnostic scripts for the Project Host architecture.

## Master Sweep (v4.0)

The single entry point for system validation. Supersedes all legacy scripts.

```bash
# Default profile (workstation — mixed desktop + inference)
sudo ./scripts/master-sweep.sh

# Specific profile
sudo ./scripts/master-sweep.sh --profile inference-only
sudo ./scripts/master-sweep.sh --profile benchmark

# No color (for piping / logging)
sudo ./scripts/master-sweep.sh --no-color
```

## Profiles

Configuration profiles define expected values for each check. Located in `profiles/`.

| Profile | Use Case | Power | CPU Affinity | CPU Cap |
|---------|----------|-------|-------------|---------|
| **workstation** (default) | Desktop + Chrome + Claude Code + inference | 140W | All 16 cores | 98% per core |
| **inference-only** | Dedicated inference, desktop idle | 150W | P-cores (0-7) | 98% per core |
| **benchmark** | Isolated testing, accepts thermal risk | 165W | All 16 cores | 100% per core |

To create a custom profile, copy `profiles/workstation.conf` and adjust the values.

## Directory Structure

```
scripts/
├── master-sweep.sh          # Main validation script (v4.0)
├── rgb_sniper.py            # RGB control utility
├── profiles/
│   ├── workstation.conf     # Default profile
│   ├── inference-only.conf  # Dedicated inference
│   └── benchmark.conf       # Performance testing
├── legacy/                  # Superseded scripts (reference only)
│   ├── sweep.sh
│   ├── health-check.sh
│   ├── check_host.sh
│   ├── check-optimizations.sh
│   └── sweep_config.sh.example
└── README.md
```

## Configuration Reference

See [docs/INFERENCE-CONFIG.md](../docs/INFERENCE-CONFIG.md) for the full configuration reference including:
- Service file contents
- sysctl values and rationale
- CUDA/GPU access setup
- Lessons learned from the 2026-04-01 tuning session
