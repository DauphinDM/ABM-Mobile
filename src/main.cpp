#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QPalette>
#include "remoteclient.h"
#include "appupdates.h"
int main(int argc, char **argv) {
    QGuiApplication app(argc,argv);
    app.setApplicationName("ABM Mobile"); app.setOrganizationName("ABM"); app.setApplicationVersion("0.2.0");
    QQuickStyle::setStyle("MotorsportGlass"); QQuickStyle::setFallbackStyle("Basic");
    QPalette palette; palette.setColor(QPalette::Window,QColor("#10141b")); palette.setColor(QPalette::WindowText,QColor("#edf1f7"));
    palette.setColor(QPalette::Text,QColor("#edf1f7")); palette.setColor(QPalette::ButtonText,QColor("#edf1f7"));
    palette.setColor(QPalette::Highlight,QColor("#ffd60a")); palette.setColor(QPalette::Base,QColor("#151a22")); app.setPalette(palette);
    RemoteClient client;
    AppUpdates updates(true,app.applicationVersion());
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("remote",&client);
    engine.rootContext()->setContextProperty("appUpdates",&updates);
    engine.rootContext()->setContextProperty("theme",QVariantMap{{"accent","#ffd60a"},{"radius",6}});
    engine.load(QUrl("qrc:/Main.qml")); if (engine.rootObjects().isEmpty()) return 1;
    const auto args = app.arguments();
    if (!args.contains("--screenshot")) updates.start();
    if (args.contains("--screenshot")) {
        const auto path = args.value(args.indexOf("--screenshot")+1);
        QTimer::singleShot(800,&app,[&engine,&app,path] { auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); app.exit(window && window->grabWindow().save(path) ? 0 : 1); });
    }
    return app.exec();
}
