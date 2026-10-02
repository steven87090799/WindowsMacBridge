from pathlib import Path
import os
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
class SDKBuildTests(unittest.TestCase):
    def test_verified_marker_does_not_bypass_archive_integrity(self):
        with tempfile.TemporaryDirectory(prefix='wmb-sdk-') as d:
            root = Path(d); (root/'scripts').mkdir(); (root/'Tools/HIDBackend').mkdir(parents=True)
            cache = root/'cache'; cache.mkdir(); (cache/'verified').write_text('old marker')
            (cache/'source.tar.gz').write_bytes(b'tampered archive')
            script = (ROOT/'scripts/prepare-hid-backend.sh').read_text().replace(
                'bridge_cache="$HOME/Library/Caches/WindowsMacBridge/HIDSDK/$bridge_revision"',
                f'bridge_cache="{cache}"')
            (root/'scripts/prepare-hid-backend.sh').write_text(script)
            result = subprocess.run(['/bin/bash',str(root/'scripts/prepare-hid-backend.sh')], capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('checksum mismatch',result.stderr)
            self.assertFalse((root/'Tools/HIDBackend/SDK').exists())
    def test_optimized_python_still_rejects_header_shape_drift(self):
        with tempfile.TemporaryDirectory(prefix='wmb-header-') as d:
            root=Path(d); p=root/'include/pqrs/karabiner/driverkit/virtual_hid_device_service/client.hpp'
            p.parent.mkdir(parents=True); p.write_text('upstream incompatible header')
            result=subprocess.run(['python3',str(ROOT/'scripts/prepare-hid-sdk.py'),str(root/'include'),str(root/'out')],
                env=dict(os.environ,PYTHONOPTIMIZE='1'),capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('shape changed',result.stderr)
