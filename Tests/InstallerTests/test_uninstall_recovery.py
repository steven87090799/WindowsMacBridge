"""A pending update cannot be destroyed by uninstalling its recovery components."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class UninstallRecoveryTests(unittest.TestCase):
    def test_pending_journal_prevents_service_or_file_mutation(self):
        with tempfile.TemporaryDirectory(prefix='wmb-uninstall-') as directory:
            root = Path(directory)
            helper = root/'helper'; helper.mkdir()
            journal = helper/'.install-recovery'; journal.write_text('protected recovery')
            daemon = root/'helper.plist'; daemon.write_text('old-service')
            driver = root/'driver.plist'; driver.write_text('old-driver-service')
            marker = root/'mutation'
            launcher = root/'launchctl'; launcher.write_text('#!/bin/bash\ntouch "'+str(marker)+'"\n'); launcher.chmod(0o755)
            script = (ROOT/'Resources/Installer/UninstallBackend.sh').read_text()
            for original, replacement in [("\"$EUID\" -eq 0",'1 -eq 1'),
                ("'/Library/Application Support/WindowsMacBridge'",repr(str(helper))),
                ("'/Library/LaunchDaemons/local.WindowsMacBridge.HIDHelper.plist'",repr(str(daemon))),
                ("'/Library/LaunchDaemons/local.WindowsMacBridge.VirtualHIDService.plist'",repr(str(driver))),
                ('/bin/launchctl',str(launcher))]:
                script = script.replace(original,replacement)
            path = root/'uninstall.sh'; path.write_text(script)
            result = subprocess.run(['/bin/bash',str(path)],capture_output=True,text=True,timeout=5)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(marker.exists(),'Uninstall must not stop services before checking recovery.')
            self.assertEqual(journal.read_text(),'protected recovery')
            self.assertEqual(daemon.read_text(),'old-service')
            self.assertEqual(driver.read_text(),'old-driver-service')
