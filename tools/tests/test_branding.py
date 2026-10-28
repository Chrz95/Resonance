import importlib.util
import tempfile
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('install_branding', ROOT / 'tools/install_branding.py')
branding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(branding)


class BrandingTest(unittest.TestCase):
    def test_complete_platform_icons(self):
        icons = ROOT / 'client/platform_config/icons'
        with Image.open(icons / 'windows/app_icon.ico') as image:
            self.assertEqual(image.ico.sizes(), {(n, n) for n in [16, 24, 32, 48, 64, 128, 256]})
        for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
            with Image.open(icons / f'android/mipmap-{density}/ic_launcher.png') as image:
                self.assertEqual(image.size, (round(48 * scale),) * 2)
            with Image.open(icons / f'android/mipmap-{density}/ic_launcher_foreground.png') as image:
                self.assertEqual(image.size, (round(108 * scale),) * 2)
                self.assertEqual(image.getpixel((0, 0))[3], 0)

    def test_install_and_reinstall_after_flutter_generation(self):
        with tempfile.TemporaryDirectory() as temp:
            client = Path(temp)
            import shutil
            shutil.copytree(ROOT / 'client/platform_config/icons', client / 'platform_config/icons')
            branding.install_branding(client)
            destination = client / 'windows/runner/resources/app_icon.ico'
            expected = destination.read_bytes()
            destination.write_bytes(b'flutter default')
            branding.install_branding(client)
            self.assertEqual(destination.read_bytes(), expected)
            self.assertTrue((client / 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').exists())
            self.assertEqual(len(list((client / 'android/app/src/main/res').rglob('*.png'))), 10)


if __name__ == '__main__':
    unittest.main()
