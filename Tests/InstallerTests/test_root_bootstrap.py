"""The administrator bootstrap runs only code sealed in a private copy of the signed App.
No sudo, osascript, launchd or /Applications is touched; codesign is a recording stub.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

def bootstrap(script):
    text = (ROOT/'Resources/Installer'/script).read_text()
    match = re.search(r"<<'BOOTSTRAP' \|\| true\n(.*?)\nBOOTSTRAP\n", text, re.S)
    assert match, 'bootstrap heredoc missing'
    return match.group(1)

class RootBootstrapTests(unittest.TestCase):
    def fixture(self, script, entry, codesign_status=0):
        temp = tempfile.TemporaryDirectory(prefix='wmb-bootstrap-')
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        app = root/'Applications/WindowsMacBridge.app'
        payload = app/'Contents/Resources/BackendPayload'
        (payload/'Driver').mkdir(parents=True)
        (payload/'Driver/driver.pkg').write_text('pkg')
        (payload/'AppProcess.sh').write_text('# sealed')
        record = root/'record'
        (payload/entry).write_text('#!/bin/bash\nprintf "%s\\n%s\\n" "$0" "${1:-}" > ' + str(record) + '\n'
                                   '[[ -z "${1:-}" ]] || { ls "$1" > ' + str(root/'listing') + '; cat "$1/PAYLOAD-SHA256SUMS" > ' + str(root/'manifest') + '; }\n')
        log = root/'codesign.log'
        stub = root/'codesign'
        stub.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> ' + str(log) + f'\nexit {codesign_status}\n'); stub.chmod(0o755)
        text = bootstrap(script).replace('/usr/bin/codesign', str(stub))
        boot = root/'boot'; boot.mkdir()
        self.assertIn('/private/var/tmp/WindowsMacBridge-boot.', text)
        text = text.replace('/private/var/tmp/WindowsMacBridge-boot.', str(boot/'WindowsMacBridge-boot.'))
        result = subprocess.run(['/bin/bash', '-c', text, 'test-bootstrap', str(app)],
                                capture_output=True, text=True, timeout=20, env=dict(os.environ))
        return root, app, boot, record, log, result

    def test_install_runs_the_sealed_copy_with_a_root_built_payload(self):
        root, app, boot, record, log, result = self.fixture('LaunchEmbeddedInstall.sh', 'InstallBackend.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        executed, payload = record.read_text().splitlines()
        # Never the user-writable source, always the private verified copy.
        self.assertTrue(executed.startswith(str(boot)), executed)
        self.assertFalse(executed.startswith(str(app)))
        self.assertTrue(payload.startswith(str(boot)))
        self.assertEqual(sorted((root/'listing').read_text().split()),
                         ['AppProcess.sh', 'Driver', 'InstallBackend.sh', 'PAYLOAD-SHA256SUMS', 'WindowsMacBridge.app'])
        self.assertIn('./Driver/driver.pkg', (root/'manifest').read_text())
        verified = log.read_text()
        self.assertIn('--verify --strict -R =identifier "local.WindowsMacBridge" ' + str(boot), verified)
        self.assertEqual(list(boot.iterdir()), [], 'private stage must be removed')

    def test_failed_signature_verification_runs_nothing(self):
        for script, entry in [('LaunchEmbeddedInstall.sh', 'InstallBackend.sh'),
                              ('LaunchEmbeddedUninstall.sh', 'UninstallBackend.sh')]:
            root, app, boot, record, log, result = self.fixture(script, entry, codesign_status=1)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(record.exists(), script)
            self.assertEqual(list(boot.iterdir()), [])

    def test_uninstall_runs_the_sealed_copy(self):
        root, app, boot, record, log, result = self.fixture('LaunchEmbeddedUninstall.sh', 'UninstallBackend.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        executed = record.read_text().splitlines()[0]
        self.assertTrue(executed.startswith(str(boot)) and not executed.startswith(str(app)), executed)

    def test_launchers_never_hand_root_a_user_script_path(self):
        for script in ['LaunchEmbeddedInstall.sh', 'LaunchEmbeddedUninstall.sh']:
            text = (ROOT/'Resources/Installer'/script).read_text()
            self.assertIn('"/bin/bash -c " & quoted form of item 1 of arguments', text)
            self.assertNotIn('TMPDIR', text)

if __name__ == '__main__':
    unittest.main()
