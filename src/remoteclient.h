#pragma once
#include <QObject>
#include <QSslSocket>
#include <QTimer>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QVariantMap>

class RemoteClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
    Q_PROPERTY(QVariantMap target READ target NOTIFY changed)
    Q_PROPERTY(QVariantList catalog READ catalog NOTIFY changed)
    Q_PROPERTY(QVariantList configs READ configs NOTIFY changed)
    Q_PROPERTY(QString configsModel READ configsModel NOTIFY changed)
    Q_PROPERTY(QString message READ message NOTIFY changed)
    Q_PROPERTY(QString actionMessage READ actionMessage NOTIFY changed)
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
    Q_INVOKABLE void pair(const QString &link, const QString &deviceName);
    Q_INVOKABLE void disconnectPhone();
    Q_INVOKABLE bool command(const QString &action, const QVariantMap &args = {});
    Q_INVOKABLE void copyText(const QString &text);
signals:
    void changed();
private:
    void receive();
    void send(const QJsonObject &data);
    void close(const QString &message);
    QSslSocket m_socket;
    QTimer m_watchdog;
    QElapsedTimer m_age, m_connectAge;
    QJsonObject m_snapshot;
    QByteArray m_buffer;
    QString m_pin, m_secret, m_name, m_message;
    qint64 m_sequence = 0;
    bool m_approved = false, m_verified = false;
};
