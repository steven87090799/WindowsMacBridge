import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("build_sdk", ROOT / "scripts/verify-build-sdk.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def build_command(sdk="27.0", minos="14.0", platform="MACOS"):
    return f"Load command 11\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform {platform}\n    minos {minos}\n      sdk {sdk}\n   ntools 1\n"


class BuildSDKTests(unittest.TestCase):
    def test_current_and_compatibility_sdks_preserve_deployment_target(self):
        for sdk in ("27.0", "26.2"):
            self.assertEqual(MODULE.verify(build_command(sdk), sdk)["minos"], "14.0")
        MODULE.verify(build_command("27.0.0"), "27.0")

    def test_deployment_target_cannot_masquerade_as_linked_sdk(self):
        with self.assertRaises(ValueError):
            MODULE.verify(build_command("14.0"), "27.0")

    def test_wrong_platform_or_raised_minimum_is_rejected(self):
        for output in (build_command(platform="IOS"), build_command(minos="27.0")):
            with self.assertRaises(ValueError):
                MODULE.verify(output, "27.0")

    def test_missing_or_ambiguous_metadata_fails_closed(self):
        for output in ("", build_command() * 2, build_command().replace("sdk 27.0", "sdk unknown")):
            with self.assertRaises(ValueError):
                MODULE.verify(output, "27.0")


if __name__ == "__main__":
    unittest.main()
