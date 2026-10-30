"""Select the actual Duo runtime and an ordinary iPhone for release regression tests."""

import json
import os
import re
import sys


def select(devices):
    candidates = []
    for runtime, values in devices.items():
        match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if not match:
            continue
        version = tuple(int(value or 0) for value in match.groups())
        for device in values:
            if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
                candidates.append((version, device))
    duo = [item for item in candidates if item[1]["name"] == "iPhone Duo" and item[0] >= (27, 1, 0)]
    standard = [item for item in candidates if item[1]["name"] != "iPhone Duo"]
    if not duo:
        raise ValueError("iPhone Duo on iOS 27.1 or later is required; an ordinary iPhone is not a substitute")
    if not standard:
        raise ValueError("An ordinary iPhone simulator is required for the standard-edition regression run")
    return max(duo, key=lambda item: item[0]), max(standard, key=lambda item: item[0])


def main():
    duo, standard = select(json.load(sys.stdin)["devices"])
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        output.write(f"DUO_SIMULATOR_ID={duo[1]['udid']}\n")
        output.write(f"STANDARD_SIMULATOR_ID={standard[1]['udid']}\n")
    for name, item in [("Duo", duo), ("Standard", standard)]:
        print(f"{name}: {item[1]['name']}, iOS {'.'.join(map(str, item[0]))}, {item[1]['udid']}")


if __name__ == "__main__":
    main()
