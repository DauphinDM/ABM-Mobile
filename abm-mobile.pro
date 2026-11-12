QT += core gui qml quick quickcontrols2 network
CONFIG += c++17
TARGET = abm-mobile
TEMPLATE = app
SOURCES += src/main.cpp src/remoteclient.cpp
HEADERS += src/remoteclient.h
RESOURCES += src/resources.qrc
android {
    ANDROID_PACKAGE_SOURCE_DIR = $$PWD/android
    ANDROID_MIN_SDK_VERSION = 28
    ANDROID_TARGET_SDK_VERSION = 35
    !exists($$PWD/vendor/openssl/arm64-v8a/libssl_3.so): error("Run bin/fetch-android-openssl before building Android")
    ANDROID_EXTRA_LIBS += $$PWD/vendor/openssl/arm64-v8a/libcrypto_3.so $$PWD/vendor/openssl/arm64-v8a/libssl_3.so
}
