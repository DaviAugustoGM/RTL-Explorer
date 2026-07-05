#!/usr/bin/env python3
"""Small live simulator for the RTLIL cells emitted by the RTL Explorer flow."""

from __future__ import annotations

import json
import sys
from pathlib import Path


UNKNOWN = None


def parameter_int(value, default=0):
    if isinstance(value, int):
        return value
    if not value:
        return default
    try:
        return int(str(value), 2)
    except ValueError:
        return default


def mask(width):
    return (1 << width) - 1 if width > 0 else 0


class NetlistSimulator:
    def __init__(self, path: str, top: str):
        design = json.loads(Path(path).read_text(encoding="utf-8"))
        try:
            self.module = design["modules"][top]
        except KeyError as exc:
            raise ValueError(f"Modulo superior '{top}' nao existe no JSON.") from exc
        self.ports = self.module.get("ports", {})
        self.netnames = self.module.get("netnames", {})
        self.watches = {}
        self.cells = self.module.get("cells", {})
        self.bits: dict[int, int | None] = {}
        self.previous_inputs: dict[str, int | None] = {}
        self.sequential = []
        self.combinational = []
        for cell in self.cells.values():
            if self.is_sequential(cell["type"]):
                self.sequential.append(cell)
            else:
                self.combinational.append(cell)
        self.reset()

    @staticmethod
    def is_sequential(kind):
        return kind in {"$dff", "$dffe", "$adff", "$adffe", "$sdff", "$sdffe", "$dlatch"}

    def reset(self):
        self.bits.clear()
        for port in self.ports.values():
            for bit in port.get("bits", []):
                if isinstance(bit, int):
                    self.bits.setdefault(bit, 0 if port.get("direction") == "input" else UNKNOWN)
        for cell in self.sequential:
            self.write_port(cell, "Q", 0)
        self.previous_inputs = {
            name: self.read_bits(info.get("bits", []))
            for name, info in self.ports.items()
            if info.get("direction") == "input"
        }
        self.evaluate()

    def read_bits(self, bits):
        value = 0
        for index, bit in enumerate(bits):
            if isinstance(bit, str):
                if bit in {"x", "z"}:
                    return UNKNOWN
                current = int(bit)
            else:
                current = self.bits.get(bit, UNKNOWN)
                if current is UNKNOWN:
                    return UNKNOWN
            value |= current << index
        return value

    def write_bits(self, bits, value):
        for index, bit in enumerate(bits):
            if not isinstance(bit, int):
                continue
            self.bits[bit] = UNKNOWN if value is UNKNOWN else (value >> index) & 1

    def read_port(self, cell, name):
        return self.read_bits(cell.get("connections", {}).get(name, []))

    def write_port(self, cell, name, value):
        self.write_bits(cell.get("connections", {}).get(name, []), value)

    def port_width(self, cell, name):
        return len(cell.get("connections", {}).get(name, []))

    def set_input(self, name, text):
        info = self.ports.get(name)
        if not info or info.get("direction") != "input":
            raise ValueError(f"Entrada desconhecida: {name}")
        width = len(info.get("bits", []))
        value = int(text, 0) & mask(width)
        old = self.read_bits(info["bits"])
        self.write_bits(info["bits"], value)
        self.evaluate()
        self.apply_async_controls(name)
        self.capture_edges(name, old, value)
        self.previous_inputs[name] = value
        self.evaluate()

    def apply_async_controls(self, changed_name):
        changed_bits = self.ports.get(changed_name, {}).get("bits", [])
        for cell in self.sequential:
            kind = cell["type"]
            if kind in {"$adff", "$adffe"}:
                reset_bits = cell.get("connections", {}).get("ARST", [])
                if not set(reset_bits).intersection(changed_bits):
                    continue
                reset = self.read_port(cell, "ARST")
                polarity = parameter_int(cell.get("parameters", {}).get("ARST_POLARITY"), 1)
                if reset is not UNKNOWN and ((reset == 1) == bool(polarity)):
                    value = parameter_int(cell.get("parameters", {}).get("ARST_VALUE"), 0)
                    self.write_port(cell, "Q", value)
            elif kind == "$dlatch":
                enable = self.read_port(cell, "EN")
                polarity = parameter_int(cell.get("parameters", {}).get("EN_POLARITY"), 1)
                if enable is not UNKNOWN and ((enable == 1) == bool(polarity)):
                    self.write_port(cell, "Q", self.read_port(cell, "D"))

    def capture_edges(self, changed_name, old, new):
        if old is UNKNOWN or new is UNKNOWN or old == new:
            return
        self.evaluate()
        updates = []
        for cell in self.sequential:
            kind = cell["type"]
            clock_bits = cell.get("connections", {}).get("CLK", [])
            changed_bits = self.ports.get(changed_name, {}).get("bits", [])
            if not set(clock_bits).intersection(changed_bits):
                continue
            polarity = parameter_int(cell.get("parameters", {}).get("CLK_POLARITY"), 1)
            active_edge = (old == 0 and new == 1) if polarity else (old == 1 and new == 0)
            if not active_edge:
                continue
            reset_applied = False
            if kind in {"$adff", "$adffe", "$sdff", "$sdffe"}:
                reset_name = "ARST" if kind.startswith("$a") else "SRST"
                reset = self.read_port(cell, reset_name)
                reset_polarity = parameter_int(cell.get("parameters", {}).get(f"{reset_name}_POLARITY"), 1)
                if reset is not UNKNOWN and ((reset == 1) == bool(reset_polarity)):
                    value = parameter_int(cell.get("parameters", {}).get(f"{reset_name}_VALUE"), 0)
                    updates.append((cell, value))
                    reset_applied = True
            if reset_applied:
                continue
            enable = self.read_port(cell, "EN") if "EN" in cell.get("connections", {}) else 1
            en_polarity = parameter_int(cell.get("parameters", {}).get("EN_POLARITY"), 1)
            if (enable == 1) != bool(en_polarity):
                continue
            value = self.read_port(cell, "D")
            updates.append((cell, value))
        for cell, value in updates:
            self.write_port(cell, "Q", value)

    def evaluate(self):
        for _ in range(max(4, len(self.combinational) + 1)):
            before = dict(self.bits)
            for cell in self.combinational:
                self.evaluate_cell(cell)
            if before == self.bits:
                break

    def evaluate_cell(self, cell):
        kind = cell["type"]
        a = self.read_port(cell, "A")
        b = self.read_port(cell, "B")
        width = self.port_width(cell, "Y")
        if kind in {"$not", "$_NOT_"}:
            result = UNKNOWN if a is UNKNOWN else (~a & mask(width))
        elif kind in {"$pos"}:
            result = a
        elif kind in {"$neg"}:
            result = UNKNOWN if a is UNKNOWN else (-a & mask(width))
        elif kind in {"$and", "$_AND_"}:
            result = UNKNOWN if UNKNOWN in (a, b) else a & b
        elif kind in {"$or", "$_OR_"}:
            result = UNKNOWN if UNKNOWN in (a, b) else a | b
        elif kind in {"$xor", "$_XOR_"}:
            result = UNKNOWN if UNKNOWN in (a, b) else a ^ b
        elif kind == "$xnor":
            result = UNKNOWN if UNKNOWN in (a, b) else ~(a ^ b) & mask(width)
        elif kind in {"$add", "$sub", "$mul"}:
            if UNKNOWN in (a, b):
                result = UNKNOWN
            elif kind == "$add":
                result = (a + b) & mask(width)
            elif kind == "$sub":
                result = (a - b) & mask(width)
            else:
                result = (a * b) & mask(width)
        elif kind in {"$shl", "$sshl"}:
            result = UNKNOWN if UNKNOWN in (a, b) else (a << b) & mask(width)
        elif kind in {"$shr", "$sshr"}:
            result = UNKNOWN if UNKNOWN in (a, b) else (a >> b) & mask(width)
        elif kind in {"$eq", "$eqx"}:
            result = UNKNOWN if UNKNOWN in (a, b) else int(a == b)
        elif kind in {"$ne", "$nex"}:
            result = UNKNOWN if UNKNOWN in (a, b) else int(a != b)
        elif kind in {"$lt", "$le", "$gt", "$ge"}:
            if UNKNOWN in (a, b):
                result = UNKNOWN
            else:
                result = int({"$lt": a < b, "$le": a <= b, "$gt": a > b, "$ge": a >= b}[kind])
        elif kind in {"$logic_not", "$reduce_bool"}:
            result = UNKNOWN if a is UNKNOWN else int(not a) if kind == "$logic_not" else int(bool(a))
        elif kind in {"$logic_and", "$logic_or"}:
            result = UNKNOWN if UNKNOWN in (a, b) else int(bool(a) and bool(b)) if kind == "$logic_and" else int(bool(a) or bool(b))
        elif kind in {"$reduce_and", "$reduce_or", "$reduce_xor"}:
            if a is UNKNOWN:
                result = UNKNOWN
            elif kind == "$reduce_and":
                result = int(a == mask(self.port_width(cell, "A")))
            elif kind == "$reduce_or":
                result = int(bool(a))
            else:
                result = a.bit_count() & 1
        elif kind in {"$mux", "$_MUX_"}:
            select = self.read_port(cell, "S")
            result = UNKNOWN if select is UNKNOWN else b if select else a
        elif kind == "$pmux":
            select = self.read_port(cell, "S")
            if select is UNKNOWN:
                result = UNKNOWN
            else:
                result = a
                for index in range(self.port_width(cell, "S")):
                    if select & (1 << index):
                        b_bits = cell.get("connections", {}).get("B", [])
                        start = index * width
                        result = self.read_bits(b_bits[start : start + width])
                        break
        else:
            return
        self.write_port(cell, "Y", result)

    def values(self):
        result = []
        for name, info in self.ports.items():
            value = self.read_bits(info.get("bits", []))
            result.append((name, "x" if value is UNKNOWN else str(value)))
        for alias, bits in self.watches.items():
            value = self.read_bits(bits)
            result.append((alias, "x" if value is UNKNOWN else str(value)))
        return result

    def add_watch(self, alias, module_name, signal_name):
        suffix = f".{signal_name}".lower()
        candidates = []
        for name, info in self.netnames.items():
            lowered = name.lower()
            if lowered == signal_name.lower() or lowered.endswith(suffix):
                score = 0 if module_name.lower() in lowered else 1
                candidates.append((score, len(name), name, info.get("bits", [])))
        if not candidates:
            raise ValueError(f"Sinal interno nao encontrado: {module_name}.{signal_name}")
        candidates.sort(key=lambda item: (item[0], item[1]))
        self.watches[alias] = candidates[0][3]


def emit(kind, fields=()):
    print("\t".join([kind, *fields]), flush=True)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: netlist_sim.py NETLIST.json TOP")
    simulator = NetlistSimulator(sys.argv[1], sys.argv[2])
    descriptions = []
    for name, info in simulator.ports.items():
        descriptions.append(f"{name}:{info.get('direction', '')}:{len(info.get('bits', []))}")
    emit("READY", descriptions)
    emit("VALUES", [f"{name}={value}" for name, value in simulator.values()])
    for line in sys.stdin:
        parts = line.rstrip("\r\n").split("\t")
        try:
            if parts[0] == "SET" and len(parts) == 3:
                simulator.set_input(parts[1], parts[2])
            elif parts[0] == "WATCH" and len(parts) == 4:
                simulator.add_watch(parts[1], parts[2], parts[3])
            elif parts[0] == "RESET":
                simulator.reset()
            elif parts[0] == "EVAL":
                simulator.evaluate()
            elif parts[0] == "QUIT":
                return
            else:
                raise ValueError("Comando de simulacao invalido.")
            emit("VALUES", [f"{name}={value}" for name, value in simulator.values()])
        except Exception as exc:  # Keep the GUI process alive after bad input.
            emit("ERROR", [str(exc).replace("\t", " ").replace("\n", " ")])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        emit("ERROR", [str(exc).replace("\t", " ").replace("\n", " ")])
        raise
