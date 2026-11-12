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
    !exists($$PWD/vendor/android_openssl/openssl.pri): error("Run bin/fetch-android-openssl before building Android")
    include($$PWD/vendor/android_openssl/openssl.pri)
}
