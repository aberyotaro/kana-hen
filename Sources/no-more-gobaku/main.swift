import Cocoa
import GobakuCore

let usage = """
使い方:
  no-more-gobaku [run] [-v]     常駐して、英数モードの Enter で誤入力を判定・変換する
  no-more-gobaku check <文字列>... 判定だけを試す（引数がなければ標準入力を 1 行ずつ）
  no-more-gobaku sources        有効な入力ソースの ID を一覧する
"""

func makeDetector(_ config: Config) -> Detector {
    let words = Detector.loadEnglishWords(paths: [
        "/usr/share/dict/words",
        Config.directory.appendingPathComponent("words.txt").path,
    ])
    return Detector(englishWords: words, minLetters: config.minLetters,
                    minJapaneseRatio: config.minJapaneseRatio)
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
        no-more-gobaku: アクセシビリティの許可が必要です。
          システム設定 > プライバシーとセキュリティ > アクセシビリティ で、
          このコマンドを実行しているアプリ（ターミナルなど）を許可してから再実行してください。\n
        """, stderr)
        exit(1)
    }
    let engine = Engine(detector: makeDetector(config), config: config, verbose: verbose)
    guard engine.start() else {
        fputs("no-more-gobaku: キー入力の監視を開始できませんでした（入力監視の許可を確認してください）\n", stderr)
        exit(1)
    }
    // LaunchAgent でファイルに出力するときもログがすぐ書き出されるよう、行単位でバッファする
    setvbuf(stdout, nil, _IOLBF, 0)
    print("no-more-gobaku: 起動しました（Ctrl+C で終了）")
    NSApplication.shared.setActivationPolicy(.prohibited)
    NSApplication.shared.run()

case "check":
    let detector = makeDetector(config)
    let inputs = args.isEmpty ? AnyIterator { readLine() }.map { $0 } : args
    for input in inputs {
        let j = detector.judge(input)
        let mark = j.convert ? "✓" : "✗"
        let detail = j.romaji.isEmpty ? "" : "  \(j.romaji) → \(j.kana)  削除 \(j.deleteCount) 文字"
        print("\(mark) \(input.debugDescription)  [\(j.reason)]\(detail)")
    }

case "sources":
    for source in InputSource.enabled() {
        guard let id = InputSource.id(of: source) else { continue }
        print(InputSource.isKanaMode(id) ? "* \(id)" : "  \(id)")
    }
    print("\n(* は切り替え先の候補になるかな入力モード)")

default:
    print(usage)
    exit(command == "help" ? 0 : 1)
}
