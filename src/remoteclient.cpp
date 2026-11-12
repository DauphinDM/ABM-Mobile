#include "remoteclient.h"
#include <QJsonDocument>
#include <QJsonArray>
#include <QCryptographicHash>
#include <QRegularExpression>
#include <QGuiApplication>
#include <QClipboard>
#include <QHostAddress>
#include <QStandardPaths>
#include <QSaveFile>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QBuffer>
#include <QImageReader>

RemoteClient::RemoteClient(QObject *parent) : QObject(parent) {
    m_store=qEnvironmentVariable("ABM_MOBILE_CONFIG_DIR",QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))+"/pc.json";
    QFile saved(m_store);
    if (saved.open(QIODevice::ReadOnly) && saved.size()<=4096) {
        const auto value=QJsonDocument::fromJson(saved.readAll()).object();
        const QRegularExpression hex("^[0-9a-f]{64}$"),id("^[0-9a-f]{32}$");
        const QHostAddress host(value.value("host").toString()); bool ok=false; const auto ip=host.toIPv4Address(&ok);
        if (ok && ((ip>>24)==10 || (ip>>24)==127 || (ip>>16)==0xc0a8 || (ip>>20)==0xac1)
            && hex.match(value.value("pin").toString()).hasMatch() && hex.match(value.value("token").toString()).hasMatch()
            && id.match(value.value("id").toString()).hasMatch() && value.value("port").toInt()>0 && value.value("port").toInt()<=65535) m_remembered=value;
    }
    connect(&m_socket,&QSslSocket::encrypted,this,[this] {
        // The invitation pins the actual certificate, not an untrusted hostname.
        // No credentials or commands leave before this comparison succeeds.
        if (QString::fromLatin1(m_socket.peerCertificate().digest(QCryptographicHash::Sha256).toHex()) != m_pin) {
            close(tr("PC certificate does not match the pairing link. Connection refused.")); return;
        }
        m_verified = true;
        m_socket.setSocketOption(QAbstractSocket::LowDelayOption,1);
        send(m_hello); m_hello={}; m_secret.clear();
    });
    connect(&m_socket,&QSslSocket::readyRead,this,&RemoteClient::receive);
    connect(&m_socket,&QSslSocket::disconnected,this,[this] {
        m_approved = m_verified = false; m_snapshot = {}; m_secret.clear(); m_buffer.clear(); emit changed(); emit libraryChanged();
    });
    connect(&m_socket,&QSslSocket::errorOccurred,this,[this] { m_message = tr("Connection error: %1").arg(m_socket.errorString()); emit changed(); });
    m_watchdog.setInterval(250);
    connect(&m_watchdog,&QTimer::timeout,this,[this] {
        if (m_approved && m_age.isValid() && m_age.elapsed() > 2000) close(tr("PC stopped updating. Controls disabled; pair again."));
        else if (!m_approved && m_connectAge.isValid() && m_connectAge.elapsed() > 120000) close(tr("Pairing timed out."));
        else if (connected() && (!m_ping.isValid() || m_ping.elapsed()>2000)) { m_ping.start(); send({{"kind","ping"},{"stamp",double(++m_pingSerial)}}); }
    });
    m_watchdog.start();
}
RemoteClient::~RemoteClient() { disconnect(&m_socket,nullptr,this,nullptr); m_socket.abort(); }
QVariantList RemoteClient::decorate(const QJsonArray &items) const {
    QVariantList result;
    for (const auto &entry:items) { auto item=entry.toObject().toVariantMap(); item.insert("thumbnail",m_images.value(item.value("photo").toString())); item.insert("modelThumbnail",m_images.value(item.value("modelPhoto").toString())); result.append(item); }
    return result;
}
QVariantList RemoteClient::catalog() const { return connected() ? decorate(m_snapshot.value("catalog").toArray()) : QVariantList{}; }
QVariantList RemoteClient::configs() const { return connected() ? decorate(m_snapshot.value("configs").toArray()) : QVariantList{}; }
void RemoteClient::close(const QString &message) {
    m_approved = m_verified = false; m_snapshot = {}; m_secret.clear(); m_buffer.clear(); m_age.invalidate(); m_connectAge.invalidate();
    m_hello={}; m_images.clear(); m_imageRequests.clear(); m_imageFlight.clear(); m_imageQueue.clear(); m_ping.invalidate(); m_roundTrip=-1;
    m_storageWarning.clear(); m_pingSerial=0;
    m_socket.abort(); m_message = message; emit changed(); emit libraryChanged();
}
void RemoteClient::disconnectPhone() { close(tr("Disconnected. Reconnect to the saved PC, or pair a new device.")); }
void RemoteClient::reconnectPC() {
    if (m_remembered.isEmpty()) return;
    const auto saved=m_remembered; disconnectPhone();
    open(saved,{{"kind","resume"},{"v",1},{"id",saved.value("id")},{"token",saved.value("token")}});
}
void RemoteClient::forgetPC() {
    disconnectPhone();
    if (QFile::exists(m_store) && !QFile::remove(m_store)) { m_message=tr("Cannot remove saved PC credentials. Check app storage."); emit changed(); return; }
    m_remembered={}; m_message=tr("Saved PC forgotten. Revoke the device on PC too if needed."); emit changed();
}
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
    open({{"host",host.toString()},{"port",int(port)},{"pin",data.value("sha256")},{"name",deviceName.trimmed()}},
        {{"kind","pair"},{"v",1},{"secret",data.value("secret")},{"device",deviceName.trimmed()}});
}
void RemoteClient::open(const QJsonObject &endpoint, const QJsonObject &hello) {
    m_endpoint=endpoint; m_hello=hello; m_pin=endpoint.value("pin").toString();
    m_sequence = 0; m_message = tr("Connecting securely to PC…"); m_connectAge.start();
    m_socket.setProtocol(QSsl::TlsV1_2OrLater); m_socket.setPeerVerifyMode(QSslSocket::VerifyNone);
    m_socket.connectToHostEncrypted(endpoint.value("host").toString(),quint16(endpoint.value("port").toInt())); emit changed();
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
        else if (kind=="trusted" && !m_approved) {
            const QRegularExpression token("^[0-9a-f]{64}$"),id("^[0-9a-f]{32}$");
            if (!token.match(data.value("token").toString()).hasMatch() || !id.match(data.value("id").toString()).hasMatch()) { close(tr("Invalid saved-device credential.")); return; }
            auto saved=m_endpoint; saved.insert("id",data.value("id")); saved.insert("token",data.value("token"));
            const auto directory=QFileInfo(m_store).absolutePath(); QDir().mkpath(directory); QFile::setPermissions(directory,QFileDevice::ReadOwner|QFileDevice::WriteOwner|QFileDevice::ExeOwner);
            QSaveFile file(m_store);
            bool retained=false;
            if (file.open(QIODevice::WriteOnly)) { file.setPermissions(QFileDevice::ReadOwner|QFileDevice::WriteOwner); const auto bytes=QJsonDocument(saved).toJson(QJsonDocument::Compact); if (file.write(bytes)==bytes.size() && file.commit()) { m_remembered=saved; retained=true; } }
            if (!retained) m_storageWarning=tr("Connected, but app storage could not remember this PC. Pairing will be required next time.");
        }
        else if (kind == "ready") { m_approved = true; m_age.start(); m_message = m_storageWarning.isEmpty() ? tr("PC approved. Waiting for telemetry…") : m_storageWarning; }
        else if (kind == "snapshot" && m_approved && data.value("v").toInt() == 1) {
            auto next=data; for (const auto key:{"catalog","configs","configsModel"}) if (!next.contains(key)) next.insert(key,m_snapshot.value(key));
            const bool library=next.value("catalog")!=m_snapshot.value("catalog") || next.value("configs")!=m_snapshot.value("configs") || next.value("configsModel")!=m_snapshot.value("configsModel");
            m_snapshot=next; m_age.restart(); if (m_message==tr("PC approved. Waiting for telemetry…")) m_message=tr("Connected to PC. Game restrictions remain enforced.");
            if (library) emit libraryChanged();
        }
        else if (kind=="pong" && m_approved) { if (m_ping.isValid() && data.value("stamp").toDouble(-1)==double(m_pingSerial)) m_roundTrip=int(m_ping.elapsed()); }
        else if (kind=="thumbnail" && m_approved) {
            const auto id=data.value("id").toString(), encoded=data.value("jpeg").toString();
            if (!m_imageFlight.remove(id) || encoded.size()>90000) { close(tr("Invalid thumbnail response.")); return; }
            auto bytes=QByteArray::fromBase64(encoded.toLatin1()); QBuffer buffer(&bytes); buffer.open(QIODevice::ReadOnly); QImageReader reader(&buffer,"JPEG");
            const auto size=reader.size();
            const bool valid=bytes.size()<=65536 && size.isValid() && size.width()<=320 && size.height()<=200 && !reader.read().isNull();
            if (m_images.size()>=128) { const auto old=m_images.begin().key(); m_images.remove(old); m_imageRequests.remove(old); }
            m_images.insert(id,valid?"data:image/jpeg;base64,"+encoded:QString());
            pumpImages(); emit libraryChanged();
        }
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
void RemoteClient::requestThumbnail(const QVariantMap &item) {
    if (!connected()) return;
    for (const auto key:{"photo","modelPhoto"}) { const auto id=item.value(key).toString();
        if (m_imageRequests.size()<512 && QRegularExpression("^[0-9a-f]{64}$").match(id).hasMatch() && !m_imageRequests.contains(id)) { m_imageRequests.insert(id); m_imageQueue.enqueue(id); }
    }
    pumpImages();
}
void RemoteClient::pumpImages() {
    while (connected() && m_imageFlight.size()<8 && !m_imageQueue.isEmpty()) {
        const auto id=m_imageQueue.dequeue(); m_imageFlight.insert(id); send({{"kind","thumbnail"},{"id",id}});
    }
}
