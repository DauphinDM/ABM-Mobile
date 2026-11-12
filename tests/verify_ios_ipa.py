"""Check distributable device-bundle structure, not Apple provisioning or ESign.

Only a real, correctly provisioned device install can validate that final step.
"""
import json
from pathlib import Path, PurePosixPath
import plistlib
import stat
import struct
import sys
import zipfile


def png_size(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'Invalid PNG'
    offset = 8
    while offset + 12 <= len(data):
        length, kind = struct.unpack_from('>I4s', data, offset)
        assert offset + length + 12 <= len(data), 'Truncated PNG chunk'
        if kind == b'IHDR':
            assert length == 13
            return struct.unpack_from('>II', data, offset + 8)
        offset += length + 12  # Xcode can add a CgBI chunk before IHDR.
    raise AssertionError('Missing PNG image header')


def check_icons():
    icons = Path(__file__).resolve().parent.parent / 'ios/ABMMobile/Assets.xcassets/AppIcon.appiconset'
    entries = json.loads((icons / 'Contents.json').read_text())['images']
    required = {('iphone', '60x60', '2x'), ('iphone', '60x60', '3x'),
                ('ipad', '76x76', '2x'), ('ipad', '83.5x83.5', '2x'),
                ('ios-marketing', '1024x1024', '1x')}
    assert required <= {(e['idiom'], e['size'], e['scale']) for e in entries}
    for entry in entries:
        data = (icons / entry['filename']).read_bytes()
        pixels = int(float(entry['size'].split('x')[0]) * int(entry['scale'][:-1]))
        assert png_size(data) == (pixels, pixels)
        assert data[25] == 2, 'Icons must be RGB, without alpha'
    print(f'Validated {len(entries)} opaque iPhone/iPad/marketing icons')


def check_ipa(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'Corrupt ZIP entry'
        names = set(archive.namelist())
        assert len(names) == len(archive.infolist()), 'Duplicate ZIP entry'
        assert all(not PurePosixPath(n).is_absolute() and '..' not in PurePosixPath(n).parts for n in names)
        assert all(not stat.S_ISLNK(i.external_attr >> 16) for i in archive.infolist())
        info_path = 'Payload/ABMMobile.app/Info.plist'
        prefix = 'Payload/ABMMobile.app/'
        info = plistlib.loads(archive.read(info_path))
        assert info['CFBundlePackageType'] == 'APPL'
        assert info['CFBundleIdentifier'] == 'io.github.dauphindm.abmmobile'
        assert info['CFBundleShortVersionString'] == '0.1.0'
        assert info['CFBundleVersion'] == '3'
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        assert info['MinimumOSVersion'] == '26.0'
        assert info['UIDeviceFamily'] == [1, 2]
        assert info['NSLocalNetworkUsageDescription']
        assert prefix + 'Assets.car' in names, 'Missing compiled asset catalog'
        assert prefix + '_CodeSignature/CodeResources' in names, 'Missing re-signing scaffold'
        assert prefix + 'embedded.mobileprovision' not in names, 'Do not ship a private provisioning profile'
        for key in ['CFBundleIcons', 'CFBundleIcons~ipad']:
            primary = info[key]['CFBundlePrimaryIcon']
            assert primary['CFBundleIconName'] == 'AppIcon'
            for stem in primary['CFBundleIconFiles']:
                assert any(n.startswith(prefix + stem) and n.endswith('.png') for n in names), stem
        pngs = [archive.read(n) for n in names if n.startswith(prefix) and n.endswith('.png')]
        dimensions = {png_size(data) for data in pngs}
        # actool emits these fallback PNGs; 180/167-pixel renditions can be
        # stored only inside Assets.car, not as separate files. check_icons()
        # validates their source sizes; never reject a valid compiled catalog
        # for not duplicating those renditions outside it.
        assert {(120, 120), (152, 152)} <= dimensions, f'Missing fallback icons: {dimensions}'
        executable_path = prefix + info['CFBundleExecutable']
        assert archive.getinfo(executable_path).external_attr >> 16 & stat.S_IXUSR
        binary = archive.read(executable_path)
        magic, cpu, _, filetype, count, command_bytes, _, _ = struct.unpack_from('<8I', binary)
        assert (magic, cpu, filetype) == (0xfeedfacf, 0x0100000c, 2), 'Not an arm64 executable'
        offset = 32
        platform_ok = signature_ok = False
        for _ in range(count):
            command, size = struct.unpack_from('<II', binary, offset)
            assert size >= 8 and offset + size <= 32 + command_bytes
            if command == 0x32:  # LC_BUILD_VERSION, platform iOS (not Simulator).
                platform, minimum, _, _ = struct.unpack_from('<4I', binary, offset + 8)
                assert platform == 2 and minimum == 26 << 16
                platform_ok = True
            elif command == 0x1d:  # LC_CODE_SIGNATURE, temporary ad-hoc scaffold.
                start, length = struct.unpack_from('<II', binary, offset + 8)
                assert length >= 12 and start + length <= len(binary)
                assert binary[start:start + 4] == b'\xfa\xde\x0c\xc0'
                signature_ok = True
            offset += size
        assert platform_ok and signature_ok, 'Missing device platform/signature load command'
        assert offset == 32 + command_bytes
        print(f'Validated device IPA: build {info["CFBundleVersion"]}, icons, arm64 iPhoneOS, re-signable bundle')


if __name__ == '__main__':
    check_icons()
    if len(sys.argv) == 2:
        check_ipa(Path(sys.argv[1]))
    else:
        assert len(sys.argv) == 1, 'Usage: verify_ios_ipa.py [device.ipa]'
