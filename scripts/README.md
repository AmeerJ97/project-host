# Scripts

This directory contains executable scripts used to validate, monitor, and maintain the Project Host architecture.

## Overview

| Script | Purpose |
|--------|---------|
| `sweep.sh` | Comprehensive system diagnostics sweep — verifies all major subsystem configurations against expected values. |
| `health-check.sh` | Detailed health check with color-coded results and fix instructions for each failure. |
| `check_host.sh` | Quick checklist for critical GPU and memory configuration parameters. |

## Usage

All scripts are designed to be run from the repository root:

```bash
./scripts/sweep.sh
./scripts/health-check.sh [--no-color] [--section SECTION]
./scripts/check_host.sh
```

## Configuration

The scripts contain hardcoded expectation values that match the original Project Host hardware and software configuration. To adapt them to a different system:

1. **`sweep.sh`** uses environment variables and an optional configuration file.  
   Copy `sweep_config.sh.example` to `sweep_config.sh` and adjust the values.

2. **`health-check.sh`** currently embeds expectation values directly in the script.  
   Edit the script file and replace values like driver version, power limits, etc., with those appropriate for the target hardware.

3. **`check_host.sh`** is a lightweight checklist that assumes standard NVIDIA GPU settings; modify the expected BAR size and PCIe speed if needed.

## Design Philosophy

These scripts embody the **validation‑first** approach of the Project Host architecture:

- **Automated verification** ensures that every documented configuration parameter is actually applied.
- **Self‑documenting failures** provide clear fix instructions for each mismatch.
- **Modular checks** allow selective validation (e.g., `--section GPU` in `health‑check.sh`).

They are intended as **working examples** of how to enforce a consistent system state, not as universal tools. Adapt them to the target environment by updating the expected values and adding/removing checks as needed.

## Extending

To add a new check:

1. Identify the subsystem and the command that reports its current state.
2. Add a new `check` (or `check_contains`, `check_gte`) call in the appropriate section.
3. Provide a helpful fix message that guides the user toward the correct configuration.

All scripts follow the same color‑coding and output conventions for consistency.