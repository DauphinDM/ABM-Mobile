# Third-party components

ABM Mobile and the copied or adapted ABM UI sources are MIT-licensed. See `LICENSE` and the provenance in `README.md`.

Android packages dynamically link Qt 6.8.3 under LGPLv3, GPLv3, or commercial terms as applicable. Qt source is available from https://download.qt.io/archive/qt/6.8/6.8.3/ and https://code.qt.io/. This project uses the open-source Qt distribution and doesn't modify Qt. Keep notices with redistributed builds, and comply with LGPL relinking and replacement requirements when you redistribute an APK.

TLS on Android uses OpenSSL **3.5.9 LTS**, Apache-2.0 licensed, built from https://github.com/openssl/openssl/releases/tag/openssl-3.5.9. The source archive SHA256 is `603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a`. `bin/fetch-android-openssl` has the complete build recipe and two small packaging adaptations: suffixed `_3` shared-library names for Qt's loader, and ordinary OpenSSL symbol-version names. This follows the packaging approach documented by KDAB at https://github.com/KDAB/android_openssl. No KDAB prebuilt libraries are distributed. The helper copies the matching source license and fetches Qt license texts into `android/assets/notices` for inclusion in the APK, along with this app's MIT license.

No game content, BeamNG or BeamMP binaries, proprietary car images, or desktop private keys are included.

The independent native iOS target uses Apple's system SwiftUI, Network, Security, and CryptoKit frameworks under the applicable Apple SDK terms. It doesn't link or package Qt, KDAB libraries, or OpenSSL. XcodeGen is a build-time tool, not an embedded runtime dependency.
