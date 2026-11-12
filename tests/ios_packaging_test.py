"""Regression tests for structural preflight; fixtures are not runnable apps."""
import contextlib
import io
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile
import zlib

from verify_ios_ipa import check_icons, check_ipa, png_size


class DevicePackagingTests(unittest.TestCase):
    prefix = 'Payload/ABMMobile.app/'

    def bundle(self):
        info = {'CFBundlePackageType': 'APPL', 'CFBundleExecutable': 'ABMMobile',
                'CFBundleIdentifier': 'io.github.dauphindm.abmmobile',
                'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '5',
                'CFBundleSupportedPlatforms': ['iPhoneOS'], 'MinimumOSVersion': '26.0',
                'UIDeviceFamily': [1, 2], 'NSLocalNetworkUsageDescription': 'Connect to your PC.'}
        primary = {'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon', 'CFBundleIconFiles': ['AppIcon']}}
        info['CFBundleIcons'] = info['CFBundleIcons~ipad'] = primary
        header = struct.pack('<8I', 0xfeedfacf, 0x0100000c, 0, 2, 2, 48, 0, 0)
        build = struct.pack('<8I', 0x32, 32, 2, 26 << 16, 26 << 16, 1, 3, 1)
        signature = struct.pack('<4I', 0x1d, 16, 80, 12)
        blob = struct.pack('>3I', 0xfade0cc0, 12, 0)
        files = {'Info.plist': plistlib.dumps(info), 'ABMMobile': header + build + signature + blob,
                 'Assets.car': b'test-fixture', '_CodeSignature/CodeResources': b'test-fixture'}
        icons = Path(__file__).resolve().parent.parent / 'ios/ABMMobile/Assets.xcassets/AppIcon.appiconset'
        for name in ['iphone-60@2x', 'iphone-60@3x', 'ipad-76@2x', 'ipad-83.5@2x']:
            files[f'AppIcon-{name}.png'] = (icons / f'AppIcon-{name}.png').read_bytes()
        return files

    def verify(self, files, executable_mode=0o100755):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.ipa'
            with zipfile.ZipFile(path, 'w') as archive:
                for name, data in files.items():
                    entry = zipfile.ZipInfo(self.prefix + name)
                    entry.create_system = 3
                    entry.external_attr = (executable_mode if name == 'ABMMobile' else 0o100644) << 16
                    archive.writestr(entry, data)
            with contextlib.redirect_stdout(io.StringIO()):
                check_ipa(path)

    def test_committed_icon_catalog(self):
        check_icons()

    def test_complete_structural_fixture(self):
        self.verify(self.bundle())

    def test_missing_resources_rejected(self):
        for name in ['Assets.car', '_CodeSignature/CodeResources', 'AppIcon-ipad-76@2x.png']:
            with self.subTest(name=name):
                files = self.bundle()
                del files[name]
                with self.assertRaises(AssertionError):
                    self.verify(files)

    def test_high_density_renditions_can_live_only_in_asset_catalog(self):
        files = self.bundle()
        del files['AppIcon-iphone-60@3x.png']
        del files['AppIcon-ipad-83.5@2x.png']
        self.verify(files)

    def test_apple_png_chunk_before_image_header(self):
        data = self.bundle()['AppIcon-iphone-60@2x.png']
        payload = b'\x40\xa0\x60\x82'
        chunk = struct.pack('>I', len(payload)) + b'CgBI' + payload
        chunk += struct.pack('>I', zlib.crc32(b'CgBI' + payload))
        self.assertEqual(png_size(data[:8] + chunk + data[8:]), (120, 120))
        with self.assertRaises(AssertionError):
            png_size(data[:24])

    def test_incorrect_metadata_rejected(self):
        for key, value in [('MinimumOSVersion', '10.0'), ('CFBundleVersion', '1'),
                           ('CFBundleSupportedPlatforms', ['iPhoneSimulator']), ('CFBundleIcons', {})]:
            with self.subTest(key=key):
                files = self.bundle()
                info = plistlib.loads(files['Info.plist'])
                info[key] = value
                files['Info.plist'] = plistlib.dumps(info)
                with self.assertRaises((AssertionError, KeyError)):
                    self.verify(files)

    def test_device_executable_permissions_and_signature_required(self):
        with self.assertRaises(AssertionError):
            self.verify(self.bundle(), executable_mode=0o100644)
        for offset, value in [(40, 7), (44, 10 << 16), (64, 0)]:
            with self.subTest(offset=offset):
                files = self.bundle()
                binary = bytearray(files['ABMMobile'])
                struct.pack_into('<I', binary, offset, value)
                files['ABMMobile'] = binary
                with self.assertRaises(AssertionError):
                    self.verify(files)

    def test_do_not_ship_provisioning_profile(self):
        files = self.bundle()
        files['embedded.mobileprovision'] = b'private-signing-material'
        with self.assertRaises(AssertionError):
            self.verify(files)


if __name__ == '__main__':
    unittest.main()
