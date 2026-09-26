"""Expose generated clock drivers for delta-cycle scheduling by the C++ bridge."""

import json
from pathlib import Path
import sys


def prepare(design, top):
    module = design["modules"][top]
    ports = module.setdefault("ports", {})
    nets = module.setdefault("netnames", {})
    cells = module.get("cells", {})
    external = {bit for port in ports.values() if port["direction"] == "input"
                for bit in port["bits"]}
    clocks = sorted({bit for cell in cells.values()
                     for bit in cell.get("connections", {}).get("CLK", [])
                     if isinstance(bit, int) and bit not in external})
    all_bits = [bit for item in [*ports.values(), *nets.values()] for bit in item["bits"]]
    all_bits += [bit for cell in cells.values()
                 for bits in cell.get("connections", {}).values() for bit in bits]
    next_bit = max((bit for bit in all_bits if isinstance(bit, int)), default=1) + 1
    result = []
    for index, bit in enumerate(clocks):
        prefix = f"__rtlx_generated_clock_{index}"
        while any(prefix + suffix in ports or prefix + suffix in nets
                  for suffix in ("_drive", "_source")):
            prefix += "_"
        drive, source = prefix + "_drive", prefix + "_source"
        ports[drive] = {"direction": "input", "bits": [next_bit]}
        ports[source] = {"direction": "output", "bits": [bit]}
        for name in (drive, source):
            nets[name] = {"hide_name": 0, "bits": ports[name]["bits"], "attributes": {}}
        # Only clock pins move. Data paths, feedback, and probes retain the original net.
        for cell in cells.values():
            connections = cell.get("connections", {})
            if "CLK" in connections:
                connections["CLK"] = [next_bit if value == bit else value
                                      for value in connections["CLK"]]
        result.append((drive, source))
        next_bit += 1
    return result


if __name__ == "__main__":
    path, top, output = sys.argv[1:]
    design = json.loads(Path(path).read_text(encoding="utf-8"))
    clocks = prepare(design, top)
    if clocks:
        Path(output).write_text(json.dumps(design), encoding="utf-8")
    for drive, source in clocks:
        print(f"{drive}\t{source}")
