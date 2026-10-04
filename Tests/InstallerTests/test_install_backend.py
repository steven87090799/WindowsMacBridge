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
    if fail == 'snapshot_replaced' and args[-1].endswith('/previous/WindowsMacBridge.app'):
        target = root/'Applications/WindowsMacBridge.app'
        if not (root/'snapshot-race-done').exists():
            (root/'snapshot-race-done').touch()
            os.rename(target, root/'displaced-during-snapshot.app')
            target.mkdir(); (target/'foreign').write_text('foreign-must-survive')
    reject = os.environ.get('WMB_CODESIGN_REJECT', '')
    if reject and any(reject in arg for arg in args):
        sys.exit(1)  # e.g. Finder tag detritus on a moved bundle fails --strict.
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
    elif args[-2] == '%d': print(os.stat(args[-1]).st_dev)
    elif args[-2] == '%d:%i':
        st = os.lstat(args[-1]); print(f'{st.st_dev}:{st.st_ino}')
        # Swap after returning the identity, in the gap before the shell's move.
        target = root/'Applications/WindowsMacBridge.app'
        race = os.environ.get('WMB_RETIRE_RACE', '')
        phase = ((root/'failed-once').exists() if race == 'rollback' else
                 any(root.glob('WindowsMacBridge-install.*/original.identity')) and
                 not any(root.glob('WindowsMacBridge-install.*/published.identity')))
        if race in ('rollback', 'upgrade') and pathlib.Path(args[-1]) == target and phase:
            counter = root/'retire-race-count'
            n = int(counter.read_text()) + 1 if counter.exists() else 1
            counter.write_text(str(n))
            if n == (3 if race == 'upgrade' else 2):
                os.rename(target, root/'displaced-before-retirement.app')
                target.mkdir(); (target/'foreign').write_text('foreign-must-survive')
elif name == 'install': copy(args[-2],args[-1])
'''

# Fixture App binary: --controller-pin and the real exclusive rename
# (renamex_np RENAME_EXCL), with a one-shot race injected at the publish point.
APP_STUB = r'''#!/usr/bin/env python3
import ctypes, os, pathlib, shutil, sys
args = sys.argv[1:]
if args[:1] == ['--controller-pin']:
    print('new-pin'); sys.exit(0)
if args[:1] == ['--retire-owned']:
    src, dst, identity = args[1:]
    root = pathlib.Path(os.environ['WMB_TEST_ROOT'])
    if not any(root.glob('WindowsMacBridge-install.*/retirement.unconfirmed')): sys.exit(79)
    expected = tuple(map(int, identity.split(':')))
    st = os.lstat(src)
    if (st.st_dev, st.st_ino) != expected: sys.exit(73)
    root = pathlib.Path(os.environ['WMB_TEST_ROOT'])
    inside_race = (os.environ.get('WMB_RETIRE_RACE') == 'rollback_inside_rename' and
                   (root/'failed-once').exists() and not (root/'inside-race-done').exists())
    if inside_race:
        (root/'inside-race-done').touch()
        os.rename(src, root/'displaced-inside-retirement.app')
        pathlib.Path(src).mkdir(); (pathlib.Path(src)/'foreign').write_text('foreign-must-survive')
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renamex_np(src.encode(), dst.encode(), 0x4) != 0: sys.exit(73)
    if inside_race:
        pathlib.Path(src).mkdir(); (pathlib.Path(src)/'blocker').write_text('also-foreign')
    if os.environ.get('WMB_FAIL') == 'kill_after_retirement':
        import signal
        os.kill(os.getppid(), signal.SIGKILL); sys.exit(44)
    moved = os.lstat(dst)
    if (moved.st_dev, moved.st_ino) != expected:
        libc.renamex_np(dst.encode(), src.encode(), 0x4)
        sys.exit(73)
    sys.exit(0)
if args[:1] == ['--publish-exclusive']:
    src, dst = args[1], args[2]
    root = pathlib.Path(os.environ['WMB_TEST_ROOT'])
    race = os.environ.get('WMB_PUBLISH_RACE', '')
    once = root/'publish-race-done'
    if race in ('directory', 'symlink') and not once.exists():
        once.touch()
        if race == 'directory': os.mkdir(dst)
        else: os.symlink(str(root/'elsewhere'), dst)
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renamex_np(src.encode(), dst.encode(), 0x4) != 0:
        sys.exit(73)
    if race == 'foreign_after_publish' and not once.exists():
        once.touch()
        # Another administrator replaces the freshly published App.
        os.rename(dst, str(root/'displaced-own.app'))
        os.mkdir(dst); (pathlib.Path(dst)/'foreign').write_text('foreign')
    sys.exit(0)
sys.exit(64)
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

    def run_install(self, receipt='installed', fail='', existing=True, installed_driver_version='1.8.0', active_driver=True, driver_running=None, private_app_resource=False, protected_app=False, unified_runtime=False, codesign_reject='', publish_race='', retire_race=''):
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
        executable.write_text(APP_STUB); executable.chmod(0o755)
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
            # A developer Mac may have Karabiner-Elements installed; never read the real path.
            transaction_text = transaction_text.replace("'/Applications/Karabiner-Elements.app'",
                                                        repr(str(root/'Applications/Karabiner-Elements.app')))
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
                   WMB_APP_PROTECTED='1' if protected_app else '0', WMB_CODESIGN_REJECT=codesign_reject,
                   WMB_PUBLISH_RACE=publish_race, WMB_RETIRE_RACE=retire_race)
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

    def test_finder_tagged_retired_app_rolls_back_from_the_verified_snapshot(self):
        # mv keeps com.apple.FinderInfo; strict verification of the retired bundle fails.
        root, app, helper, daemons, result = self.run_install(fail='bootstrap_helper')
        self.assertNotEqual(result.returncode, 0)
        self.assert_original(app, helper, daemons)
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA, WMB_ROLLBACK_SHA=ROLLBACK_SHA,
                   WMB_RECEIPT='installed', WMB_FAIL='bootstrap_helper', WMB_CODESIGN_REJECT='retired-application')
        (root/'failed-once').unlink(missing_ok=True)
        retry = subprocess.run(['/bin/bash', str(root/'InstallBackend.sh'), str(root/'payload')],
                               env=env, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(retry.returncode, 0)
        self.assertIn('previous App, input runtime, pin, Driver and service state restored', retry.stderr)
        self.assert_original(app, helper, daemons)
        self.assertFalse((helper/'.install-recovery').exists())

    def test_unverifiable_installed_app_is_never_switched(self):
        _, app, helper, daemons, result = self.run_install(codesign_reject='previous/WindowsMacBridge.app')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot be snapshotted for rollback', result.stderr)
        self.assert_original(app, helper, daemons)
        self.assertFalse((helper/'.install-recovery').exists())

    def test_recovery_leaves_the_shared_driver_alone_once_karabiner_also_uses_it(self):
        root, app, helper, _, result = self.run_install(receipt='7.3.0', fail='kill_during_driver')
        self.assertEqual(result.returncode, -9)
        (root/'Applications/Karabiner-Elements.app').mkdir()
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_ROLLBACK_SHA=ROLLBACK_SHA, WMB_RECEIPT='7.3.0', WMB_FAIL='')
        retry = subprocess.run(['/bin/bash', str(root/'InstallBackend.sh'), str(root/'payload')],
                               env=env, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(retry.returncode, 0)
        self.assertIn('Karabiner now also uses the shared Driver', retry.stderr)
        driver = root/'Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice'
        self.assertEqual((driver/'identity').read_text(), 'new-shared-driver')
        self.assertTrue((helper/'.install-recovery').exists())

    def test_destination_directory_or_symlink_appearing_at_publish_is_never_entered(self):
        for race in ['directory', 'symlink']:
            root, app, helper, daemons, result = self.run_install(existing=False, publish_race=race)
            self.assertNotEqual(result.returncode, 0, race)
            self.assertIn('Install destination is occupied', result.stderr)
            # Nothing was moved into the directory or through the link.
            if race == 'directory':
                self.assertEqual(list(app.iterdir()), [])
            else:
                self.assertTrue(app.is_symlink())
                self.assertFalse((root/'elsewhere').exists())
            self.assertFalse((helper/'.install-recovery').exists())

    def test_existing_app_publish_race_keeps_the_original_app(self):
        root, app, helper, daemons, result = self.run_install(publish_race='directory')
        # The old App was retired before the race, so the transaction must roll back
        # without touching the foreign directory.
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(app.is_dir())
        self.assertFalse((app/'identity').exists() and (app/'identity').read_text() == 'new-app')

    def test_rollback_never_moves_a_foreign_object_that_replaced_the_published_app(self):
        root, app, helper, daemons, result = self.run_install(fail='bootstrap_helper', publish_race='foreign_after_publish')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('foreign object now occupies the App path', result.stderr)
        self.assertEqual((app/'foreign').read_text(), 'foreign')
        self.assertTrue((helper/'.install-recovery').exists(), 'recovery stays pending')

    def test_rollback_identity_to_move_race_never_deletes_the_foreign_object(self):
        root, app, helper, _, result = self.run_install(fail='bootstrap_helper', retire_race='rollback')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((root/'retire-race-count').read_text(), '2', 'race was exercised')
        foreign = list(root.rglob('foreign'))
        self.assertEqual(len(foreign), 1, 'foreign object must survive rollback and cleanup')
        self.assertEqual(foreign[0].read_text(), 'foreign-must-survive')
        self.assertTrue((helper/'.install-recovery').exists(), 'recovery stays pending')

    def test_upgrade_identity_to_move_race_never_deletes_the_foreign_object(self):
        root, app, helper, _, result = self.run_install(retire_race='upgrade')
        self.assertNotEqual(result.returncode, 0, 'must refuse a changed App')
        self.assertEqual((root/'retire-race-count').read_text(), '3', 'race was exercised')
        foreign = list(root.rglob('foreign'))
        self.assertEqual(len(foreign), 1, 'foreign object must survive retirement and cleanup')
        self.assertEqual(foreign[0].read_text(), 'foreign-must-survive')
        self.assertTrue((helper/'.install-recovery').exists(), 'recovery stays pending')

    def test_later_recovery_never_cleans_a_quarantined_foreign_object(self):
        root, app, helper, _, result = self.run_install(fail='bootstrap_helper', retire_race='rollback_inside_rename')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((app/'blocker').exists())
        journal = helper/'.install-recovery'
        stage = Path(journal.read_text().splitlines()[1])
        self.assertTrue((stage/'retirement.unconfirmed').exists())
        foreign = list(stage.rglob('foreign'))
        self.assertEqual(len(foreign), 1)
        # Even after the occupied source path is freed, a later Install must not
        # silently delete the foreign object quarantined by the previous attempt.
        shutil.rmtree(app)
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_ROLLBACK_SHA=ROLLBACK_SHA, WMB_RECEIPT='installed', WMB_FAIL='')
        retry = subprocess.run(['/bin/bash', str(root/'InstallBackend.sh'), str(root/'payload')],
                               env=env, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(retry.returncode, 0)
        self.assertIn('Unconfirmed App retirement requires inspection', retry.stderr)
        self.assertEqual(foreign[0].read_text(), 'foreign-must-survive')
        self.assertTrue(journal.exists())

    def test_kill_after_retirement_preserves_the_durable_intent_and_old_app(self):
        root, app, helper, _, result = self.run_install(fail='kill_after_retirement')
        self.assertEqual(result.returncode, -9)
        journal = helper/'.install-recovery'
        stage = Path(journal.read_text().splitlines()[1])
        self.assertTrue((stage/'retirement.unconfirmed').exists())
        self.assertEqual((stage/'retired-application.app/identity').read_text(), 'old-app')
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA,
                   WMB_ROLLBACK_SHA=ROLLBACK_SHA, WMB_RECEIPT='installed', WMB_FAIL='')
        retry = subprocess.run(['/bin/bash', str(root/'InstallBackend.sh'), str(root/'payload')],
                               env=env, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(retry.returncode, 0)
        self.assertIn('Unconfirmed App retirement requires inspection', retry.stderr)
        self.assertTrue(journal.exists())
        self.assertEqual((stage/'retired-application.app/identity').read_text(), 'old-app')

    def test_snapshot_replacement_never_becomes_the_original_identity(self):
        root, app, helper, _, result = self.run_install(fail='snapshot_replaced')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('changed during snapshot', result.stderr)
        self.assertEqual((app/'foreign').read_text(), 'foreign-must-survive')
        self.assertEqual((root/'displaced-during-snapshot.app/identity').read_text(), 'old-app')
        self.assertEqual((helper/'controller.plist').read_text(), 'old-pin')
        self.assertFalse((helper/'.install-recovery').exists())

    def test_concurrent_installer_cannot_switch_while_another_owns_the_journal(self):
        root, app, helper, daemons, result = self.run_install(fail='kill_before_bootstrap')
        self.assertEqual(result.returncode, -9)
        journal = (helper/'.install-recovery').read_text().splitlines()
        # Pretend the interrupted owner is still alive in this boot.
        lines = journal[:]; lines[2] = str(os.getpid())
        (helper/'.install-recovery').write_text('\n'.join(lines) + '\n')
        env = dict(os.environ, WMB_TEST_ROOT=str(root), WMB_DRIVER_SHA=DRIVER_SHA, WMB_ROLLBACK_SHA=ROLLBACK_SHA,
                   WMB_RECEIPT='installed', WMB_FAIL='')
        before = sorted(p.name for p in app.parent.iterdir())
        second = subprocess.run(['/bin/bash', str(root/'InstallBackend.sh'), str(root/'payload')],
                                env=env, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn('Another installer may still be running', second.stderr)
        self.assertEqual(sorted(p.name for p in app.parent.iterdir()), before)

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
