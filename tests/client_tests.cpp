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
#include "remoteclient.h"

class ClientTests : public QObject {
    Q_OBJECT
private slots:
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
        pc->write("{\"kind\":\"ready\"}\n");
        const QJsonObject target{{"session","test"},{"vehicle",42}};
        const QJsonObject snapshot{{"kind","snapshot"},{"v",1},{"target",target},{"state",QJsonObject{{"connected",true},{"vehicle","Test car"}}},{"busy",false}};
        pc->write(QJsonDocument(snapshot).toJson(QJsonDocument::Compact)+'\n'); QTRY_VERIFY(client.connected());
        QCOMPARE(client.state().value("vehicle").toString(),QString("Test car")); QVERIFY(client.command("repair"));
        QTRY_VERIFY(pc->canReadLine()); const auto command=QJsonDocument::fromJson(pc->readLine()).object(); QCOMPARE(command.value("target").toObject(),target); QCOMPARE(command.value("seq").toInt(),1);
        QTRY_VERIFY_WITH_TIMEOUT(!client.connected(),4000); QVERIFY(client.state().isEmpty()); QVERIFY(!client.command("repair")); pc->deleteLater();
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
