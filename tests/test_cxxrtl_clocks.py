import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("cxxrtl_clocks", ROOT / "src" / "cxxrtl_clocks.py")
CLOCKS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLOCKS)


class ClockPreparationTest(unittest.TestCase):
    def test_shared_internal_clock_preserves_data_feedback_and_original_names(self):
        module = {
            "ports": {"clk": {"direction": "input", "bits": [2]}},
            "netnames": {"tick": {"bits": [3], "attributes": {"keep": "1"}}},
            "cells": {
                "producer": {"connections": {"CLK": [2], "Q": [3], "D": [4]}},
                "consumer": {"connections": {"CLK": [3], "D": [3], "Q": [4]}},
                "other": {"connections": {"CLK": [3], "Q": [5]}},
            },
        }
        ports = CLOCKS.prepare({"modules": {"top": module}}, "top")
        self.assertEqual(len(ports), 1)
        drive, source = ports[0]
        new_bit = module["ports"][drive]["bits"]
        self.assertEqual(new_bit, [6])
        self.assertEqual(module["ports"][source]["bits"], [3])
        self.assertEqual(module["cells"]["consumer"]["connections"]["CLK"], new_bit)
        self.assertEqual(module["cells"]["other"]["connections"]["CLK"], new_bit)
        self.assertEqual(module["cells"]["consumer"]["connections"]["D"], [3])
        self.assertEqual(module["cells"]["producer"]["connections"]["CLK"], [2])
        self.assertEqual(module["netnames"]["tick"]["attributes"], {"keep": "1"})

    def test_no_internal_clocks_need_no_ports(self):
        module = {
            "ports": {"clocks": {"direction": "input", "bits": [2, 3]}},
            "netnames": {},
            "cells": {str(bit): {"connections": {"CLK": [bit]}} for bit in [2, 3, "0"]},
        }
        self.assertEqual(CLOCKS.prepare({"modules": {"top": module}}, "top"), [])
        self.assertEqual(list(module["ports"]), ["clocks"])

    def test_existing_user_names_are_not_overwritten(self):
        name = "__rtlx_generated_clock_0_drive"
        module = {
            "ports": {name: {"direction": "output", "bits": [3]}},
            "netnames": {},
            "cells": {"consumer": {"connections": {"CLK": [3]}}},
        }
        drive, source = CLOCKS.prepare({"modules": {"top": module}}, "top")[0]
        self.assertNotEqual(drive, name)
        self.assertEqual(module["ports"][name]["bits"], [3])
        self.assertEqual(module["ports"][source]["bits"], [3])


if __name__ == "__main__":
    unittest.main()
