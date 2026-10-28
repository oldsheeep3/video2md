// CLI 版: ターミナルから起動し、Ctrl-C で終了する。
import Cocoa

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
if args.contains("-h") || args.contains("--help") {
    print("使い方: video2md [出力.md]\n既定の保存先: ~/Documents/Moodle文字起こし/live_<日時>.md")
    exit(0)
}

print("video2md — Chrome の Live Caption を Markdown に保存します\n")

// 1. アクセシビリティ権限（未許可ならダイアログを出して、許可されるまで待つ）
if !Env.accessibilityGranted(prompt: false) {
    print("① アクセシビリティの権限が必要です。")
    print("   ダイアログまたは システム設定 > プライバシーとセキュリティ > アクセシビリティ で、")
    print("   このターミナルアプリをオンにしてください。許可されるまで待機します…")
    _ = Env.accessibilityGranted(prompt: true)
    while !Env.accessibilityGranted(prompt: false) { Thread.sleep(forTimeInterval: 2) }
}
print("① アクセシビリティ権限: OK")

// 2. Chrome
if Env.chromeRunning {
    print("② Google Chrome: 起動中")
} else {
    print("② Google Chrome が起動していません。起動して動画を開いてください。")
}

// 3. 記録
let outPath = args.count > 1 ? (args[1] as NSString).expandingTildeInPath : CaptionLogger.defaultOutPath()
let logger = CaptionLogger(outPath: outPath) { print($0) }
logger.start()
print("③ 保存先: \(outPath)")
print("   動画を再生してください（音声が流れると字幕ウィンドウが出ます）。Ctrl-C で終了します。\n")

// 一定時間たっても字幕ウィンドウが出なければ、Live Caption がオフの可能性を案内する（設定ページは 1 回だけ開く）
var hinted = false
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    guard !hinted, !logger.everSawCaptionWindow, logger.elapsed > 15, Env.chromeRunning else { return }
    hinted = true
    print("   字幕ウィンドウが見つかりません。次を確認してください:")
    print("   - 動画の音声が再生されているか（無音だと字幕は出ません）")
    print("   - Chrome の Live Caption（自動字幕起こし）がオンか → 設定ページを開きます")
    Env.openCaptionSettings()
}

signal(SIGINT, SIG_IGN)
let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sig.setEventHandler {
    logger.stop()
    print("\n保存しました: \(outPath)")
    exit(0)
}
sig.resume()
RunLoop.main.run()
