import importlib.util
import tempfile
import struct
import subprocess
import shutil
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('install_branding', ROOT / 'tools/install_branding.py')
branding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(branding)
verify_spec = importlib.util.spec_from_file_location('verify_windows_icon', ROOT / 'tools/verify_windows_icon.py')
verify = importlib.util.module_from_spec(verify_spec)
verify_spec.loader.exec_module(verify)


def runner_fixture(client):
    runner = client / 'windows/runner'
    runner.mkdir(parents=True, exist_ok=True)
    (runner / 'Runner.rc').write_text('#include "resource.h"\nIDI_APP_ICON ICON "resources\\\\app_icon.ico"\n// Keep version metadata\n')
    (runner / 'resource.h').write_text('#define IDI_APP_ICON 101\n')
    (runner / 'CMakeLists.txt').write_text('set(BINARY_NAME resonance)\nadd_executable(${BINARY_NAME} main.cpp "Runner.rc")\nset_source_files_properties(Runner.rc PROPERTIES HEADER_FILE_ONLY TRUE)\n')
    (runner / 'main.cpp').write_text('int main() { return 0; }\n')



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
            shutil.copytree(ROOT / 'client/platform_config', client / 'platform_config')
            runner_fixture(client)
            branding.install_branding(client)
            destination = client / 'windows/runner/resources/app_icon.ico'
            expected = destination.read_bytes()
            destination.write_bytes(b'flutter default')
            branding.install_branding(client)
            self.assertEqual(destination.read_bytes(), expected)
            runner = client / 'windows/runner'
            self.assertEqual((runner / 'resources/resonance.ico').read_bytes(), expected)
            rc = (runner / 'Runner.rc').read_text()
            self.assertIn('resonance.ico', rc)
            self.assertNotIn('app_icon.ico', rc)
            self.assertIn('Keep version metadata', rc)
            self.assertEqual((runner / 'CMakeLists.txt').read_text().count('# BEGIN RESONANCE EXECUTABLE ICON'), 1)
            self.assertTrue((client / 'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').exists())
            self.assertEqual(len(list((client / 'android/app/src/main/res').rglob('*.png'))), 10)

    def test_changed_resource_template_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            client = Path(temp)
            runner_fixture(client)
            (client / 'windows/runner/Runner.rc').write_text('// no icon resource')
            with self.assertRaisesRegex(RuntimeError, 'icon resource'):
                branding.install_windows_branding(client)

    def test_cmake_reinstalls_committed_icon_and_refuses_reset_resource(self):
        with tempfile.TemporaryDirectory(prefix='branding space ') as temp:
            client = Path(temp) / 'client'
            shutil.copytree(ROOT / 'client/platform_config', client / 'platform_config')
            runner_fixture(client)
            branding.install_windows_branding(client)
            (client / 'windows/CMakeLists.txt').write_text('cmake_minimum_required(VERSION 3.14)\nproject(brandingcheck LANGUAGES CXX)\nadd_subdirectory(runner)\n')
            runner = client / 'windows/runner'
            for filename in ['app_icon.ico', 'resonance.ico']:
                (runner / 'resources' / filename).write_bytes(b'flutter default')
            result = subprocess.run(['cmake', '-S', str(client / 'windows'), '-B', str(client / 'build')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            expected = (client / 'platform_config/icons/windows/app_icon.ico').read_bytes()
            self.assertEqual((runner / 'resources/resonance.ico').read_bytes(), expected)
            self.assertEqual((runner / 'resources/app_icon.ico').read_bytes(), expected)
            # A later Flutter template reset must not silently embed the default.
            (runner / 'Runner.rc').write_text('IDI_APP_ICON ICON "resources/app_icon.ico"\n')
            result = subprocess.run(['cmake', '-S', str(client / 'windows'), '-B', str(client / 'build')], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('resource was reset', result.stdout + result.stderr)

    def test_executable_verifier_compares_all_embedded_image_payloads(self):
        expected = verify.ico_images(ROOT / 'client/platform_config/icons/windows/app_icon.ico')
        group = struct.pack('<HHH', 0, 1, len(expected))
        payloads = {}
        for index, (metadata, payload) in enumerate(expected, 1):
            group += struct.pack('<BBBBHHIH', *metadata, len(payload), index)
            payloads[index] = payload
        verify.verify_group(group, payloads.__getitem__, expected)
        payloads[1] = b'flutter icon'
        with self.assertRaisesRegex(ValueError, 'different icon artwork'):
            verify.verify_group(group, payloads.__getitem__, expected)


if __name__ == '__main__':
    unittest.main()
