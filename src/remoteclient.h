#pragma once
#include <QObject>
#include <QSslSocket>
#include <QTimer>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QVariantMap>
#include <QSet>
#include <QQueue>

class RemoteClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
    Q_PROPERTY(QVariantMap target READ target NOTIFY changed)
    Q_PROPERTY(QVariantList catalog READ catalog NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList configs READ configs NOTIFY libraryChanged)
    Q_PROPERTY(QString configsModel READ configsModel NOTIFY libraryChanged)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QString actionMessage READ actionMessage NOTIFY changed)
    Q_PROPERTY(bool remembered READ remembered NOTIFY changed)
    Q_PROPERTY(int roundTripMs READ roundTripMs NOTIFY changed)
public:
    explicit RemoteClient(QObject *parent = nullptr);
    ~RemoteClient() override;
    bool connected() const { return m_approved && m_age.isValid() && m_age.elapsed() <= 2000; }
    bool busy() const { return !connected() || m_snapshot.value("busy").toBool(); }
    QVariantMap state() const { return connected() ? m_snapshot.value("state").toObject().toVariantMap() : QVariantMap{}; }
    QVariantMap target() const { return connected() ? m_snapshot.value("target").toObject().toVariantMap() : QVariantMap{}; }
    QVariantList catalog() const;
    QVariantList configs() const;
    QString configsModel() const { return connected() ? m_snapshot.value("configsModel").toString() : QString(); }
    QString message() const { return m_message; }
    QString actionMessage() const { return m_snapshot.value("actionMessage").toString(); }
    bool remembered() const { return !m_remembered.isEmpty(); }
    int roundTripMs() const { return m_roundTrip; }
    Q_INVOKABLE void pair(const QString &link, const QString &deviceName);
    Q_INVOKABLE void disconnectPhone();
    Q_INVOKABLE bool command(const QString &action, const QVariantMap &args = {});
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE void reconnectPC();
    Q_INVOKABLE void forgetPC();
    Q_INVOKABLE void requestThumbnail(const QVariantMap &item);
signals:
    void changed();
    void libraryChanged();
private:
    void receive();
    void send(const QJsonObject &data);
    void close(const QString &message);
    void open(const QJsonObject &endpoint, const QJsonObject &hello);
    void pumpImages();
    QVariantList decorate(const QJsonArray &items) const;
    QSslSocket m_socket;
    QTimer m_watchdog;
    QElapsedTimer m_age, m_connectAge;
    QJsonObject m_snapshot;
    QByteArray m_buffer;
    QString m_pin, m_secret, m_name, m_message;
    qint64 m_sequence = 0;
    bool m_approved = false, m_verified = false;
    QJsonObject m_hello, m_endpoint, m_remembered;
    QHash<QString,QString> m_images;
    QSet<QString> m_imageRequests;
    QSet<QString> m_imageFlight;
    QQueue<QString> m_imageQueue;
    QString m_store, m_storageWarning;
    QElapsedTimer m_ping;
    int m_roundTrip=-1;
    qint64 m_pingSerial=0;
};
