import hashlib
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
C=ROOT/"scripts/kpoc-s55-lcd-off.c"
IMG=ROOT/"files/candidates/kpoc-v10-pwm-edge-UNINSTALLED-arm64"
INSTALL=ROOT/"backups/device-2026-10-29-kpoc/deploy-kpoc-v10-pwm-edge-pegasus.sh"
SHA="95204eca3be544e0965a1a0d7b12977352e70cb7064be7b1f73ab949fa5be77b"
OLD="e5bc66d066aa65b2512ee8534e4d56c9f757184c7e508267e4b9652d35ae1515"
class V10PWMEdgeTests(unittest.TestCase):
    def test_transition_and_bounded_delay(self):
        c=C.read_text()
        assert c.count('my_write(fd,"1\\n",2)')==1
        assert c.count('my_write(fd,"0\\n",2)')==1
        assert c.index('my_write(fd,"1\\n",2)')<c.index('pause_ms(90)')<c.index('my_write(fd,"0\\n",2)')
        assert c.index('my_write(fd,"0\\n",2)')<c.index("pause_ms(35)")
        self.assertIn('if(n!=2)return 15;',c)
        self.assertIn('if(n!=2)return 11;',c)
        self.assertEqual(c.count('led_off()'),3)
        self.assertNotIn('"/sys/power/',c)
        self.assertNotIn('"/dev/mem',c)
    @unittest.skipUnless(IMG.is_file() and INSTALL.is_file(), "private compiled binary and deployment script not in public Git")
    def test_static_binary_and_guarded_rollback(self):
        b=IMG.read_bytes()
        self.assertEqual(hashlib.sha256(b).hexdigest(),SHA)
        self.assertEqual(b[:4],b'\x7fELF')
        self.assertEqual(int.from_bytes(b[18:20],"little"),183)
        s=INSTALL.read_text()
        self.assertIn(f"OLD={OLD}",s)
        self.assertIn(f"NEW={SHA}",s)
        self.assertIn('P=/vendor/bin/s55_kpoc_lcd_off',s)
        self.assertIn('candidate=files/candidates/kpoc-v7-lcd-UNINSTALLED-arm64',s)
        self.assertIn('trap recover EXIT',s)
        self.assertIn('test "$label_before" = "$label_after"',s)
        self.assertIn('mode=--dry-run',s)
        self.assertNotIn(' unroot',s)
if __name__=="__main__":unittest.main()
