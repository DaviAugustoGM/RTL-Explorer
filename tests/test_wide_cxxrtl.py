"""Exercise the generated live bridge against real CXXRTL models."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WIDTHS = (1, 32, 64, 65, 127, 128, 129, 256)


class WideBridgeTest(unittest.TestCase):
    def test_round_trip_and_internal_watches(self):
        if not shutil.which("tclsh") or not shutil.which("g++"):
            self.skipTest("tclsh and g++ are required")
        with tempfile.TemporaryDirectory(prefix="rtlx-wide-") as folder:
            build = Path(folder)
            generator = build / "generate.tcl"
            generator.write_text(r"""
set ::APP_DIR [file join [lindex $argv 0] src]
source [file join $::APP_DIR simulation_backends.tcl]
set inputs {}
set outputs {}
foreach width {1 32 64 65 127 128 129 256} {
    lappend inputs [dict create name in_$width width $width]
    lappend outputs [dict create name out_$width width $width]
}
::svvs::simulation_backends::writeCxxrtlBridge [lindex $argv 1] \
    [dict create inputs $inputs outputs $outputs]
puts [::svvs::toolchain::yosys]
puts [::svvs::toolchain::cxxrtlInclude]
""")
            paths = subprocess.check_output(
                ["tclsh", str(generator), str(ROOT), str(build / "bridge.cpp")], text=True
            ).splitlines()
            yosys, include = paths[-2:]
            if not yosys or not include:
                self.skipTest("Yosys and CXXRTL headers are required")
            ports = []
            assigns = []
            for width in WIDTHS:
                ports += [f"input [{width-1}:0] in_{width}", f"output [{width-1}:0] out_{width}"]
                assigns.append(f"assign out_{width} = in_{width};")
            design = build / "design.v"
            design.write_text("module rtl_explorer_top(" + ",".join(ports) + ");\n" +
                              "\n".join(assigns) + "\nendmodule\n")
            for optimization in (0, 3):
                with self.subTest(optimization=optimization):
                    subprocess.run([yosys, "-Q", "-q", "-p",
                        f"read_verilog {design}; hierarchy -top rtl_explorer_top; "
                        f"write_cxxrtl -O{optimization} -g2 {build / 'cxxrtl_model.cpp'}"],
                        check=True, capture_output=True, text=True, timeout=60)
                    exe = build / "bridge"
                    subprocess.run(["g++", "-std=c++17", "-O0", "-I" + include,
                        str(build / "bridge.cpp"), "-o", str(exe)], check=True,
                        capture_output=True, text=True, timeout=60)
                    commands = []
                    expected = []
                    for width in WIDTHS:
                        commands.append(f"WATCH\tw{width}\trtl_explorer_top\tout_{width}")
                        expected.append(None)
                        for value in (1 << (width - 1), (1 << width) - 1,
                                      int("a5" * ((width + 7) // 8), 16) & ((1 << width) - 1), 0):
                            for literal in (str(value), hex(value), bin(value), oct(value),
                                            "+" + str(value), "0" + oct(value)[2:]):
                                commands.append(f"SET\tin_{width}\t{literal}")
                                expected.append({f"in_{width}": value, f"out_{width}": value,
                                                 f"w{width}": value})
                    commands += ["RESET", "QUIT"]
                    result = subprocess.run([str(exe)], input="\n".join(commands) + "\n",
                        capture_output=True, text=True, timeout=30, check=True)
                    lines = result.stdout.splitlines()
                    self.assertTrue(lines[0].startswith("READY\t"))
                    self.assertEqual(len(lines), 3 + len(expected))
                    for line, values in zip(lines[2:-1], expected):
                        self.assertTrue(line.startswith("VALUES\t"), line)
                        if values:
                            actual = dict(pair.split("=", 1) for pair in line.split("\t")[1:])
                            for name, value in values.items():
                                self.assertEqual(actual[name], str(value), name)
                    reset = dict(pair.split("=", 1) for pair in lines[-1].split("\t")[1:])
                    self.assertTrue(all(int(value) == 0 for value in reset.values()))


if __name__ == "__main__":
    unittest.main()
