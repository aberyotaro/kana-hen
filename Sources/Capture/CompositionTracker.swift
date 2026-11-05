import Foundation

/// かなモードで、Shift+英字から始まる一時的な英字入力の区間を、打ったキーから推定する。
/// 日本語入力によって、英字入力がひらがなに戻る決まりが違う（Google 日本語入力は "PRha" で "PRは" に戻る、
/// 標準の日本語入力は未確認）。そのため戻る決まりは真似ず、Shift+英字から後ろをすべて英字の候補として持つ。
/// 実際に英字のままかは、Enter の時点で入力欄の中身と突き合わせて確かめる
public struct CompositionTracker {
    private var run = ""
    private var inASCII = false

    public init() {}

    /// 変換待ちの末尾が英字の区間かもしれないとき、その文字列。そうでなければ nil
    public var asciiRun: String? { inASCII && !run.isEmpty ? run : nil }

    public mutating func type(_ c: Character) {
        guard c.isASCII else { reset(); return }
        if c.isUppercase && c.isLetter && !inASCII {
            inASCII = true
            run = ""
        }
        if inASCII { run.append(c) }
    }

    public mutating func backspace() {
        guard inASCII, !run.isEmpty else { reset(); return }
        run.removeLast()
        // 英字をすべて消すと、直前はひらがな（か空）なのでひらがなに戻る
        if run.isEmpty { inASCII = false }
    }

    public mutating func reset() {
        run = ""
        inASCII = false
    }
}
