import AppKit
import CryptoKit

// Updates come only from this repo's GitHub releases and install only if the Ed25519 signature made offline with the
// release key verifies (private key: ~/.config/taskmanager/signing.key, never committed). Same model as Claude Usage.

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
}

struct UpdateInfo {
    let version: String
    let notes: [String]
    var dmgURL: URL?
    var sha256: String?
    var sigURL: URL?
}

enum UpdateStatus {
    case idle, checking, upToDate
    case available(UpdateInfo)
    case installing(String, Double)
    case failed(String)
}

private func versionParts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 } }

/// True when version `a` is newer than `b` ("major.minor.patch").
func isNewer(_ a: String, than b: String) -> Bool {
    let x = versionParts(a), y = versionParts(b)
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

enum Updater {
    static let repo = "Ol775/macos-task-manager"
    static let bundleID = "io.github.ol775.taskmanager"
    static let publicKey = "t9AtZEDfkTFRMwxg9/UdptZnoeDuyeJwGzz0Cq8+vFw="

    static func isPlainVersion(_ v: String) -> Bool {
        v.range(of: #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#, options: .regularExpression) != nil
    }

    /// What the release key signs: label + version + disk image bytes, so an older signed image can't pass as a newer one.
    static func signedMessage(version: String, dmg: Data) -> Data { Data("taskmanager-update\nv\(version)\n".utf8) + dmg }

    static func isAllowedRedirectHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "github.com" || h.hasSuffix(".githubusercontent.com")
    }

    static func isTrustedAsset(_ u: URL) -> Bool {
        u.scheme == "https" && u.host == "github.com" && u.path.hasPrefix("/\(repo)/releases/download/")
    }

    static func verifySignature(_ data: Data, base64Signature: String, publicKey key: String = Updater.publicKey) -> Bool {
        guard let k = Data(base64Encoded: key), let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
              let sig = Data(base64Encoded: base64Signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return pub.isValidSignature(sig, for: data)
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        static let maxBytes: Int64 = 100_000_000
        var onProgress: (Double) -> Void = { _ in }
        var location: URL?, status = 0
        let done = DispatchSemaphore(value: 0)
        func urlSession(_ s: URLSession, task: URLSessionTask, willPerformHTTPRedirection r: HTTPURLResponse, newRequest req: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(req.url?.scheme == "https" && Updater.isAllowedRedirectHost(req.url?.host) ? req : nil)
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
            if w > Self.maxBytes || e > Self.maxBytes { t.cancel(); return }
            if e > 0 { onProgress(min(1, Double(w) / Double(e))) }
        }
        func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
            status = (t.response as? HTTPURLResponse)?.statusCode ?? 0
            let keep = FileManager.default.temporaryDirectory.appendingPathComponent("tm-\(UUID().uuidString)")
            if (try? FileManager.default.moveItem(at: loc, to: keep)) != nil { location = keep }
        }
        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { done.signal() }
    }

    private static func fetchData(_ url: URL, timeout: TimeInterval, accept: String? = nil) -> Data? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let accept { req.setValue(accept, forHTTPHeaderField: "Accept") }
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        session.dataTask(with: req) { d, r, _ in
            if (r as? HTTPURLResponse)?.statusCode == 200, let d, d.count < 1_000_000 { out = d }
            sem.signal()
        }.resume()
        sem.wait(); session.finishTasksAndInvalidate()
        return out
    }

    /// Blocking: call from a background queue.
    static func check(installed: String = AppInfo.version) -> UpdateStatus {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest"),
              let data = fetchData(url, timeout: 15, accept: "application/vnd.github+json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            return .failed("Couldn’t find a release on GitHub. Check your connection and try again.")
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isPlainVersion(version) else { return .failed("Unexpected version number on GitHub.") }
        guard isNewer(version, than: installed) else { return .upToDate }

        let assets = json["assets"] as? [[String: Any]] ?? []
        func asset(_ name: String) -> URL? {
            (assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String)
                .flatMap(URL.init(string:)).flatMap { isTrustedAsset($0) ? $0 : nil }
        }
        let dmgName = assets.compactMap { $0["name"] as? String }.first { $0.hasSuffix(".dmg") } ?? ""
        let sha = asset(dmgName + ".sha256").flatMap { fetchData($0, timeout: 20) }.flatMap { String(data: $0, encoding: .utf8) }?
            .split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map { String($0).lowercased() }
        let notes = (json["body"] as? String ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return .available(UpdateInfo(version: version, notes: notes, dmgURL: asset(dmgName), sha256: sha, sigURL: asset(dmgName + ".sig2")))
    }

    // MARK: Installing

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static var cachesDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TaskManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    private static func sha256Hex(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// Downloads and checks the release; installs nothing unless the signature, checksum, bundle id, version and code
    /// signature all pass. Blocking: call from a background queue. Returns the verified app, or an error message.
    static func prepare(_ info: UpdateInfo, progress: @escaping (String, Double) -> Void) -> (app: URL?, error: String?) {
        let fm = FileManager.default
        guard let dmgURL = info.dmgURL, isTrustedAsset(dmgURL), let want = info.sha256, let sigURL = info.sigURL else {
            return (nil, "This release isn’t signed, so it won’t be installed automatically.")
        }
        let root = cachesDir.appendingPathComponent("update-\(Int(Date().timeIntervalSince1970))")
        guard (try? fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else {
            return (nil, "Couldn’t create a work folder.")
        }
        func fail(_ m: String) -> (URL?, String?) { try? fm.removeItem(at: root); return (nil, m) }

        progress("Downloading version \(info.version)…", 0)
        let dl = RedirectGuard()
        dl.onProgress = { progress("Downloading version \(info.version)…", $0 * 0.8) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: dl, delegateQueue: nil)
        session.downloadTask(with: URLRequest(url: dmgURL, timeoutInterval: 60)).resume()
        dl.done.wait(); session.finishTasksAndInvalidate()
        guard dl.status == 200, let tmp = dl.location else { return fail("Couldn’t download the update.") }
        let dmg = root.appendingPathComponent("update.dmg")
        guard (try? fm.moveItem(at: tmp, to: dmg)) != nil, let dmgData = try? Data(contentsOf: dmg, options: .alwaysMapped) else {
            return fail("Couldn’t read the download.")
        }

        progress("Verifying…", 0.85)
        guard let sigData = fetchData(sigURL, timeout: 20), let sig = String(data: sigData, encoding: .utf8),
              verifySignature(signedMessage(version: info.version, dmg: dmgData), base64Signature: sig) else {
            return fail("The download’s signature didn’t check out, so it was discarded.")
        }
        guard sha256Hex(dmgData) == want else { return fail("The download didn’t match its checksum, so it was discarded.") }

        progress("Unpacking…", 0.9)
        guard let again = try? Data(contentsOf: dmg, options: .alwaysMapped), sha256Hex(again) == want else {
            return fail("The download changed after it was checked, so it was discarded.")      // closes the check-to-mount gap
        }
        let mount = root.appendingPathComponent("mnt")
        try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path]) == 0 else {
            return fail("Couldn’t open the downloaded disk image.")
        }
        defer { run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let app = root.appendingPathComponent("TaskManager.app")
        guard run("/usr/bin/ditto", [mount.appendingPathComponent("TaskManager.app").path, app.path]) == 0 else {
            return fail("The disk image didn’t contain the app.")
        }
        let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == bundleID else { return fail("The download isn’t Task Manager.") }
        guard plist?["CFBundleShortVersionString"] as? String == info.version else {
            return fail("The download held a different version than the release says.")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            return fail("The app’s signature didn’t check out.")
        }
        try? fm.removeItem(at: dmg)
        progress("Ready", 0.96)
        return (app, nil)
    }

    /// Hands the verified app to a helper that waits for this app to quit, swaps it in (keeping the old one as a backup)
    /// and relaunches. Returns an error message, or nil once the hand-off has started – the caller should then quit.
    static func apply(_ app: URL, dest: URL = Bundle.main.bundleURL) -> String? {
        let fm = FileManager.default
        guard app.path.hasPrefix(cachesDir.path + "/"), dest.pathExtension == "app",
              run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            return "The update didn’t pass its final check, so it wasn’t installed."
        }
        guard !dest.path.hasPrefix("/Volumes/"), fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            return "Task Manager can’t replace itself here. Move it to Applications and try again."
        }
        let backup = cachesDir.appendingPathComponent("previous/TaskManager.app")
        try? fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = app.deletingLastPathComponent().appendingPathComponent("swap.sh")
        let body = """
        #!/bin/zsh
        PID="$1"; NEW="$2"; DEST="$3"; BACKUP="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$BACKUP"
        [ -d "$DEST" ] && mv "$DEST" "$BACKUP"
        if ! cp -R "$NEW" "$DEST"; then rm -rf "$DEST"; [ -d "$BACKUP" ] && mv "$BACKUP" "$DEST"; fi
        open "$DEST"
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil else { return "Couldn’t prepare the installer." }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), app.path, dest.path, backup.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "Couldn’t start the installer." }
        return nil
    }

    /// `TaskManager --selftest`: checks the version and signature logic.
    static func selfTest() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL: \(m)"); ok = false } }
        check(isNewer("0.2.0", than: "0.1.9") && isNewer("1.0.0", than: "0.9.9") && !isNewer("0.1.0", than: "0.1.0") && !isNewer("0.1.0", than: "0.1.1"), "isNewer")
        check(isPlainVersion("1.2.3") && !isPlainVersion("1.2") && !isPlainVersion("1.2.3-evil") && !isPlainVersion("../1.2.3"), "isPlainVersion")
        check(isTrustedAsset(URL(string: "https://github.com/\(repo)/releases/download/v1.0.0/a.dmg")!), "trusted asset")
        check(!isTrustedAsset(URL(string: "https://github.com/other/repo/releases/download/v1.0.0/a.dmg")!), "other repo rejected")
        check(!isTrustedAsset(URL(string: "http://github.com/\(repo)/releases/download/v1.0.0/a.dmg")!), "http rejected")
        check(isAllowedRedirectHost("objects.githubusercontent.com") && !isAllowedRedirectHost("evil.com") && !isAllowedRedirectHost("githubusercontent.com.evil.com"), "redirect hosts")
        let key = Curve25519.Signing.PrivateKey(), pub = key.publicKey.rawRepresentation.base64EncodedString()
        let dmg = Data("image".utf8)
        let sig = (try? key.signature(for: signedMessage(version: "1.0.0", dmg: dmg)))?.base64EncodedString() ?? ""
        check(verifySignature(signedMessage(version: "1.0.0", dmg: dmg), base64Signature: sig, publicKey: pub), "valid signature")
        check(!verifySignature(signedMessage(version: "1.0.1", dmg: dmg), base64Signature: sig, publicKey: pub), "signature is version-bound")
        check(!verifySignature(signedMessage(version: "1.0.0", dmg: Data("other".utf8)), base64Signature: sig, publicKey: pub), "tampered image rejected")
        check(!verifySignature(signedMessage(version: "1.0.0", dmg: dmg), base64Signature: sig), "other key rejected")
        return ok
    }
}

@MainActor
final class UpdateModel: ObservableObject {
    @Published var status = UpdateStatus.idle

    func check() {
        if case .checking = status { return }
        if case .installing = status { return }
        status = .checking
        DispatchQueue.global().async {
            let r = Updater.check()
            DispatchQueue.main.async { self.status = r }
        }
    }

    func install(_ info: UpdateInfo) {
        status = .installing("Starting…", 0)
        DispatchQueue.global().async {
            let r = Updater.prepare(info) { msg, f in DispatchQueue.main.async { self.status = .installing(msg, f) } }
            guard let app = r.app else { DispatchQueue.main.async { self.status = .failed(r.error ?? "Update failed.") }; return }
            DispatchQueue.main.async {
                self.status = .installing("Installing…", 0.98)
                if let e = Updater.apply(app) { self.status = .failed(e) } else { NSApp.terminate(nil) }
            }
        }
    }

    var available: UpdateInfo? { if case .available(let i) = status { return i } else { return nil } }
}
