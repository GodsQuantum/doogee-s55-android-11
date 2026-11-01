import hashlib
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
FB=ROOT/"scripts/kpoc-s55-fb-off.c"
DIAG=ROOT/"files/candidates/kpoc-v9-fb-diag-UNINSTALLED-arm64"
ORIG=ROOT/"files/candidates/kpoc-v5-fb-off-UNINSTALLED-arm64"
INSTALL=ROOT/"backups/device-2026-10-29-kpoc/deploy-kpoc-v9-diagnostic-pegasus.sh"
SHA_NEW="7fd8a099995d04dc853e74133e4839baa79d11af27a58499ef3b81c4756e7943"
SHA_OLD="b763022619f23f2777b5ebf58e1edb877651301da53722fbda8369c15d322d38"

class ChargerBacklightDiagnosticsTests(unittest.TestCase):
    def test_charger_domain_existing_fb_path_only(self):
        code=FB.read_text()
        for mark in ['S55KPOC_FB ','LED_BEFORE','FBIOBLANK','LED_AFTER','brightness()']:
            self.assertIn(mark,code)
        self.assertIn('FBIOBLANK,4',code)
        self.assertIn('finish(result==0?0:11)',code)
        self.assertNotIn('"/sys/power/',code)
        self.assertNotIn('"/dev/mem',code)
        self.assertNotIn('"/sys/class/leds/lcd-backlight/brightness",O_WRONLY',code)
        self.assertNotIn('NANOSLEEP',code)
    @unittest.skipUnless(DIAG.is_file() and ORIG.is_file(), "private compiled OEM-derived binaries not in public Git")
    def test_binary_static_elf_and_hash(self):
        original=ORIG.read_bytes()
        new=DIAG.read_bytes()
        self.assertEqual(hashlib.sha256(original).hexdigest(),SHA_OLD)
        self.assertEqual(hashlib.sha256(new).hexdigest(),SHA_NEW)
        self.assertEqual(new[:4],b'\x7fELF')
        self.assertEqual(int.from_bytes(new[18:20],"little"),183) # EM_AARCH64
        self.assertIn(b"S55KPOC_FB ",new)
    @unittest.skipUnless(INSTALL.is_file(), "private deployment script not in public Git")
    def test_install_rollback_sha_and_scope(self):
        script=INSTALL.read_text()
        self.assertIn(f"OLD={SHA_OLD}",script)
        self.assertIn(f"NEW={SHA_NEW}",script)
        self.assertIn('P=/vendor/bin/s55_kpoc_fb_off',script)
        self.assertIn('candidate=files/candidates/kpoc-v5-fb-off-UNINSTALLED-arm64',script)
        self.assertIn('case "$mode" in',script)
        self.assertIn('--dry-run|--apply',script)
        self.assertIn('test "$label_before" = "$label_after"',script)
        self.assertIn('trap recover EXIT',script)
        self.assertNotIn('unroot',script)
        self.assertNotIn('/vendor/etc/init/',script)
if __name__=="__main__":
    unittest.main()
