// CLI 版とメニューバーアプリ版で共有する中核ロジック。
// Chrome の Live Caption ウィンドウをアクセシビリティ API で読み、新しい字幕だけを Markdown に追記する。
import Cocoa
import ApplicationServices

// MARK: - 起動時チェック

enum Env {
    /// アクセシビリティ権限があるか。prompt=true なら未許可のときにシステムのダイアログを出し、
    /// 設定画面の一覧にこのアプリ（CLI 版なら起動元のターミナル）を追加する。
    static func accessibilityGranted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static var chromeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty
    }

    /// Chrome の「字幕」設定ページを開く（Live Caption のスイッチがある）。
    static func openCaptionSettings() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Google Chrome", "chrome://settings/captions"]
        try? p.run()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 字幕の記録

final class CaptionLogger {
    let outPath: String
    private let onLine: (String) -> Void
    private let holdBack = 15      // 末尾の数文字は後から訂正されやすいので確定を少し待つ
    private let idleFlush = 6.0    // この秒数 新しい字幕が無ければ残りを確定する

    private(set) var captionWindowFound = false
    private var timer: Timer?
    private var started = Date()
    private var committed = ""     // 確定済みの字幕（アンカー探索用）
    private var sentence = ""      // 句点がまだ来ていない確定済みの断片
    private var sentenceStart = 0.0
    private var lastNew = ""
    private var lastChange = Date()
    private var out: FileHandle?

    init(outPath: String, onLine: @escaping (String) -> Void) {
        self.outPath = outPath
        self.onLine = onLine
    }

    static func defaultOutPath() -> String {
        let dir = NSHomeDirectory() + "/Documents/Moodle文字起こし"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmm"
        return "\(dir)/live_\(f.string(from: Date())).md"
    }

    var isRunning: Bool { timer != nil }

    /// 記録を始めてからの秒数。
    var elapsed: TimeInterval { Date().timeIntervalSince(started) }

    /// Live Caption の設定は Chrome のデータ領域にあり macOS の保護で読めないため、
    /// 字幕ウィンドウが一度も出ていない状態が続くかどうかで「オフかも」を判断する。
    var everSawCaptionWindow = false

    func start() {
        guard timer == nil else { return }
        started = Date()
        committed = ""; sentence = ""; lastNew = ""
        let header = "# Live Caption 文字起こし\n\n- 記録開始: \(started)\n\n## 文字起こし\n\n"
        FileManager.default.createFile(atPath: outPath, contents: header.data(using: .utf8))
        out = FileHandle(forWritingAtPath: outPath)
        out?.seekToEndOfFile()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// 停止して、未確定の字幕を書き出す。
    func stop() {
        guard timer != nil else { return }
        timer?.invalidate(); timer = nil
        commit(lastNew); lastNew = ""
        let rest = sentence.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { write("- [\(stamp(sentenceStart))] \(rest)") }
        sentence = ""
        out?.closeFile(); out = nil
    }

    // MARK: 取得

    private func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? (v as AnyObject?) : nil
    }

    private func collect(_ e: AXUIElement, _ depth: Int, _ lines: inout [String]) {
        if (attr(e, kAXRoleAttribute) as? String) == "AXStaticText",
           let v = attr(e, kAXValueAttribute) as? String, !v.isEmpty { lines.append(v) }
        if depth > 12 { return }
        for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { collect(c, depth + 1, &lines) }
    }

    private static let cjkGap = try! NSRegularExpression(pattern: "(?<=[^\\x00-\\x7F]) (?=[^\\x00-\\x7F])")

    private func normalize(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\u{FFFD}", with: "")
        return Self.cjkGap.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
    }

    private func readCaption() -> String? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first
        else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        for w in (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            let title = attr(w, kAXTitleAttribute) as? String ?? ""
            guard title.contains("字幕") || title.contains("Live Caption") else { continue }
            var lines: [String] = []
            collect(w, 0, &lines)
            return normalize(lines.filter { $0 != title }.joined())
        }
        return nil
    }

    // MARK: 差分

    private func stamp(_ sec: Double) -> String {
        let s = Int(sec), h = s / 3600
        return h > 0 ? String(format: "%d:%02d:%02d", h, (s % 3600) / 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func write(_ line: String) {
        out?.write((line + "\n").data(using: .utf8)!)
        onLine(line)
    }

    private func commit(_ text: String) {
        guard !text.isEmpty else { return }
        committed += text
        if sentence.isEmpty { sentenceStart = Date().timeIntervalSince(started) }
        sentence += text
        while let r = sentence.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？")) {
            let s = String(sentence[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { write("- [\(stamp(sentenceStart))] \(s)") }
            sentence = String(sentence[r.upperBound...])
            sentenceStart = Date().timeIntervalSince(started)
        }
    }

    /// 前回確定した末尾を現在の字幕から探し、その後ろを新規部分として返す。
    private func newPart(of cur: String) -> String {
        if committed.isEmpty { return cur }
        for n in [30, 20, 12, 6] where committed.count >= n {
            if let r = cur.range(of: String(committed.suffix(n)), options: .backwards) {
                return String(cur[r.upperBound...])
            }
        }
        return cur
    }

    private func tick() {
        guard let cur = readCaption() else { captionWindowFound = false; return }
        captionWindowFound = true
        everSawCaptionWindow = true
        guard !cur.isEmpty else { return }
        let fresh = newPart(of: cur)
        if fresh != lastNew { lastChange = Date() }
        lastNew = fresh
        if fresh.count > holdBack {
            commit(String(fresh.dropLast(holdBack)))
            lastNew = String(fresh.suffix(holdBack))
        } else if Date().timeIntervalSince(lastChange) > idleFlush, !lastNew.isEmpty {
            commit(lastNew); lastNew = ""
        }
    }
}
