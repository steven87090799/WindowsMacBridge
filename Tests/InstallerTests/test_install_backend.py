"""Exercise the production shell transaction with commands/destinations replaced in a private copy.
No sudo, launchd, driver, /Applications or user settings are touched.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIVER_SHA = 'ff8c7fdc5e25387c7805fc7509a0fa9cf98f69ba582704f717fddcae47424387'

STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['WMB_TEST_ROOT'])
with (root/'commands.log').open('a') as f: f.write(json.dumps([name]+args)+'\n')
fail = os.environ.get('WMB_FAIL', '')
def copy(src, dst):
    src, dst = pathlib.Path(src), pathlib.Path(dst)
    if src.is_dir(): shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
if name == 'ditto':
    src, dst = args[-2:]
    if fail == 'staging' and 'next' in dst: sys.exit(31)
    copy(src, dst)
elif name == 'chown': pass
elif name == 'codesign': pass
elif name == 'pkgutil':
    state = os.environ.get('WMB_RECEIPT', 'fresh')
    if args[0] == '--pkgs':
        if state == 'query_error': sys.exit(41)
        if state != 'fresh': print('org.pqrs.Karabiner-DriverKit-VirtualHIDDevice')
    elif args[0] == '--pkg-info':
        if state in ['fresh','info_error']: sys.exit(1)
        print('version: '+('9.0.0' if state == 'mismatch' else '8.6.0'))
elif name == 'installer':
    if fail == 'driver': sys.exit(42)
    (root/'driver-installed').write_text('8.6.0')
elif name == 'shasum':
    if args[-1].endswith('.pkg'): print(os.environ['WMB_DRIVER_SHA']+'  '+args[-1])
    else: sys.exit(subprocess.call(['/usr/bin/shasum']+args))
elif name == 'launchctl':
    state_path = root/'services.json'
    state = json.loads(state_path.read_text())
    label = 'helper' if 'HIDHelper' in args[-1] else 'driver'
    if args[0] == 'print': sys.exit(0 if state[label] else 1)
    if args[0] == 'bootout':
        was = state[label]; state[label] = False
        state_path.write_text(json.dumps(state)); sys.exit(0 if was else 113)
    if args[0] == 'bootstrap':
        if fail == 'kill_before_bootstrap':
            import signal, time
            os.kill(os.getppid(), signal.SIGKILL); time.sleep(0.05); sys.exit(44)
        once = root/'failed-once'
        if fail == 'bootstrap_'+label and not once.exists(): once.touch(); sys.exit(43)
        state[label] = True
        state_path.write_text(json.dumps(state))
elif name == 'pgrep': sys.exit(1)
elif name == 'stat':
    if args[-2] == '%u': print('0')
    elif args[-2] == '%Lp': print(oct(pathlib.Path(args[-1]).stat().st_mode & 0o777)[2:])
elif name == 'install': copy(args[-2],args[-1])
'''

class InstallBackendTests(unittest.TestCase):
    def run_install(self, receipt='installed', fail='', existing=True):
        temp = tempfile.TemporaryDirectory(prefix='wmb-install-test-')
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        payload = root/'payload'; payload.mkdir()
        app = root/'Applications/WindowsMacBridge.app'
        app.parent.mkdir(parents=True)
        helper_root = root/'Library/Application Support/WindowsMacBridge'
        daemons = root/'Library/LaunchDaemons'; daemons.mkdir(parents=True)
        for target, value in [(payload/'WindowsMacBridge.app', 'new-app'),
                              (payload/'BridgeHIDHelper.app','new-helper')]:
            (target/'Contents/MacOS').mkdir(parents=True)
            identifier = 'local.WindowsMacBridge'+('.HIDHelper' if 'Helper' in target.name else '')
            (target/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,
                'CFBundleShortVersionString':'0.5.13','CFBundleVersion':'25'}))
            (target/'identity').write_text(value)
        executable = payload/'BridgeHIDHelper.app/Contents/MacOS/BridgeHIDHelper'
        executable.write_text('#!/bin/bash\nprintf "new-pin\\n"\n'); executable.chmod(0o755)
        (payload/'Licenses').mkdir(); (payload/'Licenses/license').write_text('notice')
        (payload/'Driver').mkdir(); (payload/'Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg').write_bytes(b'pkg')
        for label in ['HIDHelper','VirtualHIDService']:
            (payload/f'local.WindowsMacBridge.{label}.plist').write_text('new-'+label)
        if existing:
            shutil.copytree(payload/'WindowsMacBridge.app', app)
            (app/'identity').write_text('old-app')
            helper_root.mkdir(parents=True)
            shutil.copytree(payload/'BridgeHIDHelper.app', helper_root/'BridgeHIDHelper.app')
            (helper_root/'BridgeHIDHelper.app/identity').write_text('old-helper')
            (helper_root/'controller.plist').write_text('old-pin')
            (helper_root/'unrelated.txt').write_text('preserve')
            for label in ['HIDHelper','VirtualHIDService']:
                (daemons/f'local.WindowsMacBridge.{label}.plist').write_text('old-'+label)
        (root/'services.json').write_text(json.dumps({'helper':existing,'driver':existing}))
        manifest = ''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(payload))+'\n'
                           for p in sorted(payload.rglob('*')) if p.is_file())
        (payload/'PAYLOAD-SHA256SUMS').write_text(manifest)
        tools = root/'tools'; tools.mkdir()
        text = (ROOT/'Resources/Installer/InstallBackend.sh').read_text()
        # Authentication is only removed from this test copy; every privileged command is a stub.
        text = text.replace('"$EUID" -eq 0', '1 -eq 1')
        text = text.replace("'/Library/Application Support/WindowsMacBridge'", repr(str(helper_root)))
        text = text.replace("'/Applications/WindowsMacBridge.app'", repr(str(app)))
        for label in ['HIDHelper','VirtualHIDService']:
            text = text.replace(f"'/Library/LaunchDaemons/local.WindowsMacBridge.{label}.plist'",
                                repr(str(daemons/f'local.WindowsMacBridge.{label}.plist')))
        # mktemp and filesystem commands operate exclusively under the above private test destinations.
        text = text.replace('/private/var/tmp/WindowsMacBridge-install.', str(root/'WindowsMacBridge-install.'))
        for command in ['/usr/bin/ditto','/usr/sbin/chown','/usr/bin/codesign','/usr/sbin/pkgutil',
                        '/usr/sbin/installer','/usr/bin/shasum','/bin/launchctl','/usr/bin/pgrep',
                        '/usr/bin/stat','/usr/bin/install']:
            stub = tools/Path(command).name; stub.write_text(STUB); stub.chmod(0o755)
            text = text.replace(command, str(stub))
        script = root/'InstallBackend.sh'; script.write_text(text)
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_RECEIPT=receipt, WMB_FAIL=fail)
        result = subprocess.run(['/bin/bash',str(script),str(payload)], env=env, capture_output=True, text=True, timeout=20)
        return root, app, helper_root, daemons, result

    def assert_original(self, app, helper, daemons):
        self.assertEqual((app/'identity').read_text(),'old-app')
        self.assertEqual((helper/'BridgeHIDHelper.app/identity').read_text(),'old-helper')
        self.assertEqual((helper/'controller.plist').read_text(),'old-pin')
        self.assertEqual((helper/'unrelated.txt').read_text(),'preserve')
        self.assertEqual((daemons/'local.WindowsMacBridge.HIDHelper.plist').read_text(),'old-HIDHelper')

    def test_fresh_driver_install_reaches_installation(self):
        root, app, helper, _, result = self.run_install(receipt='fresh', existing=False)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue((root/'driver-installed').exists())
        self.assertEqual((app/'identity').read_text(),'new-app')

    def test_already_installed_driver_is_not_reinstalled(self):
        root, _, _, _, result = self.run_install()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((root/'driver-installed').exists())

    def test_receipt_query_errors_and_shared_version_mismatch_are_errors(self):
        for receipt in ['query_error','info_error','mismatch']:
            _, app, helper, daemons, result = self.run_install(receipt=receipt)
            self.assertNotEqual(result.returncode,0)
            self.assert_original(app,helper,daemons)

    def test_failed_driver_install_preserves_existing_app_and_services(self):
        root, app, helper, daemons, result = self.run_install(receipt='fresh',fail='driver')
        self.assertNotEqual(result.returncode,0)
        self.assert_original(app,helper,daemons)
        self.assertEqual(json.loads((root/'services.json').read_text()),{'helper':True,'driver':True})

    def test_staging_and_service_failures_roll_back_app_helper_pin_and_services(self):
        for failure in ['staging','bootstrap_helper','bootstrap_driver']:
            root, app, helper, daemons, result = self.run_install(fail=failure)
            self.assertNotEqual(result.returncode,0,failure)
            self.assert_original(app,helper,daemons)
            self.assertEqual(json.loads((root/'services.json').read_text()),{'helper':True,'driver':True},failure)

    def test_killed_update_is_recovered_before_the_next_attempt(self):
        root, app, helper, daemons, result = self.run_install(fail='kill_before_bootstrap')
        self.assertEqual(result.returncode, -9)
        self.assertTrue((helper/'.install-recovery').is_file())
        self.assertEqual((app/'identity').read_text(), 'new-app')
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_RECEIPT='query_error', WMB_FAIL='')
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode, 0)
        self.assert_original(app, helper, daemons)
        self.assertEqual(json.loads((root/'services.json').read_text()),{'helper':True,'driver':True})
        self.assertFalse((helper/'.install-recovery').exists())

    def test_live_transaction_owner_prevents_a_second_installer_from_switching(self):
        root, app, helper, _, result = self.run_install(fail='kill_before_bootstrap')
        self.assertEqual(result.returncode, -9)
        marker = helper/'.install-recovery'
        rows = marker.read_text().splitlines(); rows[2] = str(os.getpid())
        marker.write_text('\n'.join(rows)+'\n')
        env = dict(os.environ,WMB_TEST_ROOT=str(root),WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_RECEIPT='installed',WMB_FAIL='')
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode,0)
        self.assertIn('Another installer',retry.stderr)
        self.assertTrue(marker.exists())
        self.assertEqual((app/'identity').read_text(),'new-app')

    def test_symlink_recovery_record_is_rejected_without_switching(self):
        root, app, helper, _, result = self.run_install(fail='kill_before_bootstrap')
        self.assertEqual(result.returncode,-9)
        marker = helper/'.install-recovery'; saved = helper/'saved-record'
        marker.rename(saved); marker.symlink_to(saved)
        env = dict(os.environ,WMB_TEST_ROOT=str(root),WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_RECEIPT='installed',WMB_FAIL='')
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode,0)
        self.assertTrue(marker.is_symlink())
        self.assertEqual((app/'identity').read_text(),'new-app')

if __name__ == '__main__': unittest.main()
