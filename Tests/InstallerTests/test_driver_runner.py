"""Native bounded-job tests; only a private runner copy and disposable children run."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

@unittest.skipUnless(sys.platform == 'darwin', 'Native Darwin process groups')
class DriverProcessRunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='WindowsMacBridge-install.runner-',dir='/private/var/tmp')
        cls.root = Path(cls.directory.name)
        cls.manager = cls.root/'TestManager'
        cls.runner = cls.root/'TestRunner'
        result = subprocess.run(['/usr/bin/clang','-O1','-Wall','-Wextra','-Werror',
                                 '-DWMB_DRIVER_TIMEOUT=1','-DWMB_MANAGER_PATH='+json.dumps(str(cls.manager)),
                                 str(ROOT/'Resources/Installer/DriverProcessRunner.c'),'-o',str(cls.runner)],
                                capture_output=True,text=True,timeout=30)
        if result.returncode: raise RuntimeError(result.stderr)

    @classmethod
    def tearDownClass(cls): cls.directory.cleanup()

    def run_manager(self, script):
        self.manager.write_text('#!/bin/sh\n'+script); self.manager.chmod(0o700)
        log = self.root/'driver-activate.log'
        if log.exists(): log.unlink()
        result = subprocess.run([str(self.runner),str(self.manager),'activate',str(log)],
                                capture_output=True,text=True,timeout=6)
        return result, log

    def test_normal_exit_and_bounded_log(self):
        result, log = self.run_manager("printf 'completed\\n'\n")
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(log.read_text(),'completed\n')

    def test_output_storm_cannot_grow_log(self):
        result, log = self.run_manager('/usr/bin/yes spam\n')
        self.assertEqual(result.returncode,125,result.stderr)
        self.assertLessEqual(log.stat().st_size,65536)

    def test_timeout_cancels_descendants_before_return(self):
        pidfile = self.root/'child.pid'
        result, _ = self.run_manager("trap '' TERM\n/bin/sleep 30 &\nprintf '%s' \"$!\" > "+str(pidfile)+"\nwait\n")
        self.assertEqual(result.returncode,124,result.stderr)
        pid = int(pidfile.read_text())
        state = subprocess.run(['/bin/ps','-p',str(pid),'-o','stat='],capture_output=True,text=True).stdout.strip()
        self.assertTrue(not state or state.startswith('Z'),state)

    def test_existing_hardlink_is_rejected_without_truncating_original(self):
        self.manager.write_text('#!/bin/sh\nexit 0\n'); self.manager.chmod(0o700)
        original = self.root/'protected'; original.write_text('preserve'); original.chmod(0o600)
        log = self.root/'driver-restore.log'
        if log.exists(): log.unlink()
        os.link(original,log)
        result = subprocess.run([str(self.runner),str(self.manager),'activate',str(log)],capture_output=True,text=True,timeout=6)
        self.assertEqual(result.returncode,73,result.stderr)
        self.assertEqual(original.read_text(),'preserve')

if __name__ == '__main__': unittest.main()
