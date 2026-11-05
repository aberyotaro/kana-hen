import Cocoa
import Conversion

let usage = """
使い方:
  kanahen [run] [-v]     常駐して、英数モードの Enter で誤入力を判定・変換する
  kanahen check <文字列>... 判定だけを試す（引数がなければ標準入力を 1 行ずつ）
  kanahen sources        有効な入力ソースの ID を一覧する
  kanahen probe [秒]     指定秒後（既定 5）に前面の入力欄を読めるか調べる（中身は表示しない）
"""

func makeDetector(_ config: Config) -> Detector {
    let words = Detector.loadEnglishWords(paths: [
        "/usr/share/dict/words",
        Config.directory.appendingPathComponent("words.txt").path,
    ])
    return Detector(englishWords: words, minLetters: config.minLetters,
                    minJapaneseRatio: config.minJapaneseRatio)
}

func describe(_ spans: [Span]) -> String {
    if spans.count == 1, case .kana(let romaji, let kana) = spans[0] { return "\(romaji) → \(kana)" }
    return spans.map {
        switch $0 {
        case .kana(let romaji, let kana): return "[かな \(romaji) → \(kana)]"
        case .literal(let text): return "[英字 \(text.debugDescription)]"
        }
    }.joined(separator: " ")
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.first.flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "run"
if args.first == command { args.removeFirst() }
let config = Config.load()

switch command {
case "run":
    let verbose = args.contains("-v")
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        fputs("""
        kanahen: アクセシビリティの許可が必要です。
          システム設定 > プライバシーとセキュリティ > アクセシビリティ で、
          このコマンドを実行しているアプリ（ターミナルなど）を許可してから再実行してください。\n
        """, stderr)
        exit(1)
    }
    let engine = Engine(detector: makeDetector(config), config: config, verbose: verbose)
    guard engine.start() else {
        fputs("kanahen: キー入力の監視を開始できませんでした（入力監視の許可を確認してください）\n", stderr)
        exit(1)
    }
    // LaunchAgent でファイルに出力するときもログがすぐ書き出されるよう、行単位でバッファする
    setvbuf(stdout, nil, _IOLBF, 0)
    print("kanahen: 起動しました（Ctrl+C で終了）")
    NSApplication.shared.setActivationPolicy(.prohibited)
    NSApplication.shared.run()

case "check":
    let detector = makeDetector(config)
    let inputs = args.isEmpty ? AnyIterator { readLine() }.map { $0 } : args
    for input in inputs {
        let j = detector.judge(input)
        let mark = j.convert ? "✓" : "✗"
        let detail = j.spans.isEmpty ? "" : "  \(describe(j.spans))  削除 \(j.deleteCount) 文字"
        print("\(mark) \(input.debugDescription)  [\(j.reason)]\(detail)")
    }

case "sources":
    for source in InputSource.enabled() {
        guard let id = InputSource.id(of: source) else { continue }
        print(InputSource.isKanaMode(id) ? "* \(id)" : "  \(id)")
    }
    print("\n(* は切り替え先の候補になるかな入力モード)")
    print("今の入力ソースは\(InputSource.isCurrentASCII() ? "英数とみなす（判定の対象）" : "英数とみなさない（何もしない）")")

case "probe":
    let seconds = args.first.flatMap(Double.init) ?? 5
    Thread.sleep(forTimeInterval: seconds)
    let front = NSWorkspace.shared.frontmostApplication
    print("trusted: \(AXIsProcessTrusted())  app: \(front?.bundleIdentifier ?? "不明")")
    if let front {
        Accessibility.prepare(front.processIdentifier)
        Thread.sleep(forTimeInterval: 0.5)
    }
    switch Accessibility.focusedText() {
    case .success(let f):
        print("ok: 文字数 \(f.text.utf16.count)  カーソル \(f.caret)  選択 \(f.selectionLength)")
    case .failure(let e):
        print("失敗: \(e)")
    }

default:
    print(usage)
    exit(command == "help" ? 0 : 1)
}
