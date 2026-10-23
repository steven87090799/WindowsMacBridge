"""Check canonical test orchestration with fake tools in a private directory."""
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MEMORY_TESTS = (
    'BridgePlatformTests.ScreenshotBoundedReadTests/repeatedPreparationDoesNotGrowMemoryWithCaptureCount',
    'BridgePlatformTests.InputDiagnosticsTests/repeatedTraceSnapshotsKeepMemoryBounded',
)


class TestRunnerTests(unittest.TestCase):
    def run_runner(self, arguments=(), fail_call=0, with_plugin=False):
        with tempfile.TemporaryDirectory(prefix='wmb-test-runner-') as directory:
            root = Path(directory)
            scripts = root/'scripts'; scripts.mkdir()
            shutil.copy2(ROOT/'scripts/test.sh', scripts/'test.sh')
            (scripts/'build-environment.sh').write_text('task_scratch="$task_root/scratch"\n')
            (scripts/'prepare-hid-backend.sh').write_text('#!/bin/bash\nexit 0\n')
            tools = root/'tools'; tools.mkdir()
            swiftc = root/'toolchain/usr/bin/swiftc'
            (tools/'xcrun').write_text('#!/bin/bash\nprintf "%s\\n" ' + shlex.quote(str(swiftc)) + '\n')
            (tools/'swift').write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
path = pathlib.Path(os.environ['WMB_RUNNER_CALLS'])
count = len(path.read_text().splitlines()) if path.exists() else 0
with path.open('a') as output: output.write(json.dumps(sys.argv[1:]) + '\\n')
sys.exit(97 if count + 1 == int(os.environ['WMB_FAIL_CALL']) else 0)
''')
            for tool in tools.iterdir(): tool.chmod(0o755)
            if with_plugin:
                plugin = root/'toolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib'
                plugin.parent.mkdir(parents=True); plugin.write_bytes(b'fixture-only')
            log = root/'calls.jsonl'
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                       WMB_RUNNER_CALLS=str(log), WMB_FAIL_CALL=str(fail_call))
            result = subprocess.run(['/bin/bash', str(scripts/'test.sh'), *arguments],
                                    env=env, capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_full_run_requires_main_and_separate_memory_process(self):
        result, calls = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][-2], '--skip')
        memory_pattern = calls[0][-1]
        self.assertEqual(calls[1][-3:], ['--no-parallel', '--filter', memory_pattern])
        for name in MEMORY_TESTS:
            self.assertIsNotNone(re.fullmatch(memory_pattern, name))
        self.assertIsNone(re.search(memory_pattern, 'BridgePlatformTests.InputDiagnosticsTests/disabledAndEmptySessionsAllocateNoRecordStorage'))
        self.assertIn('--skip-build', calls[1])
        self.assertNotIn('--skip', calls[1])

    def test_release_plugin_and_build_options_are_preserved_for_memory_process(self):
        result, calls = self.run_runner(['-c', 'release', '--parallel', '--num-workers', '4'], with_plugin=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertEqual(call[call.index('-c') + 1], 'release')
            self.assertIn('-load-plugin-library', call)
        self.assertIn('--parallel', calls[0])
        self.assertNotIn('--parallel', calls[1])
        self.assertNotIn('--num-workers', calls[1])

    def test_explicit_selection_serial_and_report_requests_are_not_rewritten(self):
        for args in [('--filter', 'SettingsStoreTests'), ('--filter=SettingsStoreTests',),
                     ('--skip', 'SomeTest'), ('--no-parallel',), ('--list-tests',),
                     ('--enable-code-coverage',), ('--xunit-output', 'results.xml'), ('list',)]:
            with self.subTest(arguments=args):
                result, calls = self.run_runner(args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0][-len(args):], list(args))

    def test_failures_in_either_process_fail_the_gate(self):
        for failure, call_count in [(1, 1), (2, 2)]:
            with self.subTest(failure=failure):
                result, calls = self.run_runner(fail_call=failure)
                self.assertEqual(result.returncode, 97)
                self.assertEqual(len(calls), call_count)

    def test_existing_skip_build_is_forwarded_once(self):
        result, calls = self.run_runner(['--skip-build', '-c', 'release'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[1].count('--skip-build'), 1)


if __name__ == '__main__':
    unittest.main()
