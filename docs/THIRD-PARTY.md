# Third-party components

ABM Mobile and copied/adapted ABM UI sources are MIT licensed; see `LICENSE` and the provenance in `README.md`.

Android packages dynamically link Qt 6.8.3 (LGPLv3/GPLv3 or commercial terms as applicable). Qt source is available from https://download.qt.io/archive/qt/6.8/6.8.3/ and https://code.qt.io/. This project uses the open-source Qt distribution and does not modify Qt. Keep notices with redistributed builds and comply with LGPL relinking/replacement requirements when redistributing an APK.

TLS on Android uses https://github.com/KDAB/android_openssl at pinned commit `b71f1470962019bd89534a2919f5925f93bc5779`, distributed under its repository license. Its OpenSSL libraries are Apache-2.0 licensed; matching source/build instructions live in that pinned repository and https://www.openssl.org/source/. The build helper copies/downloads these notices and Qt license texts into `android/assets/notices` for inclusion in the APK, together with this app's MIT license.

No game content, BeamNG/BeamMP binaries, proprietary car images or desktop private keys are included.
