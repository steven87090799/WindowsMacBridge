import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("monitor", Path(__file__).parents[2] / "scripts/monitor-runtime.py")
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class ResourceMeasurements(unittest.TestCase):
    def test_cpu_time_supports_seconds_hours_and_days(self):
        self.assertEqual(monitor.cpu_seconds("0:03.25"), 3.25)
        self.assertEqual(monitor.cpu_seconds("2:03:04.50"), 7384.5)
        self.assertEqual(monitor.cpu_seconds("1-02:03:04.50"), 93784.5)

    def test_interval_cpu_uses_elapsed_cpu_not_ps_lifetime_average(self):
        self.assertEqual(monitor.interval_cpu((12, 0, 1), 12, 60, 1.06), 0.1)
        self.assertEqual(monitor.interval_cpu((12, 0, 1), 12, 60, 121), 200)

    def test_restart_never_combines_different_pids(self):
        self.assertEqual(monitor.interval_cpu((12, 0, 20), 13, 60, 0.1), "")
        self.assertEqual(monitor.interval_cpu(None, 13, 60, 0.1), "")

    def test_clock_and_counter_discontinuities_do_not_produce_false_spikes(self):
        self.assertEqual(monitor.interval_cpu((12, 60, 2), 12, 60, 3), "")
        self.assertEqual(monitor.interval_cpu((12, 60, 2), 12, 61, 1), "")


if __name__ == "__main__":
    unittest.main()
