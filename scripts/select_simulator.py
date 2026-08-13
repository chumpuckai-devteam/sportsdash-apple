#!/usr/bin/env python3
"""
select_simulator.py
Dynamic UDID selector for iOS/tvOS simulators in CI.
Prefers newest/relevant device; falls back gracefully.
No YAML embedding issues; checked-in script.
Usage:
  python3 scripts/select_simulator.py --platform iphone
  python3 scripts/select_simulator.py --platform tvos
Prints UDID or exits 1 with message to stderr.
"""
import argparse
import json
import subprocess
import sys
from typing import Optional, List, Dict, Any

def list_devices() -> Dict[str, Any]:
    try:
        out = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return json.loads(out)
    except Exception as e:
        print(f"ERROR: failed to list simulators: {e}", file=sys.stderr)
        sys.exit(1)

def select_best_iphone(devices: Dict[str, Any]) -> Optional[str]:
    """Prefer iPhone 16 Pro (or Pro Max), then latest numbered iPhone, then any iPhone."""
    candidates: List[tuple] = []
    for rt, devs in devices.get("devices", {}).items():
        if not isinstance(devs, list):
            continue
        for d in devs:
            if not isinstance(d, dict):
                continue
            name = d.get("name", "")
            udid = d.get("udid", "")
            state = d.get("state", "")
            if "iPhone" not in name or not udid or state != "Booted" and state != "Shutdown":
                # accept available even if shutdown, as simctl can boot
                pass
            if "iPhone" not in name or not udid:
                continue
            # scoring: 16 Pro highest, then 16, then higher numbers
            score = 0
            if "16 Pro" in name:
                score = 100 if "Max" not in name else 99
            elif "16" in name:
                score = 90
            elif "15" in name:
                score = 80
            elif "14" in name:
                score = 70
            else:
                score = 50
            # prefer booted? but for CI usually not booted yet
            candidates.append((score, name, udid))
    if not candidates:
        return None
    candidates.sort(reverse=True)  # highest score first
    return candidates[0][2]

def select_best_tvos(devices: Dict[str, Any]) -> Optional[str]:
    """Any available Apple TV (prefer newest)."""
    candidates: List[tuple] = []
    for rt, devs in devices.get("devices", {}).items():
        if not isinstance(devs, list):
            continue
        for d in devs:
            if not isinstance(d, dict):
                continue
            name = d.get("name", "")
            udid = d.get("udid", "")
            if "Apple TV" not in name or not udid:
                continue
            # prefer higher gen
            gen = 0
            for g in range(4, 20):
                if f"{g}" in name or f"HD" in name or "4K" in name:
                    gen = g
                    break
            candidates.append((gen, name, udid))
    if not candidates:
        return None
    candidates.sort(reverse=True)
    return candidates[0][2]

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["iphone", "tvos"], required=True)
    args = parser.parse_args()

    data = list_devices()
    if args.platform == "iphone":
        udid = select_best_iphone(data)
        if not udid:
            print("ERROR: No iPhone simulator found", file=sys.stderr)
            sys.exit(1)
        print(udid)
    else:
        udid = select_best_tvos(data)
        if not udid:
            print("ERROR: No tvOS simulator found", file=sys.stderr)
            sys.exit(1)
        print(udid)

if __name__ == "__main__":
    main()
