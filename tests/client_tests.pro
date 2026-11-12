QT += core gui qml quick quickcontrols2 network testlib
CONFIG += c++17 testcase
TARGET = client_tests
TEMPLATE = app
INCLUDEPATH += ../src
SOURCES += client_tests.cpp ../src/remoteclient.cpp
HEADERS += ../src/remoteclient.h
RESOURCES += ../src/resources.qrc
