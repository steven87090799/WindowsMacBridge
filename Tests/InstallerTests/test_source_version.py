import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
class SourceVersionTests(unittest.TestCase):
    def test_zip_without_git_and_explicit_revision(self):
        with tempfile.TemporaryDirectory(prefix='wmb-source-') as directory:
            command = 'task_root="$1"; source "$2"; printf "%s|%s" "$bridge_revision" "$bridge_source_state"'
            script = str(ROOT/'scripts/source-version.sh')
            result = subprocess.run(['/bin/bash','-euc',command,'test',directory,script], capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout,'archive|archive')
            env = dict(os.environ,SOURCE_REVISION='abcdef0123456789')
            result = subprocess.run(['/bin/bash','-euc',command,'test',directory,script],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout,'abcdef0123456789|provided')
    def test_invalid_provided_revision_fails_closed(self):
        result = subprocess.run(['/bin/bash','-euc','task_root="$1"; source "$2"','test',str(ROOT),str(ROOT/'scripts/source-version.sh')],
                                env=dict(os.environ,SOURCE_REVISION='not a revision'),capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
    def test_git_checkout_is_identified(self):
        result = subprocess.run(['/bin/bash','-euc','task_root="$1"; source "$2"; printf "%s|%s" "$bridge_revision" "$bridge_source_state"',
                                 'test',str(ROOT),str(ROOT/'scripts/source-version.sh')],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertRegex(result.stdout,r'^[0-9a-f]{40}\|(clean|modified)$')

if __name__ == '__main__': unittest.main()
