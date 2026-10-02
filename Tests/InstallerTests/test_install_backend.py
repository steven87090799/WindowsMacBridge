"""Exercise the production shell transaction with commands/destinations replaced in a private copy.
No sudo, launchd, driver, /Applications or user settings are touched.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DRIVER_SHA = 'ff8c7fdc5e25387c7805fc7509a0fa9cf98f69ba582704f717fddcae47424387'
ROLLBACK_SHA = '4ccd9b11628f4c319b17452927827a8313728fe60292e4f789ef4ba626e09ba0'

STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['WMB_TEST_ROOT'])
with (root/'commands.log').open('a') as f: f.write(json.dumps([name]+args)+'\n')
fail = os.environ.get('WMB_FAIL', '')
def copy(src, dst):
    src, dst = pathlib.Path(src), pathlib.Path(dst)
    fixture_root = root.resolve()  # macOS /var and /private/var refer to the same temporary directory.
    if dst.resolve() != fixture_root and fixture_root not in dst.resolve().parents:
        sys.exit(78)  # Regression failures must never write outside the fixture.
    if src.is_dir(): shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
if name == 'ditto':
    src, dst = args[-2:]
    if fail == 'staging' and 'next' in dst: sys.exit(31)
    if os.environ.get('WMB_APP_PROTECTED') == '1' and pathlib.Path(dst) == root/'Applications/WindowsMacBridge.app':
        sys.exit(77)  # App Management can reject writes into an installed bundle.
    copy(src, dst)
elif name in ['chown', 'chmod']:
    if os.environ.get('WMB_APP_PROTECTED') == '1' and pathlib.Path(args[-1]) == root/'Applications/WindowsMacBridge.app':
        sys.exit(77)
    if name == 'chmod': sys.exit(subprocess.call(['/bin/chmod']+args))
elif name == 'codesign':
    if '-R' in args and not args[args.index('-R')+1].startswith('='):
        sys.exit(65)  # Native codesign interprets a bare expression as a filename.
elif name == 'pkgutil':
    receipt_path = root/'receipt-state'
    state = receipt_path.read_text() if receipt_path.exists() else os.environ.get('WMB_RECEIPT', 'fresh')
    if args[0] == '--pkgs':
        if state == 'query_error': sys.exit(41)
        if state != 'fresh': print('org.pqrs.Karabiner-DriverKit-VirtualHIDDevice')
    elif args[0] == '--pkg-info':
        if state in ['fresh','info_error']: sys.exit(1)
        print('version: '+('9.0.0' if state == 'mismatch' else state if state.startswith(('7.','8.')) else '8.6.0'))
    elif args[0] == '--forget': receipt_path.write_text('fresh')
elif name == 'installer':
    version = '7.3.0' if '7.3.0.pkg' in args[args.index('-pkg')+1] else '8.6.0'
    driver = root/'Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'
    manager = root/'Applications/.Karabiner-VirtualHIDDevice-Manager.app'
    import plistlib
    for target, v in [(driver/'Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents',version),
                      (manager/'Contents',version),
                      (manager/'Contents/Library/SystemExtensions/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext','1.8.0')]:
        target.mkdir(parents=True,exist_ok=True)
        (target/'Info.plist').write_bytes(plistlib.dumps({'CFBundleVersion':v}))
    executable = manager/'Contents/MacOS/Karabiner-VirtualHIDDevice-Manager'
    executable.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(sys.argv[0],executable); executable.chmod(0o755)
    (driver/'identity').write_text('new-shared-driver' if version == '8.6.0' else 'original-shared-driver')
    (root/'receipt-state').write_text(version)
    (root/'driver-installed').write_text(version)
    if fail in ['deactivation_pending','deactivation_active'] and version == '8.6.0':
        # Explicitly simulate registration after package installation. Fresh
        # installs otherwise leave activation to the user's permission step.
        (root/'extension-state').write_text('1.8.0')
    if fail == 'driver' and version == '8.6.0': sys.exit(42)
    if fail == 'kill_during_driver' and version == '8.6.0':
        import signal, time
        os.kill(os.getppid(),signal.SIGKILL); time.sleep(0.05); sys.exit(44)
elif name == 'shasum':
    if args[-1].endswith('.pkg'):
        print(os.environ['WMB_ROLLBACK_SHA' if '7.3.0.pkg' in args[-1] else 'WMB_DRIVER_SHA']+'  '+args[-1])
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
        if (fail == 'bootstrap_'+label or (fail in ['deactivation_pending','deactivation_active'] and label == 'helper')) and not once.exists(): once.touch(); sys.exit(43)
        state[label] = True
        state_path.write_text(json.dumps(state))
elif name == 'pgrep':
    if (fail in ['foreign_daemon','foreign_client'] and args[-1] == 'Karabiner-VirtualHIDDevice-Daemon') or (fail in ['app_running','root_runtime'] and args[-1] == 'WindowsMacBridge'):
        print('4242'); sys.exit(0)
    sys.exit(1)
elif name == 'ps':
    print('0' if fail == 'root_runtime' else '501')
elif name == 'lsof':
    print('p4242\nf3\nf4' if fail == 'foreign_client' else 'p4242\nf3')
elif name == 'systemextensionsctl':
    path = root/'extension-state'
    version = path.read_text() if path.exists() else ('1.8.0' if os.environ.get('WMB_RECEIPT') == '7.3.0' else '')
    if fail == 'orphan_extension': version = '1.8.0'
    if version: print('*\t*\tG43BCU2T37\torg.pqrs.Karabiner-DriverKit-VirtualHIDDevice\t('+version+'/'+version+')\tname\t'+('[terminated waiting for uninstall on reboot]' if version == 'pending' else '[activated enabled]'))
elif name == 'Karabiner-VirtualHIDDevice-Manager':
    import plistlib
    manager = pathlib.Path(sys.argv[0]).parents[2]
    package_version = plistlib.loads((manager/'Contents/Info.plist').read_bytes())['CFBundleVersion']
    v = plistlib.loads((manager/'Contents/Library/SystemExtensions/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext/Info.plist').read_bytes())['CFBundleVersion']
    if args[0] == 'deactivate':
        (root/'extension-state').write_text('pending' if fail == 'deactivation_pending' else v if fail == 'deactivation_active' else ''); sys.exit(0)
    if fail == 'activation' and package_version == '8.6.0': sys.exit(45)
    if fail == 'reboot' and package_version == '8.6.0': print('requires reboot'); sys.exit(0)
    if fail == 'rollback_activation' and package_version == '7.3.0': sys.exit(46)
    (root/'extension-state').write_text(v)
elif name == 'DriverProcessRunner':
    result = subprocess.run(args[:2],capture_output=True,text=True)
    pathlib.Path(args[2]).write_text(result.stdout+result.stderr)
    sys.exit(result.returncode)
elif name == 'stat':
    if args[-2] == '%u': print('0')
    elif args[-2] == '%Lp': print(oct(pathlib.Path(args[-1]).stat().st_mode & 0o777)[2:])
elif name == 'install': copy(args[-2],args[-1])
'''

class InstallBackendTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin', 'Native macOS requirement parser')
    def test_shared_driver_requirements_compile_with_native_parser(self):
        lines = [shlex.split(row) for row in (ROOT/'Resources/Installer/InstallBackend.sh').read_text().splitlines()
                 if '/usr/bin/codesign --verify --strict -R ' in row]
        self.assertEqual(len(lines), 3)
        with tempfile.TemporaryDirectory(prefix='wmb-requirement-') as directory:
            for index, args in enumerate(lines):
                expression = args[args.index('-R')+1]
                result = subprocess.run(['/usr/bin/csreq', '-r', expression, '-b', str(Path(directory)/str(index))],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def run_install(self, receipt='installed', fail='', existing=True, installed_driver_version='1.8.0', active_driver=True, driver_running=None, private_app_resource=False, protected_app=False, unified_runtime=False):
        temp = tempfile.TemporaryDirectory(prefix='wmb-install-test-')
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        payload = root/'payload'; payload.mkdir()
        app = root/'Applications/WindowsMacBridge.app'
        app.parent.mkdir(parents=True)
        helper_root = root/'Library/Application Support/WindowsMacBridge'
        daemons = root/'Library/LaunchDaemons'; daemons.mkdir(parents=True)
        driver_root = root/'Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'
        manager = root/'Applications/.Karabiner-VirtualHIDDevice-Manager.app'
        daemon = driver_root/'Applications/Karabiner-VirtualHIDDevice-Daemon.app'
        extension = manager/'Contents/Library/SystemExtensions/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext'
        for target, identifier, version in [
            (daemon, 'org.pqrs.Karabiner-VirtualHIDDevice-Daemon', receipt if receipt.startswith(('7.','8.')) else '8.6.0'),
            (extension, 'org.pqrs.Karabiner-DriverKit-VirtualHIDDevice', installed_driver_version)]:
            contents = target if target == extension else target/'Contents'
            contents.mkdir(parents=True)
            (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,
                'CFBundleVersion':version,'CFBundleShortVersionString':version}))
        (driver_root/'identity').write_text('original-shared-driver')
        (manager/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleVersion':receipt if receipt.startswith(('7.','8.')) else '8.6.0'}))
        manager_executable = manager/'Contents/MacOS/Karabiner-VirtualHIDDevice-Manager'
        manager_executable.parent.mkdir(parents=True,exist_ok=True)
        manager_executable.write_text(STUB); manager_executable.chmod(0o755)
        if receipt == 'fresh':
            shutil.rmtree(driver_root); shutil.rmtree(manager)
        (root/'extension-state').write_text('1.8.0' if receipt != 'fresh' and active_driver else '')
        for target, value in [(payload/'WindowsMacBridge.app', 'new-app')]:
            (target/'Contents/MacOS').mkdir(parents=True)
            identifier = 'local.WindowsMacBridge'+('.HIDHelper' if 'Helper' in target.name else '')
            (target/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,
                'CFBundleShortVersionString':'0.5.13','CFBundleVersion':'25'}))
            (target/'identity').write_text(value)
        executable = payload/'WindowsMacBridge.app/Contents/MacOS/WindowsMacBridge'
        executable.write_text('#!/bin/bash\nprintf "new-pin\\n"\n'); executable.chmod(0o755)
        if private_app_resource:
            folder = payload/'WindowsMacBridge.app/Contents/Resources/BackendPayload/Driver'
            folder.mkdir(parents=True)
            package = folder/'rollback.pkg'; package.write_bytes(b'public-software'); package.chmod(0o600)
            folder.chmod(0o700)
        (payload/'Licenses').mkdir(); (payload/'Licenses/license').write_text('notice')
        (payload/'Driver').mkdir(); (payload/'Driver/Karabiner-DriverKit-VirtualHIDDevice-8.6.0.pkg').write_bytes(b'pkg')
        (payload/'Driver/Karabiner-DriverKit-VirtualHIDDevice-7.3.0.pkg').write_bytes(b'rollback')
        shutil.copy2(ROOT/'Resources/Installer/AppProcess.sh', payload/'AppProcess.sh')
        transaction = ROOT/'Resources/Installer/DriverTransaction.sh'
        if transaction.exists(): shutil.copy2(transaction,payload/'DriverTransaction.sh')
        runner = payload/'DriverProcessRunner'; runner.write_text(STUB); runner.chmod(0o755)
        for label in ['HIDHelper','VirtualHIDService']:
            (payload/f'local.WindowsMacBridge.{label}.plist').write_text('new-'+label)
        if existing:
            shutil.copytree(payload/'WindowsMacBridge.app', app)
            (app/'identity').write_text('old-app')
            helper_root.mkdir(parents=True)
            if unified_runtime:
                shutil.copytree(app, helper_root/'WindowsMacBridge.app')
                (helper_root/'WindowsMacBridge.app/identity').write_text('old-runtime')
            else:
                shutil.copytree(payload/'WindowsMacBridge.app', helper_root/'BridgeHIDHelper.app')
                (helper_root/'BridgeHIDHelper.app/Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.WindowsMacBridge.HIDHelper'}))
                (helper_root/'BridgeHIDHelper.app/identity').write_text('old-helper')
            (helper_root/'controller.plist').write_text('old-pin')
            (helper_root/'unrelated.txt').write_text('preserve')
            for label in ['HIDHelper','VirtualHIDService']:
                (daemons/f'local.WindowsMacBridge.{label}.plist').write_text('old-'+label)
        (root/'services.json').write_text(json.dumps({'helper':existing,'driver':existing if driver_running is None else driver_running}))
        manifest = ''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(payload))+'\n'
                           for p in sorted(payload.rglob('*')) if p.is_file())
        (payload/'PAYLOAD-SHA256SUMS').write_text(manifest)
        tools = root/'tools'; tools.mkdir()
        text = (ROOT/'Resources/Installer/InstallBackend.sh').read_text()
        # Authentication is only removed from this test copy; every privileged command is a stub.
        text = text.replace('"$EUID" -eq 0', '1 -eq 1')
        text = text.replace("'/Library/Application Support/WindowsMacBridge'", repr(str(helper_root)))
        text = text.replace("'/Applications/WindowsMacBridge.app'", repr(str(app)))
        text = text.replace("'/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'", repr(str(driver_root)))
        text = text.replace("'/Applications/.Karabiner-VirtualHIDDevice-Manager.app'", repr(str(manager)))
        for label in ['HIDHelper','VirtualHIDService']:
            text = text.replace(f"'/Library/LaunchDaemons/local.WindowsMacBridge.{label}.plist'",
                                repr(str(daemons/f'local.WindowsMacBridge.{label}.plist')))
        # mktemp and filesystem commands operate exclusively under the above private test destinations.
        text = text.replace('/private/var/tmp/WindowsMacBridge-install.', str(root/'WindowsMacBridge-install.'))
        for command in ['/usr/bin/ditto','/usr/sbin/chown','/bin/chmod','/usr/bin/codesign','/usr/sbin/pkgutil',
                        '/usr/sbin/installer','/usr/bin/shasum','/bin/launchctl','/usr/bin/pgrep','/bin/ps',
                        '/usr/bin/stat','/usr/bin/install']:
            stub = tools/Path(command).name; stub.write_text(STUB); stub.chmod(0o755)
            text = text.replace(command, str(stub))
        roles = (payload/'AppProcess.sh').read_text().replace('/usr/bin/pgrep',str(tools/'pgrep')).replace('/bin/ps',str(tools/'ps'))
        (payload/'AppProcess.sh').write_text(roles)
        manifest = ''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(payload))+'\n'
                           for p in sorted(payload.rglob('*')) if p.is_file() and p.name != 'PAYLOAD-SHA256SUMS')
        (payload/'PAYLOAD-SHA256SUMS').write_text(manifest)
        script = root/'InstallBackend.sh'; script.write_text(text)
        if transaction.exists():
            transaction_text = transaction.read_text()
            for command in ['/usr/bin/ditto','/usr/sbin/chown','/usr/bin/codesign','/usr/sbin/pkgutil',
                            '/usr/sbin/installer','/usr/bin/shasum','/bin/launchctl','/usr/bin/pgrep','/bin/ps',
                            '/usr/bin/stat','/usr/bin/install','/usr/sbin/lsof','/usr/bin/systemextensionsctl']:
                stub = tools/Path(command).name; stub.write_text(STUB); stub.chmod(0o755)
                transaction_text = transaction_text.replace(command,str(stub))
            (payload/'DriverTransaction.sh').write_text(transaction_text)
            manifest = ''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(payload))+'\n'
                               for p in sorted(payload.rglob('*')) if p.is_file() and p.name != 'PAYLOAD-SHA256SUMS')
            (payload/'PAYLOAD-SHA256SUMS').write_text(manifest)
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_ROLLBACK_SHA=ROLLBACK_SHA, WMB_RECEIPT=receipt, WMB_FAIL=fail,
                   WMB_APP_PROTECTED='1' if protected_app else '0')
        result = subprocess.run(['/bin/bash',str(script),str(payload)], env=env, capture_output=True, text=True, timeout=20)
        return root, app, helper_root, daemons, result

    def assert_original(self, app, helper, daemons):
        self.assertEqual((app/'identity').read_text(),'old-app')
        self.assertEqual((helper/'BridgeHIDHelper.app/identity').read_text(),'old-helper')
        self.assertEqual((helper/'controller.plist').read_text(),'old-pin')
        self.assertEqual((helper/'unrelated.txt').read_text(),'preserve')
        self.assertFalse((helper/'WindowsMacBridge.app').exists())
        self.assertEqual((daemons/'local.WindowsMacBridge.HIDHelper.plist').read_text(),'old-HIDHelper')

    def test_fresh_driver_install_reaches_installation(self):
        root, app, helper, _, result = self.run_install(receipt='fresh', existing=False)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue((root/'driver-installed').exists())
        self.assertEqual((app/'identity').read_text(),'new-app')
        self.assertEqual((root/'extension-state').read_text(), '')

    def test_one_app_payload_migrates_legacy_helper_to_the_same_app_identity(self):
        _, app, support, _, result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((support/'BridgeHIDHelper.app').exists())
        runtime = support/'WindowsMacBridge.app'
        self.assertEqual((runtime/'identity').read_text(), 'new-app')
        self.assertEqual(plistlib.loads((runtime/'Contents/Info.plist').read_bytes()),
                         plistlib.loads((app/'Contents/Info.plist').read_bytes()))
        self.assertFalse((app/'Contents/Resources/BridgeHIDHelper.app').exists())

    def test_failed_unified_update_restores_main_app_and_root_runtime_separately(self):
        _, app, support, _, result = self.run_install(fail='bootstrap_helper', unified_runtime=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((app/'identity').read_text(), 'old-app')
        self.assertEqual((support/'WindowsMacBridge.app/identity').read_text(), 'old-runtime')
        self.assertEqual((support/'controller.plist').read_text(), 'old-pin')
        self.assertFalse((support/'BridgeHIDHelper.app').exists())
        self.assertFalse((support/'.install-recovery').exists())

    def test_root_runtime_does_not_block_app_update(self):
        _, app, support, _, result = self.run_install(fail='root_runtime')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((app/'identity').read_text(), 'new-app')
        self.assertEqual((support/'WindowsMacBridge.app/identity').read_text(), 'new-app')

    def test_already_installed_driver_is_not_reinstalled(self):
        root, _, _, _, result = self.run_install()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((root/'driver-installed').exists())

    def test_private_source_modes_do_not_make_installed_app_resources_root_only(self):
        _, app, helper_root, _, result = self.run_install(private_app_resource=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        folder = app/'Contents/Resources/BackendPayload/Driver'
        for path, mask in [(folder, 0o005), (folder/'rollback.pkg', 0o004),
                           (helper_root/'WindowsMacBridge.app/Contents/Info.plist', 0o004)]:
            self.assertEqual(path.stat().st_mode & mask, mask)
            self.assertEqual(path.stat().st_mode & 0o022, 0)

    def test_app_management_protection_does_not_interrupt_installation_or_atomic_rollback(self):
        for failure in ['', 'bootstrap_helper']:
            root, app, helper, daemons, result = self.run_install(
                fail=failure, private_app_resource=True, protected_app=True)
            self.assertEqual(result.returncode == 0, not failure, result.stderr)
            if failure:
                self.assert_original(app, helper, daemons)
                self.assertEqual(json.loads((root/'services.json').read_text()), {'helper':True,'driver':True})
            else:
                self.assertEqual((app/'identity').read_text(), 'new-app')
                self.assertEqual((app/'Contents/Resources/BackendPayload/Driver/rollback.pkg').stat().st_mode & 0o004, 0o004)
            self.assertFalse((helper/'.install-recovery').exists())

    def test_incomplete_destination_bundle_does_not_block_trusted_interrupted_recovery(self):
        root, app, helper, daemons, result = self.run_install(fail='kill_before_bootstrap')
        self.assertEqual(result.returncode, -9)
        (app/'Contents/Info.plist').unlink()
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_RECEIPT='query_error', WMB_FAIL='', WMB_APP_PROTECTED='1')
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode, 0)
        self.assert_original(app, helper, daemons)
        self.assertFalse((helper/'.install-recovery').exists())

    def test_failed_rollback_staging_preserves_snapshot_without_publishing_partial_app(self):
        root, app, helper, _, result = self.run_install(fail='kill_before_bootstrap')
        self.assertEqual(result.returncode, -9)
        snapshot = Path((helper/'.install-recovery').read_text().splitlines()[1])
        shutil.rmtree(snapshot/'retired-application.app')  # Exercise legacy backup reconstruction.
        script = root/'InstallBackend.sh'
        original = script.read_text()
        allocation = '/usr/bin/mktemp -d "$bridge_stage/restore.XXXXXX"'
        self.assertIn(allocation, original)
        script.write_text(original.replace(allocation, '/usr/bin/false'))
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_RECEIPT='query_error', WMB_FAIL='', WMB_APP_PROTECTED='1')
        retry = subprocess.run(['/bin/bash',str(script),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode, 0)
        self.assertEqual((app/'identity').read_text(), 'new-app')
        self.assertEqual((snapshot/'previous/WindowsMacBridge.app/identity').read_text(), 'old-app')
        self.assertTrue((helper/'.install-recovery').exists())
        commands = [json.loads(row) for row in (root/'commands.log').read_text().splitlines()]
        self.assertFalse(any(row[0] == 'ditto' and row[-1] == '/WindowsMacBridge.app' for row in commands))

    def test_compatible_shared_daemon_is_not_restarted_on_success_or_rollback(self):
        for failure in ['', 'bootstrap_helper']:
            root, _, _, _, result = self.run_install(receipt='8.5.0',fail=failure)
            self.assertEqual(result.returncode == 0, not failure, result.stderr)
            commands = [json.loads(row) for row in (root/'commands.log').read_text().splitlines()]
            mutations = [row for row in commands if row[0] == 'launchctl' and row[1] in ['bootout','bootstrap']
                         and 'VirtualHIDService' in row[-1]]
            self.assertEqual(mutations, [], 'Do not disconnect other clients of the compatible shared daemon.')

    def test_fresh_receipt_with_existing_registration_or_daemon_is_not_overwritten(self):
        for failure in ['orphan_extension','foreign_daemon']:
            root, _, _, _, result = self.run_install(receipt='fresh',existing=False,fail=failure)
            self.assertNotEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root/'driver-installed').exists())

    def test_verified_compatible_shared_packages_are_reused_without_reinstallation(self):
        for receipt in ['8.0.0','8.1.0','8.2.0','8.3.0','8.4.0','8.5.0']:
            root, _, _, _, result = self.run_install(receipt=receipt)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((root/'driver-installed').exists())
            shared = root/'Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/identity'
            self.assertEqual(shared.read_text(),'original-shared-driver')

    def test_compatible_receipt_does_not_authorize_wrong_driver_binary(self):
        root, app, helper, daemons, result = self.run_install(receipt='8.6.0', installed_driver_version='1.7.0')
        self.assertNotEqual(result.returncode,0)
        self.assert_original(app,helper,daemons)
        self.assertFalse((root/'driver-installed').exists())

    def test_compatible_shared_driver_survives_owned_service_rollback(self):
        root, app, helper, daemons, result = self.run_install(receipt='8.5.0',fail='bootstrap_helper')
        self.assertNotEqual(result.returncode,0)
        self.assert_original(app,helper,daemons)
        self.assertEqual(json.loads((root/'services.json').read_text()),{'helper':True,'driver':True})
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
        self.assertFalse((root/'Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice').exists())
        self.assertFalse((root/'Applications/.Karabiner-VirtualHIDDevice-Manager.app').exists())
        self.assertEqual((root/'receipt-state').read_text(),'fresh')

    def test_known_old_abi_upgrades_only_after_snapshot_and_verification(self):
        root, app, _, _, result = self.run_install(receipt='7.3.0')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual((root/'receipt-state').read_text(),'8.6.0')
        self.assertEqual((root/'extension-state').read_text(),'1.8.0')
        self.assertEqual((app/'identity').read_text(),'new-app')

    def test_old_shared_driver_files_receipt_activation_and_services_roll_back(self):
        for failure in ['driver','activation','reboot','bootstrap_helper']:
            active = failure not in ['activation','reboot']
            root, app, helper, daemons, result = self.run_install(receipt='7.3.0',fail=failure,active_driver=active)
            self.assertNotEqual(result.returncode,0,failure)
            self.assert_original(app,helper,daemons)
            self.assertEqual((root/'receipt-state').read_text(),'7.3.0')
            self.assertEqual((root/'Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/identity').read_text(),'original-shared-driver')
            self.assertEqual((root/'extension-state').read_text(),'1.8.0' if active else '')
            self.assertEqual(json.loads((root/'services.json').read_text()),{'helper':True,'driver':True})

    def test_deactivation_success_exit_does_not_discard_pending_recovery(self):
        for failure in ['deactivation_pending', 'deactivation_active']:
            root, _, helper, _, result = self.run_install(receipt='fresh', fail=failure)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((helper/'.install-recovery').exists(), failure)
            self.assertTrue((root/'Applications/.Karabiner-VirtualHIDDevice-Manager.app').exists())
            self.assertEqual((root/'receipt-state').read_text(), '8.6.0')
            self.assertEqual(json.loads((root/'services.json').read_text()), {'helper':False, 'driver':False})

    def test_driver_install_kill_is_recovered_from_durable_snapshot(self):
        root, app, helper, _, result = self.run_install(receipt='7.3.0',fail='kill_during_driver')
        self.assertEqual(result.returncode,-9)
        env = dict(os.environ,WMB_TEST_ROOT=str(root),WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_ROLLBACK_SHA=ROLLBACK_SHA,WMB_RECEIPT='7.3.0',WMB_FAIL='staging')
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode,0)
        self.assertEqual((root/'receipt-state').read_text(),'7.3.0')
        self.assertEqual((app/'identity').read_text(),'old-app')
        self.assertFalse((helper/'.install-recovery').exists())

    def test_corrupt_driver_phase_retains_the_protected_recovery_snapshot(self):
        root, _, helper, _, result = self.run_install(receipt='7.3.0',fail='kill_during_driver')
        self.assertEqual(result.returncode,-9)
        saved = Path((helper/'.install-recovery').read_text().splitlines()[1])
        (saved/'driver.phase').write_text('invalid')
        env = dict(os.environ,WMB_TEST_ROOT=str(root),WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_ROLLBACK_SHA=ROLLBACK_SHA,WMB_RECEIPT='7.3.0',WMB_FAIL='')
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode,0)
        self.assertTrue((saved/'previous/SharedDriver').is_dir())
        self.assertTrue((helper/'.install-recovery').exists())

    def test_running_app_and_foreign_clients_prevent_shared_mutation(self):
        for failure in ['app_running','foreign_client']:
            root, app, helper, daemons, result = self.run_install(receipt='7.3.0',fail=failure)
            self.assertNotEqual(result.returncode,0)
            self.assert_original(app,helper,daemons)
            self.assertFalse((root/'driver-installed').exists())

    def test_failed_activation_recovery_retains_journal_until_rollback_succeeds(self):
        root, _, helper, _, result = self.run_install(receipt='7.3.0',fail='kill_during_driver')
        self.assertEqual(result.returncode,-9)
        env = dict(os.environ,WMB_TEST_ROOT=str(root),WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_ROLLBACK_SHA=ROLLBACK_SHA,WMB_RECEIPT='7.3.0',WMB_FAIL='rollback_activation')
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode,0)
        self.assertTrue((helper/'.install-recovery').exists())
        self.assertEqual(json.loads((root/'services.json').read_text()),{'helper':False,'driver':False},
                         'Do not restart services against an incompletely restored Driver.')
        env['WMB_FAIL']='staging'
        retry = subprocess.run(['/bin/bash',str(root/'InstallBackend.sh'),str(root/'payload')],
                               env=env,capture_output=True,text=True,timeout=20)
        self.assertNotEqual(retry.returncode,0)
        self.assertFalse((helper/'.install-recovery').exists())

    def test_staging_and_service_failures_roll_back_app_helper_pin_and_services(self):
        for failure in ['staging','bootstrap_helper','bootstrap_driver']:
            # A compatible running daemon is deliberately not restarted. Exercise
            # bootstrap failure when this owned service was initially stopped.
            driver_running = failure != 'bootstrap_driver'
            root, app, helper, daemons, result = self.run_install(fail=failure,driver_running=driver_running)
            self.assertNotEqual(result.returncode,0,failure)
            self.assert_original(app,helper,daemons)
            self.assertEqual(json.loads((root/'services.json').read_text()),{'helper':True,'driver':driver_running},failure)

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
