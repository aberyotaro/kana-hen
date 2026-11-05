import Foundation

/// フォーカス中の入力欄の状態。位置と長さは UTF-16 単位（アクセシビリティ API と同じ）
public struct FocusedText: Equatable {
    public let text: String
    public let caret: Int
    public let selectionLength: Int

    public init(text: String, caret: Int, selectionLength: Int) {
        self.text = text
        self.caret = caret
        self.selectionLength = selectionLength
    }

    /// 消そうとしている文字列がカーソルの直前にあり、選択範囲がないときだけ true。
    /// 記録と入力欄がずれているとき（補完で選択が残っている、フォーカスが移ったなど）に、
    /// 打っていない文字を Backspace で消さないための確認
    public func endsAtCaret(with typed: String) -> Bool {
        typedEnd(typed) != nil
    }

    /// typed の終わりの位置（UTF-16）。カーソルの直前になければ nil。
    /// Electron の複数行の入力欄（Claude, Slack）は、空行を含むと値とカーソル位置で改行の数え方が違い、
    /// 末尾にカーソルがあっても位置が改行の数までずれる。typed が欄の末尾にあり、ずれが改行の数以内なら末尾とみなす
    func typedEnd(_ typed: String) -> Int? {
        guard selectionLength == 0 else { return nil }
        let utf16 = Array(text.utf16)
        let typed16 = Array(typed.utf16)
        if caret >= typed16.count, caret <= utf16.count,
           Array(utf16[(caret - typed16.count)..<caret]) == typed16 {
            return caret
        }
        let newlines = utf16.filter { $0 == 0x0A || $0 == 0x0D }.count
        guard newlines > 0, utf16.count >= typed16.count,
              Array(utf16.suffix(typed16.count)) == typed16,
              caret < utf16.count, utf16.count - caret <= newlines,
              !typed16.contains(0x0A), !typed16.contains(0x0D) else { return nil }
        return utf16.count
    }

    /// typed がカーソルの直前、または選択範囲の直前にあれば true。
    /// 変換待ちの文字を選択範囲として返すアプリがあっても確かめられるよう、選択があっても受け付ける
    public func compositionEnds(with typed: String) -> Bool {
        let utf16 = Array(text.utf16)
        let typed16 = Array(typed.utf16)
        for end in Set([caret, caret + selectionLength]) where end >= typed16.count && end <= utf16.count {
            if Array(utf16[(end - typed16.count)..<end]) == typed16 { return true }
        }
        return false
    }

    /// 照合に失敗したときの手がかり。文字の中身は含めない。
    /// typed が最後に現れる位置の終わりとカーソルの差（end-caret）で、ずれの大きさが分かる
    public func mismatchSummary(typed: String) -> String {
        let utf16 = Array(text.utf16)
        let typed16 = Array(typed.utf16)
        let newlines = utf16.filter { $0 == 0x0A || $0 == 0x0D }.count
        var lastEnd: Int?
        if typed16.count <= utf16.count {
            for end in stride(from: utf16.count, through: typed16.count, by: -1)
            where Array(utf16[(end - typed16.count)..<end]) == typed16 {
                lastEnd = end
                break
            }
        }
        let offset = lastEnd.map { String($0 - caret) } ?? "none"
        return "length \(utf16.count) caret \(caret) selection \(selectionLength) newlines \(newlines) "
            + "typed \(typed16.count) end-caret \(offset)"
    }

    /// カーソルの直前にある typed より前の文字（最大 limit 文字）。typed がカーソルの直前にないときは nil
    public func text(before typed: String, limit: Int = 64) -> String? {
        guard let typedEnd = typedEnd(typed) else { return nil }
        let end = typedEnd - typed.utf16.count
        let context = String(decoding: Array(text.utf16)[..<end], as: UTF16.self)
        return String(context.suffix(limit))
    }
}
