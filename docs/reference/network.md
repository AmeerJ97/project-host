[< Back to Index](README.md)

## 15. Network

### Interfaces

| Interface | Hardware | Speed | Status |
|-----------|----------|-------|--------|
| Ethernet | Realtek RTL8125 | 2.5 GbE (2500 Mbps) | Primary |
| Wi-Fi | Intel Wi-Fi 6E | — | Available |

### LAN Topology

| IP | Role |
|----|------|
| 192.168.2.10 | This workstation (Project Host) |
| 192.168.2.11 | k3s node 1 |
| 192.168.2.12 | k3s node 2 |
| 192.168.2.13 | k3s node 3 |

### Firewall

**Tool:** `ufw`

Allowed from `192.168.2.0/24`:
- SSH (22)
- KDE Connect (1714:1764 TCP/UDP)
- Ollama (11434)
- Triton Inference Server

### TCP Tuning

Buffer sizes and TCP parameters are configured in the sysctl section (Section 8, Network group).

**Verify:**
```bash
ip link show | grep -E "state UP|mtu"
ethtool eth0 2>/dev/null | grep Speed || ethtool enp* 2>/dev/null | grep Speed
sudo ufw status verbose
```
