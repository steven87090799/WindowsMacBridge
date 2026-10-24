import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = '/Applications/WindowsMacBridge.app'


class RecoveryHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler_directory = tempfile.TemporaryDirectory(prefix='wmb-recovery-build-')
        build = Path(cls.compiler_directory.name)
        launcher = build / 'fake-open'
        launcher.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
directory = Path(os.environ['WMB_TEST_RECOVERY_DIRECTORY'])
(directory/'launch.json').write_text(json.dumps(sys.argv[1:]))
mode = os.environ.get('WMB_TEST_RECOVERY_MODE', 'ack')
if mode == 'fail': sys.exit(1)
if mode == 'hang': time.sleep(30)
if mode == 'ack':
    token = sys.argv[sys.argv.index('--bridge-recovery-token') + 1]
    (directory/('ready-' + token)).write_text('ready')
''')
        launcher.chmod(0o700)
        cls.helper = build / 'WindowsMacBridgeRecovery'
        subprocess.run(['clang', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                        '-DWMB_RECOVERY_TESTING', '-DWMB_RECOVERY_LAUNCHER=' + json.dumps(str(launcher)),
                        '-framework', 'CoreFoundation', str(ROOT/'Tools/RecoveryHelper/RecoveryHelper.c'),
                        '-o', str(cls.helper)], check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls):
        cls.compiler_directory.cleanup()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='wmb-recovery-test-')
        self.root = Path(self.directory.name)
        self.recovery = self.root / 'Recovery'
        self.recovery.mkdir(mode=0o700)
        self.lock = self.root / 'instance.lock'
        self.lock.touch(mode=0o600)
        self.addCleanup(self.directory.cleanup)

    def start(self, attempt=0, window=None, mode='ack', app=APP, directory=None):
        if window is None:
            window = int(time.time() * 1000)
        env = dict(os.environ, WMB_TEST_RECOVERY_DIRECTORY=str(self.recovery), WMB_TEST_RECOVERY_MODE=mode)
        process = subprocess.Popen([str(self.helper), app, str(directory or self.recovery), str(attempt), str(window)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        return process

    def finish(self, process, message=b''):
        output, error = process.communicate(message, timeout=5)
        return process.returncode, output, error

    def log(self):
        return (self.recovery/'Recovery.log').read_text()

    def test_normal_quit_disarms_without_relaunching(self):
        result, _, _ = self.finish(self.start(), b'Q')
        self.assertEqual(result, 0)
        self.assertIn('normal_exit', self.log())
        self.assertNotIn('unexpected_exit', self.log())
        self.assertFalse((self.recovery/'launch.json').exists())

    def test_unexpected_pipe_close_relaunches_and_requires_new_monitor_ack(self):
        result, _, _ = self.finish(self.start())
        self.assertEqual(result, 0)
        args = json.loads((self.recovery/'launch.json').read_text())
        self.assertEqual(args[:3], ['-g', APP, '--args'])
        self.assertEqual(args[args.index('--bridge-recovery-attempt') + 1], '1')
        self.assertIn('relaunch_acknowledged', self.log())
        self.assertFalse(list(self.recovery.glob('ready-*')))

    def test_next_crash_preserves_window_and_advances_attempt(self):
        window = int(time.time() * 1000) - 1000
        self.assertEqual(self.finish(self.start(attempt=2, window=window))[0], 0)
        args = json.loads((self.recovery/'launch.json').read_text())
        self.assertEqual(args[args.index('--bridge-recovery-attempt') + 1], '3')
        self.assertEqual(args[args.index('--bridge-recovery-window') + 1], str(window))

    def test_three_recoveries_stop_the_loop_and_emit_a_notice(self):
        self.assertEqual(self.finish(self.start(attempt=3))[0], 75)
        self.assertIn('recovery_stopped', self.log())
        self.assertFalse((self.recovery/'launch.json').exists())

    def test_old_window_allows_a_new_bounded_recovery(self):
        self.assertEqual(self.finish(self.start(attempt=3, window=int(time.time()*1000)-300001))[0], 0)
        args = json.loads((self.recovery/'launch.json').read_text())
        self.assertEqual(args[args.index('--bridge-recovery-attempt') + 1], '1')

    def test_policy_uses_backoff_and_handles_clock_changes(self):
        def plan(attempt, window, now):
            return list(map(int, subprocess.check_output([str(self.helper), '--plan', str(attempt), str(window), str(now)], text=True).split()))
        self.assertEqual([plan(n, 1000, 2000)[1] for n in range(3)], [1, 3, 10])
        self.assertEqual(plan(3, 1000, 2000)[3], 1)
        self.assertEqual(plan(3, 1000, 301000), [1, 1, 301000, 0])
        self.assertEqual(plan(3, 2000, 1000), [1, 1, 1000, 0])

    def test_manual_reopen_during_delay_wins(self):
        with self.lock.open('rb') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.finish(self.start())[0], 0)
        self.assertIn('existing_instance', self.log())
        self.assertFalse((self.recovery/'launch.json').exists())

    def test_failed_launch_is_reported_without_an_infinite_retry(self):
        self.assertEqual(self.finish(self.start(mode='fail'))[0], 75)
        self.assertIn('relaunch_unconfirmed', self.log())
        self.assertIn('recovery_stopped', self.log())

    def test_successful_open_without_an_armed_monitor_is_not_success(self):
        self.assertEqual(self.finish(self.start(mode='no-ack'))[0], 75)
        self.assertIn('recovery_stopped', self.log())
        self.assertNotIn('relaunch_acknowledged', self.log())

    def test_stuck_launcher_is_bounded_and_reported(self):
        started = time.monotonic()
        self.assertEqual(self.finish(self.start(mode='hang'))[0], 75)
        self.assertLess(time.monotonic() - started, 4)
        self.assertIn('recovery_stopped', self.log())

    def test_monitor_shutdown_does_not_reopen_the_app(self):
        process = self.start()
        time.sleep(0.1)
        process.send_signal(signal.SIGTERM)
        self.assertEqual(self.finish(process)[0], -signal.SIGTERM)
        self.assertFalse((self.recovery/'launch.json').exists())

    def test_private_directory_and_fixed_application_are_required(self):
        self.assertEqual(self.finish(self.start(app='/Applications/Other.app'))[0], 64)
        self.assertEqual(self.finish(self.start(attempt=4))[0], 64)
        self.recovery.chmod(0o755)
        self.assertEqual(self.finish(self.start())[0], 77)
        self.recovery.chmod(0o700)
        link = self.root/'linked-recovery'
        link.symlink_to(self.recovery)
        self.assertEqual(self.finish(self.start(directory=link))[0], 77)

    def test_production_policy_self_check_does_not_start_monitoring(self):
        result = subprocess.run([str(self.helper), '--self-check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('no monitoring, relaunch or notification started', result.stdout)
        self.assertFalse((self.recovery/'Recovery.log').exists())


if __name__ == '__main__':
    unittest.main()
