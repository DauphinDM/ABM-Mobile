#include <QtTest>
#include <QTemporaryDir>
#include <QProcess>
#include <QFile>
#include <QSslServer>
#include <QSslKey>
#include <QJsonDocument>
#include <QCryptographicHash>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QQuickItem>
#include <QBuffer>
#include <QImage>
#include "remoteclient.h"
#include "update_test_cases.h"

class ClientTests : public QObject {
    Q_OBJECT
    QTemporaryDir storage;
private slots:
    void updateReleaseSelectionIsScoped() { UpdateTests::selection(); }
    void updateDownloadsAreBoundedAndVerified() { UpdateTests::transfers(); }
    void updatePanelUsesExplicitCheck() { UpdateTests::panel(); }
    void init() { QVERIFY(storage.isValid()); qputenv("ABM_MOBILE_CONFIG_DIR",storage.filePath(QString::fromLatin1(QTest::currentTestFunction())).toUtf8()); }
    void validatesInvitationsAndNeverQueuesOffline() {
        RemoteClient client;
        for (const auto &link : {QString(),QString("https://example.com"),QString("abm://pair/bad"),QString(3000,'x')}) {
            client.pair(link,"Test phone"); QVERIFY(!client.connected()); QVERIFY(!client.command("repair"));
        }
    }
    void pinnedTlsApprovalCommandsStalenessAndWrongCertificate() {
        QTemporaryDir dir; QVERIFY(dir.isValid());
        const auto certPath=dir.filePath("cert.pem"), keyPath=dir.filePath("key.pem");
        QProcess openssl; openssl.start("openssl",{"req","-x509","-newkey","rsa:2048","-sha256","-nodes","-days","1","-subj","/CN=test","-keyout",keyPath,"-out",certPath});
        QVERIFY(openssl.waitForFinished(15000)); QCOMPARE(openssl.exitCode(),0);
        QFile certFile(certPath),keyFile(keyPath); QVERIFY(certFile.open(QIODevice::ReadOnly)); QVERIFY(keyFile.open(QIODevice::ReadOnly));
        const QSslCertificate certificate(certFile.readAll()); const QSslKey key(keyFile.readAll(),QSsl::Rsa);
        auto config=QSslConfiguration::defaultConfiguration(); config.setLocalCertificate(certificate); config.setPrivateKey(key); config.setPeerVerifyMode(QSslSocket::VerifyNone);
        QSslServer server; server.setSslConfiguration(config); QVERIFY(server.listen(QHostAddress::LocalHost,0));
        QJsonObject invitation{{"v",1},{"host","127.0.0.1"},{"port",server.serverPort()},{"sha256",QString::fromLatin1(certificate.digest(QCryptographicHash::Sha256).toHex())},{"secret",QString(64,'a')}};
        auto link=[&] { return "abm://pair/"+QString::fromLatin1(QJsonDocument(invitation).toJson(QJsonDocument::Compact).toBase64(QByteArray::Base64UrlEncoding|QByteArray::OmitTrailingEquals)); };
        RemoteClient client; client.pair(link(),"Test phone"); QTRY_VERIFY(server.hasPendingConnections());
        auto *pc=qobject_cast<QSslSocket *>(server.nextPendingConnection()); QVERIFY(pc);
        QTRY_VERIFY(pc->canReadLine()); const auto hello=QJsonDocument::fromJson(pc->readLine()).object(); QCOMPARE(hello.value("secret"),invitation.value("secret"));
        QVERIFY(!client.connected()); QVERIFY(!client.command("repair"));
        pc->write("{\"kind\":\"pending\"}\n"); QTRY_VERIFY(client.message().contains("Approve"));
        const QJsonObject trusted{{"kind","trusted"},{"id",QString(32,'b')},{"token",QString(64,'c')}};
        pc->write(QJsonDocument(trusted).toJson(QJsonDocument::Compact)+'\n');
        QTRY_VERIFY(client.remembered());
        pc->write("{\"kind\":\"ready\"}\n");
        const QJsonObject target{{"session","test"},{"vehicle",42}};
        const QJsonObject snapshot{{"kind","snapshot"},{"v",1},{"target",target},{"state",QJsonObject{{"connected",true},{"vehicle","Test car"},{"vehicleId",42},{"vehicleOwned",true},{"controlsAvailable",true},{"sandboxAllowed",true},{"map","test_map"},{"telemetry",QJsonObject{{"speed",0}}},{"capabilities",QJsonObject{{"power",true}}}}},{"busy",false}};
        pc->write(QJsonDocument(snapshot).toJson(QJsonDocument::Compact)+'\n'); QTRY_VERIFY(client.connected());
        QCOMPARE(client.state().value("vehicle").toString(),QString("Test car"));
        {
            QQmlApplicationEngine engine;
            engine.rootContext()->setContextProperty("remote",&client);
            engine.rootContext()->setContextProperty("theme",QVariantMap{{"accent","#ffd60a"},{"radius",6}});
            engine.load(QUrl("qrc:/Main.qml")); QVERIFY(!engine.rootObjects().isEmpty());
            auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
            window->setProperty("page",1); window->requestActivate(); QVERIFY(QTest::qWaitForWindowExposed(window)); QTest::qWait(60);
            auto *input=window->findChild<QQuickItem *>("powerInput"); auto *done=window->findChild<QQuickItem *>("dismissKeyboard");
            auto *apply=window->findChild<QQuickItem *>("applyPower"); QVERIFY(input && done && apply);
            input->forceActiveFocus(); input->setProperty("text","200"); QTRY_VERIFY(done->isVisible());
            QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,done->mapToScene(QPointF(done->width()/2,done->height()/2)).toPoint());
            QTRY_VERIFY(!input->hasActiveFocus()); QVERIFY(apply->isEnabled());
            QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,apply->mapToScene(QPointF(apply->width()/2,apply->height()/2)).toPoint());
            QJsonObject command;
            auto readCommand=[&] {
                while (command.isEmpty() && pc->canReadLine()) {
                    const auto value=QJsonDocument::fromJson(pc->readLine()).object();
                    if (value.value("kind")=="ping") pc->write(QJsonDocument(QJsonObject{{"kind","pong"},{"stamp",value.value("stamp")}}).toJson(QJsonDocument::Compact)+'\n');
                    else command=value;
                }
                return !command.isEmpty();
            };
            QTRY_VERIFY(readCommand());
            QCOMPARE(command.value("target").toObject(),target); QCOMPARE(command.value("seq").toInt(),1);
            QCOMPARE(command.value("action").toString(),QString("power")); QCOMPARE(command.value("args").toObject().value("value").toDouble(),2.0);
        } // Actual Apply dispatched without an intermediate confirmation dialog.
        QTRY_VERIFY_WITH_TIMEOUT(!client.connected(),4000); QVERIFY(client.state().isEmpty()); QVERIFY(!client.command("repair")); pc->deleteLater();
        client.reconnectPC(); QTRY_VERIFY(server.hasPendingConnections());
        auto *resumed=qobject_cast<QSslSocket *>(server.nextPendingConnection()); QVERIFY(resumed);
        QTRY_VERIFY(resumed->canReadLine()); const auto resume=QJsonDocument::fromJson(resumed->readLine()).object();
        QCOMPARE(resume.value("kind").toString(),QString("resume")); QCOMPARE(resume.value("token"),trusted.value("token"));
        QVERIFY(!resume.contains("secret")); QVERIFY(!resume.contains("device"));
        resumed->write("{\"kind\":\"ready\"}\n");
        QJsonArray cars;
        for (int i=0;i<40;++i) cars.append(QJsonObject{{"id",QString::number(i)},{"photo",QString::number(i,16).rightJustified(64,'0')}});
        auto library=snapshot; library.insert("catalog",cars); library.insert("configs",QJsonArray{}); library.insert("configsModel","");
        resumed->write(QJsonDocument(library).toJson(QJsonDocument::Compact)+'\n'); QTRY_COMPARE(client.catalog().size(),40);
        QSignalSpy libraryChanges(&client,&RemoteClient::libraryChanged);
        resumed->write(QJsonDocument(snapshot).toJson(QJsonDocument::Compact)+'\n'); QTest::qWait(30);
        QCOMPARE(client.catalog().size(),40); QCOMPARE(libraryChanges.count(),0); // Telemetry does not rebuild Garage delegates.
        for (const auto &car:cars) client.requestThumbnail(car.toObject().toVariantMap());
        QTRY_VERIFY(resumed->canReadLine()); QTest::qWait(50);
        QJsonArray requests;
        auto collect=[&] {
            while (resumed->canReadLine()) {
                const auto message=QJsonDocument::fromJson(resumed->readLine()).object();
                if (message.value("kind")=="thumbnail") requests.append(message);
                else if (message.value("kind")=="ping") resumed->write(QJsonDocument(QJsonObject{{"kind","pong"},{"stamp",message.value("stamp")}}).toJson(QJsonDocument::Compact)+'\n');
            }
        };
        collect(); QCOMPARE(requests.size(),8); // Never overflow the PC's bounded image queue.
        QImage image(32,20,QImage::Format_RGB32); image.fill(Qt::yellow); QByteArray jpeg; QBuffer buffer(&jpeg); buffer.open(QIODevice::WriteOnly); QVERIFY(image.save(&buffer,"JPEG"));
        int replies=0;
        auto respond=[&] {
            collect();
            while (!requests.isEmpty()) {
                const auto request=requests.takeAt(0).toObject();
                resumed->write(QJsonDocument(QJsonObject{{"kind","thumbnail"},{"id",request.value("id")},{"jpeg",QString::fromLatin1(jpeg.toBase64())}}).toJson(QJsonDocument::Compact)+'\n'); ++replies;
            }
            return replies==40;
        };
        QTRY_VERIFY(respond()); QTRY_VERIFY(client.catalog().last().toMap().value("thumbnail").toString().startsWith("data:image/jpeg;base64,"));
        QCOMPARE(client.catalog().first().toMap().value("thumbnail").toString(),client.catalog().last().toMap().value("thumbnail").toString());
        { RemoteClient loaded; QVERIFY(loaded.remembered()); }
        client.forgetPC(); QVERIFY(!client.remembered()); QVERIFY(!client.connected());
        { RemoteClient loaded; QVERIFY(!loaded.remembered()); }
        resumed->deleteLater();
        invitation.insert("sha256",QString(64,'0')); client.pair(link(),"Test phone");
        QTRY_VERIFY(client.message().contains("certificate")); QVERIFY(!client.connected());
        QTest::qWait(100);
        while (server.hasPendingConnections()) { auto *socket=server.nextPendingConnection(); QVERIFY(socket->readAll().isEmpty()); socket->deleteLater(); }
    }
    void allPagesLoadWithoutWarningsAtPhoneSizes() {
        RemoteClient client; QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("remote",&client);
        engine.rootContext()->setContextProperty("theme",QVariantMap{{"accent","#ffd60a"},{"radius",6}});
        QStringList warnings;
        connect(&engine,&QQmlEngine::warnings,this,[&](const QList<QQmlError> &errors) { for (const auto &error:errors) warnings << error.toString(); });
        engine.load(QUrl("qrc:/Main.qml")); QVERIFY(!engine.rootObjects().isEmpty());
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first()); QVERIFY(window);
        for (const auto &size:{QSize(320,600),QSize(412,860),QSize(800,600)}) {
            window->resize(size);
            for (int page=0;page<5;++page) { window->setProperty("page",page); QTest::qWait(50); QVERIFY(!window->grabWindow().isNull()); }
        }
        QVERIFY2(warnings.isEmpty(),qPrintable(warnings.join('\n')));
    }
};
int main(int argc,char **argv) {
    QGuiApplication app(argc,argv); QQuickStyle::setStyle("MotorsportGlass"); QQuickStyle::setFallbackStyle("Basic");
    ClientTests test; return QTest::qExec(&test,argc,argv);
}
#include "client_tests.moc"
