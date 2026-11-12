#include "remoteclient.h"
#include <QJsonDocument>
#include <QJsonArray>
#include <QCryptographicHash>
#include <QRegularExpression>
#include <QGuiApplication>
#include <QClipboard>
#include <QHostAddress>

RemoteClient::RemoteClient(QObject *parent) : QObject(parent) {
    connect(&m_socket,&QSslSocket::encrypted,this,[this] {
        // The invitation pins the actual certificate, not an untrusted hostname.
        // No credentials or commands leave before this comparison succeeds.
        if (QString::fromLatin1(m_socket.peerCertificate().digest(QCryptographicHash::Sha256).toHex()) != m_pin) {
            close(tr("PC certificate does not match the pairing link. Connection refused.")); return;
        }
        m_verified = true;
        send({{"kind","pair"},{"v",1},{"secret",m_secret},{"device",m_name}}); m_secret.clear();
    });
    connect(&m_socket,&QSslSocket::readyRead,this,&RemoteClient::receive);
    connect(&m_socket,&QSslSocket::disconnected,this,[this] {
        m_approved = m_verified = false; m_snapshot = {}; m_secret.clear(); m_buffer.clear(); emit changed();
    });
    connect(&m_socket,&QSslSocket::errorOccurred,this,[this] { m_message = tr("Connection error: %1").arg(m_socket.errorString()); emit changed(); });
    m_watchdog.setInterval(250);
    connect(&m_watchdog,&QTimer::timeout,this,[this] {
        if (m_approved && m_age.isValid() && m_age.elapsed() > 2000) close(tr("PC stopped updating. Controls disabled; pair again."));
        else if (!m_approved && m_connectAge.isValid() && m_connectAge.elapsed() > 120000) close(tr("Pairing timed out."));
    });
    m_watchdog.start();
}
RemoteClient::~RemoteClient() { disconnect(&m_socket,nullptr,this,nullptr); m_socket.abort(); }
QVariantList RemoteClient::catalog() const { return connected() ? m_snapshot.value("catalog").toArray().toVariantList() : QVariantList{}; }
QVariantList RemoteClient::configs() const { return connected() ? m_snapshot.value("configs").toArray().toVariantList() : QVariantList{}; }
void RemoteClient::close(const QString &message) {
    m_approved = m_verified = false; m_snapshot = {}; m_secret.clear(); m_buffer.clear(); m_age.invalidate(); m_connectAge.invalidate();
    m_socket.abort(); m_message = message; emit changed();
}
void RemoteClient::disconnectPhone() { close(tr("Disconnected. Pair on the PC again to reconnect.")); }
void RemoteClient::pair(const QString &link, const QString &deviceName) {
    disconnectPhone();
    if (link.size() > 2048 || !link.startsWith("abm://pair/")) { m_message = tr("Paste a valid ABM pairing link from your PC."); emit changed(); return; }
    const auto decoded = QByteArray::fromBase64Encoding(link.mid(11).toLatin1(),QByteArray::Base64UrlEncoding | QByteArray::AbortOnBase64DecodingErrors);
    const auto data = QJsonDocument::fromJson(decoded.decoded).object();
    const QHostAddress host(data.value("host").toString()); bool ok = false; const auto ip = host.toIPv4Address(&ok);
    const bool local = ok && ((ip >> 24) == 10 || (ip >> 24) == 127 || (ip >> 16) == 0xc0a8 || (ip >> 20) == 0xac1);
    const QRegularExpression hex("^[0-9a-f]{64}$");
    const auto port = data.value("port").toDouble();
    if (!decoded || data.value("v").toInt() != 1 || !local || port < 1 || port > 65535 || int(port) != port
        || !hex.match(data.value("sha256").toString()).hasMatch() || !hex.match(data.value("secret").toString()).hasMatch()
        || deviceName.trimmed().isEmpty() || deviceName.size() > 64 || !QSslSocket::supportsSsl()) {
        m_message = tr("Invalid invitation, private address, device name, or missing TLS support."); emit changed(); return;
    }
    m_pin = data.value("sha256").toString(); m_secret = data.value("secret").toString(); m_name = deviceName.trimmed();
    m_sequence = 0; m_message = tr("Connecting securely to PC…"); m_connectAge.start();
    m_socket.setProtocol(QSsl::TlsV1_2OrLater); m_socket.setPeerVerifyMode(QSslSocket::VerifyNone);
    m_socket.connectToHostEncrypted(host.toString(),quint16(port)); emit changed();
}
void RemoteClient::send(const QJsonObject &data) {
    if (!m_verified || !m_socket.isEncrypted() || m_socket.bytesToWrite() > 32768) return;
    m_socket.write(QJsonDocument(data).toJson(QJsonDocument::Compact)+'\n');
}
void RemoteClient::receive() {
    if (!m_verified) { close(tr("Unverified connection refused.")); return; }
    m_buffer += m_socket.readAll();
    if (m_buffer.size() > 2*1024*1024) { close(tr("PC message exceeded the size limit.")); return; }
    while (m_buffer.contains('\n')) {
        const int index = m_buffer.indexOf('\n'); QJsonParseError error;
        const auto document = QJsonDocument::fromJson(m_buffer.left(index),&error); m_buffer.remove(0,index+1);
        const auto data = document.object(); const auto kind = data.value("kind").toString();
        if (error.error != QJsonParseError::NoError || !document.isObject()) { close(tr("Invalid PC response.")); return; }
        if (kind == "pending") m_message = tr("Approve this phone in Connect on the PC.");
        else if (kind == "ready") { m_approved = true; m_age.start(); m_message = tr("PC approved. Waiting for telemetry…"); }
        else if (kind == "snapshot" && m_approved && data.value("v").toInt() == 1) { m_snapshot = data; m_age.restart(); m_message = tr("Connected to PC. Game restrictions remain enforced."); }
        else if (kind == "receipt") m_message = data.value("message").toString().left(512);
        else if (kind == "error") { close(data.value("message").toString().left(512)); return; }
        else { close(tr("Unexpected PC response.")); return; }
        emit changed();
    }
}
bool RemoteClient::command(const QString &action, const QVariantMap &args) {
    if (!connected() || busy() || QJsonDocument(QJsonObject::fromVariantMap(args)).toJson().size() > 24000) {
        m_message = tr("Not connected, stale, busy, or command too large. Nothing was queued."); emit changed(); return false;
    }
    send({{"kind","command"},{"seq",double(++m_sequence)},{"action",action},{"args",QJsonObject::fromVariantMap(args)},{"target",m_snapshot.value("target")}});
    return true;
}
void RemoteClient::copyText(const QString &text) { if (text.size() <= 2048 && QGuiApplication::clipboard()) QGuiApplication::clipboard()->setText(text); }
