import unittest

from select_ios_simulators import select


def device(name, udid, available=True):
    return {"name": name, "udid": udid, "isAvailable": available}


class SimulatorSelectionTests(unittest.TestCase):
    def test_duo_and_standard_use_their_own_installed_runtimes(self):
        duo, ordinary = select({
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo", "duo")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [device("iPhone 18 Pro", "standard")],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [device("iPhone 16", "older")],
        })
        self.assertEqual(duo[1]["udid"], "duo")
        self.assertEqual(ordinary[1]["udid"], "standard")

    def test_unavailable_or_old_duo_never_silently_falls_back(self):
        for runtime, available in [("27-1", False), ("27-0", True)]:
            with self.subTest(runtime=runtime, available=available), self.assertRaises(ValueError):
                devices = {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [device("iPhone 18 Pro", "ordinary")]}
                devices.setdefault(f"com.apple.CoreSimulator.SimRuntime.iOS-{runtime}", []).append(
                    device("iPhone Duo", "duo", available))
                select(devices)

    def test_standard_coverage_is_not_replaced_with_a_second_duo_run(self):
        with self.assertRaises(ValueError):
            select({"com.apple.CoreSimulator.SimRuntime.iOS-27-1": [device("iPhone Duo", "duo")]})


if __name__ == "__main__":
    unittest.main()
