[< Back to Index](README.md)

## 12. CPU Governor

| Setting | Value |
|---------|-------|
| Driver | `intel_pstate` |
| Governor | `performance` |
| Turbo | Enabled (`no_turbo=0`) |

The `performance` governor locks all cores at maximum frequency — eliminates frequency ramping latency that would affect inference response times.

### systemd Services

- `cpu-governor.service` — sets governor to `performance` at boot
- `thp-madvise.service` — applies THP settings at boot

**Verify:**
```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/devices/system/cpu/intel_pstate/no_turbo
cpupower frequency-info | grep "current policy"
```
