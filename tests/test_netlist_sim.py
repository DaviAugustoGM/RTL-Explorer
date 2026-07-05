import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("netlist_sim", ROOT / "src" / "netlist_sim.py")
NETLIST_SIM = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NETLIST_SIM)


class NetlistSimulatorTest(unittest.TestCase):
    def setUp(self):
        self.simulator = NETLIST_SIM.NetlistSimulator(
            ROOT / "tests" / "netlist_fixture.json", "rtl_explorer_top"
        )

    def values(self):
        return dict(self.simulator.values())

    def test_combinational_values_update_immediately(self):
        self.simulator.set_input("a", "1")
        self.simulator.set_input("b", "1")
        self.assertEqual(self.values()["y"], "1")

    def test_register_captures_on_rising_edge(self):
        self.simulator.set_input("a", "1")
        self.simulator.set_input("b", "1")
        self.assertEqual(self.values()["q"], "0")
        self.simulator.set_input("clk", "1")
        self.assertEqual(self.values()["q"], "1")

    def test_async_reset_updates_without_clock_edge(self):
        self.assertEqual(self.values()["aq"], "0")
        self.simulator.set_input("arst", "1")
        self.assertEqual(self.values()["aq"], "1")

    def test_sync_reset_has_priority_over_disabled_enable(self):
        self.simulator.set_input("en", "0")
        self.simulator.set_input("srst", "1")
        self.simulator.set_input("clk", "1")
        self.assertEqual(self.values()["sq"], "5")

    def test_internal_signal_watch(self):
        self.simulator.add_watch("__fsm_1", "demo", "current_state")
        self.assertEqual(self.values()["__fsm_1"], "0")


if __name__ == "__main__":
    unittest.main()
