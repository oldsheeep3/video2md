// メニューバーアプリ版。起動時に権限と Live Caption を確認し、メニューから開始/停止する。
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var logger: CaptionLogger?
    private let toggleItem = NSMenuItem(title: "記録を開始", action: #selector(toggle), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "停止中", action: nil, keyEquivalent: "")
    private var lastFile: String?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.title = "📝"
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        toggleItem.target = self
        menu.addItem(toggleItem)
        for (title, sel) in [("保存フォルダを開く", #selector(openFolder)),
                             ("Live Caption の設定を開く", #selector(openCaption)),
                             ("アクセシビリティ設定を開く", #selector(openAX))] {
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: ""); m.target = self; menu.addItem(m)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        startupChecks()
    }

    func applicationWillTerminate(_ n: Notification) { logger?.stop() }

    // MARK: 起動時チェック

    private func startupChecks() {
        if !Env.accessibilityGranted(prompt: true) {
            statusLine.title = "アクセシビリティの許可待ち…"
            toggleItem.isEnabled = false
            // 許可されたら自動で有効化する
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                guard let self, Env.accessibilityGranted(prompt: false) else { return }
                t.invalidate()
                self.toggleItem.isEnabled = true
                self.statusLine.title = "停止中"
            }
        }
    }

    /// 記録中に字幕ウィンドウが一定時間出なければ、Live Caption がオフの可能性を案内する（1 記録につき 1 回）。
    private var hinted = false
    private func checkLiveCaption() {
        hintTimer?.invalidate()
        hinted = false
        hintTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, let l = self.logger, l.isRunning else { t.invalidate(); return }
            if l.everSawCaptionWindow { t.invalidate(); return }
            guard l.elapsed > 15, !self.hinted else { return }
            self.hinted = true
            t.invalidate()
            let a = NSAlert()
            a.messageText = "字幕ウィンドウが見つかりません"
            a.informativeText = "動画の音声が再生されているか、Chrome の「自動字幕起こし」（Live Caption）がオンか確認してください。設定ページを開きますか？"
            a.addButton(withTitle: "設定を開く")
            a.addButton(withTitle: "あとで")
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn { Env.openCaptionSettings() }
        }
    }
    private var hintTimer: Timer?

    // MARK: 操作

    @objc private func toggle() {
        if let l = logger, l.isRunning {
            l.stop()
            statusLine.title = "保存しました: \((l.outPath as NSString).lastPathComponent)"
            toggleItem.title = "記録を開始"
            item.button?.title = "📝"
            return
        }
        let path = CaptionLogger.defaultOutPath()
        lastFile = path
        logger = CaptionLogger(outPath: path) { [weak self] line in
            self?.statusLine.title = "記録中: " + String(line.dropFirst(10).prefix(24))
        }
        logger?.start()
        checkLiveCaption()
        statusLine.title = "記録中（動画の音声を再生してください）"
        toggleItem.title = "記録を停止して保存"
        item.button?.title = "🔴"
    }

    @objc private func openFolder() {
        let dir = NSHomeDirectory() + "/Documents/Moodle文字起こし"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }
    @objc private func openCaption() { Env.openCaptionSettings() }
    @objc private func openAX() { Env.openAccessibilitySettings() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
