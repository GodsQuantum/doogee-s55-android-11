"""DOOGEE S55 neutral initial charging symbol integrity: offline only."""
import importlib.util
from pathlib import Path
import struct,zlib,unittest
ROOT=Path(__file__).resolve().parents[1]
P=ROOT/"scripts/patch-s55-logo-neutral-charging.py"
spec=importlib.util.spec_from_file_location("s55logo",P)
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)
class LogoSafetyTests(unittest.TestCase):
    def setUp(self):
        self.path=ROOT/"backups/device-2026-10-29-kpoc/stock-as-installed-logo-before-graphics-20261030.img"
        if not self.path.exists():self.skipTest("Private original absent")
        self.orig=self.path.read_bytes()
    def test_repacking_39_images_only_low_index_2_changes(self):
        patched=M.repack(self.orig)
        self.assertEqual(len(patched),len(self.orig))
        self.assertEqual(patched[:4],self.orig[:4])
        self.assertEqual(patched[8:512],self.orig[8:512])
        n,sz=struct.unpack_from('<II',patched,512)
        self.assertEqual(n,39)
        off=struct.unpack_from('<39I',patched,520)
        self.assertEqual(off[0],164)
        self.assertEqual(sz,164+sum(len(x) for x in M.unpack(self.orig)[:2]) +
                         len(zlib.compress(M.neutral_bitmap(),9)) +
                         sum(len(x) for x in M.unpack(self.orig)[3:]))
        for idx in range(39):
            lo=512+off[idx]
            hi=512+(off[idx+1] if idx+1<39 else sz)
            data=zlib.decompress(patched[lo:hi])
            if idx==2:self.assertEqual(data,M.neutral_bitmap())
            else:self.assertEqual(data,zlib.decompress(M.unpack(self.orig)[idx]))
        self.assertEqual(M.digest(patched),"9a30ace267a75eb5ae12cb019717eebfcfd6f639b2e85ac1687d10a7c05bf42c")
    def test_refuse_unknown_image(self):
        self.assertRaises(ValueError,M.repack,b'unknown')
        modified=bytearray(self.orig);modified[500]^=1
        self.assertRaises(ValueError,M.repack,bytes(modified))
    def test_stock_warning_3_preserved(self):
        parts=M.unpack(self.orig)
        self.assertEqual(len(zlib.decompress(parts[3])),720*1440*4)
        self.assertNotEqual(parts[2],parts[3])
if __name__=="__main__":unittest.main()
