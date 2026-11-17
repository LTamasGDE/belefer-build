#!/usr/bin/env python3
"""Kiválasztja a legújabb iOS-futtatókörnyezet első elérhető iPhone-szimulátorát.

Bemenet: `xcrun simctl list devices available -j` kimenete a standard bemeneten.
Kimenet: a szimulátor UDID-je.
"""

import json
import re
import sys


def _runtime_version(runtime: str):
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


def main() -> int:
    devices = json.load(sys.stdin)["devices"]
    runtimes = sorted((r for r in devices if "iOS" in r), key=_runtime_version, reverse=True)
    for runtime in runtimes:
        for device in devices[runtime]:
            if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
                print(device["udid"])
                return 0
    print("Nem található iPhone-szimulátor.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
