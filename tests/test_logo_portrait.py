import hashlib
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/"scripts/patch-s55-logo-artwork.py"

def load_script():
    spec=importlib.util.spec_from_file_location("s55_artwork", SCRIPT)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class PortraitLogoTests(unittest.TestCase):
    def test_fills_full_height_instead_of_square_letterbox(self):
        mod=load_script()
        w,h=60,120
        src=bytearray()
        for y in range(h):
            for x in range(w):
                src.extend((30+y,35+x,120))
        pixels=mod.artwork_bgra(w,h,src)
        self.assertEqual(len(pixels),720*1440*4)
        top=pixels[0:4]
        bottom=pixels[(1439*720)*4:(1439*720)*4+4]
        self.assertNotEqual(top,bytes((0,0,0,255)))
        self.assertNotEqual(bottom,bytes((0,0,0,255)))
        self.assertNotEqual(top,bottom)
        self.assertEqual(top[3],255)
        self.assertEqual(bottom[3],255)
    @unittest.skipUnless((ROOT/"backups/device-2026-10-29-kpoc/stock-as-installed-logo-before-graphics-20261030.img").is_file() and (ROOT/"files/candidates/s55-logo-gods-work-portrait-UNFLASHED.img").is_file(), "private OEM logo partition not in public Git")
    def test_candidate_unchanged_other_sprites(self):
        mod=load_script()
        part=(ROOT/"backups/device-2026-10-29-kpoc/stock-as-installed-logo-before-graphics-20261030.img").read_bytes()
        existing=(ROOT/"files/candidates/s55-logo-gods-work-portrait-UNFLASHED.img").read_bytes()
        self.assertEqual(len(existing),mod.mtk.PART_SIZE)
        import struct,zlib
        def unpack_any(data):
            total=struct.unpack_from("<II",data,512)[1]
            starts=struct.unpack_from("<39I",data,520)
            return [zlib.decompress(data[512+starts[i]:512+(starts[i+1] if i+1<39 else total)]) for i in range(39)]
        before,after=unpack_any(part),unpack_any(existing)
        self.assertEqual(len(before),39)
        self.assertEqual(len(after),39)
        self.assertNotEqual(before[2],after[2])
        for i in range(39):
            if i!=2:self.assertEqual(before[i],after[i],f"sprite {i} must remain OEM")
if __name__=="__main__":
    unittest.main()
