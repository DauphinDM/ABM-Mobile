import Foundation
import Combine
import UIKit

private final class UpdateRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class UpdateChecker: ObservableObject {
    struct Release: Equatable { let version: String; let url: URL }
    @Published var automatic: Bool { didSet { defaults.set(automatic, forKey: "updates.automatic") } }
    @Published var previews: Bool { didSet { defaults.set(previews, forKey: "updates.previews"); release=nil } }
    @Published private(set) var busy=false
    @Published private(set) var release: Release?
    @Published private(set) var message="Enable automatic checks or choose Check now. Checks contact GitHub."
    let current: String
    private let defaults: UserDefaults
    private let session: URLSession
    private var lastCheck: Date?

    init(defaults: UserDefaults = .standard, current: String? = nil) {
        self.defaults=defaults
        self.current=current ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        automatic=defaults.bool(forKey: "updates.automatic"); previews=defaults.bool(forKey: "updates.previews")
        lastCheck=defaults.object(forKey: "updates.lastCheck") as? Date
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=20; config.timeoutIntervalForResource=30
        session=URLSession(configuration: config, delegate: UpdateRedirectPolicy(), delegateQueue: nil)
    }
    static func numbers(_ text: String) -> [Int]? {
        let parts=text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count==3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) }) else { return nil }
        let values=parts.compactMap { Int($0) }; return values.count==3 ? values : nil
    }
    static func select(_ data: Data, current: String, previews: Bool) -> Release? {
        guard data.count<=1_048_576, let entries=(try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], let installed=numbers(current) else { return nil }
        var highest=installed
        var result: Release?
        for entry in entries.prefix(100) {
            guard entry["draft"] as? Bool != true, let tag=entry["tag_name"] as? String,
                  tag.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+(?:-(?:preview|beta|rc)\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  previews || (entry["prerelease"] as? Bool != true && !tag.contains("-")) else { continue }
            let version=String(tag.dropFirst().split(separator: "-")[0])
            guard let number=numbers(version), highest.lexicographicallyPrecedes(number),
                  let page=entry["html_url"] as? String,
                  page=="https://github.com/DauphinDM/ABM-Mobile/releases/tag/"+tag,
                  let url=URL(string: page) else { continue }
            highest=number; result=Release(version: version, url: url)
        }
        return result
    }
    func monitor() async {
        while !Task.isCancelled {
            await checkIfDue()
            do { try await Task.sleep(for: .seconds(3600)) } catch { return }
        }
    }
    func checkIfDue() async {
        if automatic && (lastCheck == nil || Date().timeIntervalSince(lastCheck!)>=86400) { await check() }
    }
    func check() async {
        guard !busy else { return }
        busy=true; release=nil; message="Checking official GitHub releases…"
        defer { busy=false }
        lastCheck=Date(); defaults.set(lastCheck, forKey: "updates.lastCheck")
        var request=URLRequest(url: URL(string: "https://api.github.com/repos/DauphinDM/ABM-Mobile/releases?per_page=20")!)
        request.setValue("ABM-Mobile-release-updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response)=try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode==200 else { throw URLError(.badServerResponse) }
            var data=Data()
            for try await byte in bytes {
                guard data.count<1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
                data.append(byte)
            }
            guard (try? JSONSerialization.jsonObject(with: data)) is [[String: Any]] else { throw URLError(.cannotParseResponse) }
            release=Self.select(data, current: current, previews: previews)
            message=release.map { "Update \($0.version) is available." } ?? "No newer published release in this channel. CI artifacts are not updates."
        } catch { message="Update check failed. Check your connection or try later; GitHub rate limits may apply." }
    }
    func openRelease() {
        guard let release else { return }
        UIApplication.shared.open(release.url) { [weak self] opened in
            Task { @MainActor [weak self] in if !opened { self?.message="Could not open the release page." } }
        }
    }
}
