"""LK Orange State cosmetic patch safety checks; no phone or flash."""
from pathlib import Path
import importlib.util
import hashlib
import unittest

ROOT=Path(__file__).resolve().parents[1]
F=ROOT/"scripts/patch-s55-lk-orange-text-only.py"
spec=importlib.util.spec_from_file_location("lkpatch",F)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class LKPatchSafetyTests(unittest.TestCase):
    def test_source_known_offline_and_only_text_diff(self):
        original=ROOT/"backups/device-2026-10-29-kpoc/stock-as-installed-lk-before-graphics-20261030.img"
        if not original.exists():
            self.skipTest("Private original backup unavailable")
        before=original.read_bytes()
        after=mod.patch(before)
        self.assertEqual(len(before),len(after))
        self.assertEqual(hashlib.sha256(after).hexdigest(),mod.PATCHED_SHA256)
        self.assertEqual(before[:2048],after[:2048])
        changes=[i for i,(a,b) in enumerate(zip(before,after)) if a!=b]
        self.assertEqual(len(changes),96)
        self.assertTrue(all(after[i]==0 for i in changes))
        self.assertFalse(any(x in after for x in mod.WORDS))
    def test_reject_modified_or_short_unknown_lk(self):
        self.assertRaises(ValueError,mod.patch,b"")
        orig=ROOT/"backups/device-2026-10-29-kpoc/stock-as-installed-lk-before-graphics-20261030.img"
        if orig.exists():
            b=bytearray(orig.read_bytes())
            b[0]^=1
            self.assertRaises(ValueError,mod.patch,bytes(b))

if __name__=="__main__":
    unittest.main()
