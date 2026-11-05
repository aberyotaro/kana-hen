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
        guard selectionLength == 0 else { return false }
        let utf16 = Array(text.utf16)
        let typed16 = Array(typed.utf16)
        guard caret >= typed16.count, caret <= utf16.count else { return false }
        return Array(utf16[(caret - typed16.count)..<caret]) == typed16
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

    /// カーソルの直前にある typed より前の文字（最大 limit 文字）。typed がカーソルの直前にないときは nil
    public func text(before typed: String, limit: Int = 64) -> String? {
        guard endsAtCaret(with: typed) else { return nil }
        let end = caret - typed.utf16.count
        let context = String(decoding: Array(text.utf16)[..<end], as: UTF16.self)
        return String(context.suffix(limit))
    }
}
