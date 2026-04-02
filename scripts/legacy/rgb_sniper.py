#!/usr/bin/env python3
"""
RGB Sniper — monitors Mystic Light controller and blasts color commands
the instant it wakes up during a cold-induced reset window.

Usage: sudo python3 rgb_sniper.py [--color RRGGBB] [--loop]
"""

import os
import sys
import time
import select
import argparse
import subprocess


HID_PATH = "/dev/hidraw7"
POLL_INTERVAL = 0.1  # 100ms between probes


def parse_color(hex_str: str) -> tuple[int, int, int]:
    hex_str = hex_str.lstrip("#")
    return (int(hex_str[0:2], 16), int(hex_str[2:4], 16), int(hex_str[4:6], 16))


def probe_controller(fd: int) -> bytes | None:
    """Send query command and check for response."""
    query = bytes([0x53] + [0] * 64)
    try:
        os.write(fd, query)
    except OSError:
        return None

    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try:
            return os.read(fd, 65)
        except OSError:
            return None
    return None


def send_color(fd: int, r: int, g: int, b: int, zone: int = 0) -> bool:
    """Send static color to a zone via MSI Mystic Light HID protocol."""
    # 0x52 = set LED, zone, R, G, B, mode(0=static), speed, brightness
    payload = bytearray(65)
    payload[0] = 0x52
    payload[1] = zone
    payload[2] = r
    payload[3] = g
    payload[4] = b
    payload[5] = 0x00  # static mode
    payload[6] = 0x00  # speed
    payload[7] = 0xFF  # brightness max
    try:
        os.write(fd, bytes(payload))
        return True
    except OSError as e:
        print(f"  Write error: {e}")
        return False


def try_openrgb(r: int, g: int, b: int) -> bool:
    """Fire OpenRGB as a backup method."""
    color = f"{r:02X}{g:02X}{b:02X}"
    try:
        result = subprocess.run(
            ["openrgb", "--device", "0", "--mode", "static", "--color", color],
            capture_output=True, text=True, timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False


def usb_reset_mystic_light() -> bool:
    """Reset the USB device to force re-enumeration."""
    try:
        result = subprocess.run(
            ["usbreset", "1462:7d98"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return True
    except FileNotFoundError:
        pass

    # Fallback: manual sysfs reset
    try:
        for root, dirs, files in os.walk("/sys/bus/usb/devices/"):
            for d in dirs:
                id_vendor_path = os.path.join(root, d, "idVendor")
                id_product_path = os.path.join(root, d, "idProduct")
                if os.path.exists(id_vendor_path) and os.path.exists(id_product_path):
                    with open(id_vendor_path) as f:
                        vendor = f.read().strip()
                    with open(id_product_path) as f:
                        product = f.read().strip()
                    if vendor == "1462" and product == "7d98":
                        auth_path = os.path.join(root, d, "authorized")
                        with open(auth_path, "w") as f:
                            f.write("0")
                        time.sleep(0.5)
                        with open(auth_path, "w") as f:
                            f.write("1")
                        return True
    except OSError:
        pass
    return False


def get_cpu_temp() -> float | None:
    """Read lowest CPU core temp from sensors."""
    try:
        result = subprocess.run(
            ["sensors", "-u", "coretemp-isa-0000"],
            capture_output=True, text=True, timeout=3
        )
        temps = []
        for line in result.stdout.splitlines():
            if "temp" in line and "_input" in line:
                val = float(line.split(":")[1].strip())
                temps.append(val)
        return min(temps) if temps else None
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser(description="RGB Sniper for Mystic Light")
    parser.add_argument("--color", default="FF0000", help="Hex color (default: FF0000 red)")
    parser.add_argument("--loop", action="store_true", help="Keep retrying indefinitely")
    parser.add_argument("--zones", type=int, default=3, help="Number of zones to set (default: 3)")
    args = parser.parse_args()

    r, g, b = parse_color(args.color)
    print(f"RGB Sniper armed — target color: #{args.color}")
    print(f"Monitoring {HID_PATH} and CPU temps...")
    print(f"Waiting for controller to wake up...\n")

    attempt = 0
    success_count = 0

    while True:
        attempt += 1
        temp = get_cpu_temp()
        temp_str = f"{temp:.1f}°C" if temp else "??°C"

        # Try to open the HID device
        try:
            fd = os.open(HID_PATH, os.O_RDWR)
        except OSError as e:
            print(f"\r[{attempt}] {temp_str} | HID open failed: {e}", end="", flush=True)
            time.sleep(POLL_INTERVAL)
            continue

        # Probe
        response = probe_controller(fd)

        if response is not None:
            print(f"\n\n*** CONTROLLER IS ALIVE! *** (attempt {attempt}, {temp_str})")
            print(f"    Response: {response[:16].hex()}...")

            # FIRE EVERYTHING
            print("    Sending colors via HID...")
            for zone in range(args.zones):
                ok = send_color(fd, r, g, b, zone)
                print(f"      Zone {zone}: {'OK' if ok else 'FAIL'}")

            print("    Firing OpenRGB backup...")
            orb_ok = try_openrgb(r, g, b)
            print(f"      OpenRGB: {'OK' if orb_ok else 'FAIL'}")

            success_count += 1
            print(f"\n    Total successful hits: {success_count}")

            if not args.loop:
                os.close(fd)
                print("\nDone. Run with --loop to keep hammering.")
                return

            print("    Continuing to monitor (--loop mode)...\n")
        else:
            print(f"\r[{attempt}] {temp_str} | No response — controller locked", end="", flush=True)

        os.close(fd)
        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("ERROR: Must run as root (sudo)")
        sys.exit(1)
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nSniper disarmed.")
