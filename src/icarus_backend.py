#!/usr/bin/env python3
"""Persistent GUI protocol adapter for replay-based Icarus simulation."""

from __future__ import annotations

import subprocess
import sys
import os
from pathlib import Path


def emit(kind: str, fields=()):
    print("\t".join([kind, *fields]), flush=True)


def tool_environment(root_value: str):
    environment = os.environ.copy()
    root = Path(root_value)
    environment["PATH"] = os.pathsep.join(
        [str(root / "bin"), str(root / "lib"), environment.get("PATH", "")]
    )
    environment["YOSYSHQ_ROOT"] = str(root)
    return environment


def compile_design(arguments):
    iverilog, root, output, design, testbench = arguments
    process = subprocess.run(
        [
            iverilog,
            "-g2012",
            "-B",
            str(Path(root) / "lib" / "ivl"),
            "-s",
            "rtlx_tb",
            "-o",
            output,
            design,
            testbench,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=tool_environment(root),
    )
    if process.returncode:
        raise RuntimeError((process.stderr or process.stdout).strip())


def read_metadata(path: str):
    config = {"inputs": [], "outputs": []}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if fields[0] == "VVP":
            config["vvp"] = fields[1]
        elif fields[0] == "DESIGN":
            config["design"] = fields[1]
        elif fields[0] == "ROOT":
            config["root"] = fields[1]
        elif fields[0] == "STIMULUS":
            config["stimulus"] = fields[1]
        elif fields[0] in {"INPUT", "OUTPUT"}:
            config[fields[0].lower() + "s"].append((fields[1], int(fields[2])))
    return config


class IcarusAdapter:
    def __init__(self, metadata: str):
        self.config = read_metadata(metadata)
        self.input_indexes = {
            name: index for index, (name, _width) in enumerate(self.config["inputs"])
        }
        self.history: list[tuple[int, int]] = []

    def run(self):
        stimulus = Path(self.config["stimulus"])
        stimulus.write_text(
            "".join(f"{index} {value:x}\n" for index, value in self.history),
            encoding="ascii",
        )
        process = subprocess.run(
            [self.config["vvp"], self.config["design"], f"+stimulus={stimulus}"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
            env=tool_environment(self.config["root"]),
        )
        if process.returncode:
            raise RuntimeError((process.stderr or process.stdout).strip())
        marker = next(
            (line for line in reversed(process.stdout.splitlines()) if line.startswith("RTLX_VALUES")),
            None,
        )
        if marker is None:
            detail = (process.stderr or process.stdout).strip()
            raise RuntimeError(f"Icarus did not return signal values. {detail}")
        emit("VALUES", marker.split("\t")[1:])

    def set_input(self, name: str, value: str):
        if name not in self.input_indexes:
            raise ValueError(f"Unknown input: {name}")
        self.history.append((self.input_indexes[name], int(value, 0)))


def main():
    if len(sys.argv) == 7 and sys.argv[1] == "--compile":
        compile_design(sys.argv[2:])
        return
    if len(sys.argv) != 2:
        raise SystemExit("usage: icarus_backend.py METADATA.tsv")
    adapter = IcarusAdapter(sys.argv[1])
    descriptions = [
        f"{name}:input:{width}" for name, width in adapter.config["inputs"]
    ] + [f"{name}:output:{width}" for name, width in adapter.config["outputs"]]
    emit("READY", descriptions)
    adapter.run()
    for line in sys.stdin:
        parts = line.rstrip("\r\n").split("\t")
        try:
            if parts[0] == "SET" and len(parts) == 3:
                adapter.set_input(parts[1], parts[2])
            elif parts[0] == "RESET":
                adapter.history.clear()
            elif parts[0] == "EVAL":
                adapter.history.append((-1, 0))
            elif parts[0] == "WATCH":
                pass
            elif parts[0] == "QUIT":
                return
            else:
                raise ValueError("Invalid simulation command.")
            adapter.run()
        except Exception as exc:
            emit("ERROR", [str(exc).replace("\t", " ").replace("\n", " ")])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        emit("ERROR", [str(exc).replace("\t", " ").replace("\n", " ")])
        raise
