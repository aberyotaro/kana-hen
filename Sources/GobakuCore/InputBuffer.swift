import Foundation

/// 英数モードで打たれた文字を、カーソル位置が変わるまで溜めておく。
public struct InputBuffer {
    public private(set) var text = ""
    let limit: Int
    /// これより長く入力が途切れたら、フォーカスが移った可能性があるので捨てる
    let idleLimit: TimeInterval
    private var lastInput: Date?

    public init(limit: Int = 256, idleLimit: TimeInterval = 30) {
        self.limit = limit
        self.idleLimit = idleLimit
    }

    public mutating func append(_ c: Character, at now: Date = Date()) {
        if isStale(at: now) { reset() }
        lastInput = now
        text.append(c)
        if text.count > limit { text.removeFirst(text.count - limit) }
    }

    public mutating func backspace(at now: Date = Date()) {
        if isStale(at: now) {
            reset()
            return
        }
        lastInput = now
        if !text.isEmpty { text.removeLast() }
    }

    public mutating func consume(at now: Date = Date()) -> String {
        if isStale(at: now) {
            reset()
            return ""
        }
        let committed = text
        reset()
        return committed
    }

    public mutating func reset() {
        text = ""
        lastInput = nil
    }

    private func isStale(at now: Date) -> Bool {
        guard let last = lastInput else { return false }
        return now.timeIntervalSince(last) > idleLimit
    }
}

/// フォーカス中の入力欄の状態。位置と長さは UTF-16 単位（アクセシビリティ API と同じ）
public struct FocusedText: Equatable {
    public var text: String
    public var caret: Int
    public var selectionLength: Int

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

    /// カーソルの直前にある typed より前の文字（最大 limit 文字）。typed がカーソルの直前にないときは nil
    public func text(before typed: String, limit: Int = 64) -> String? {
        guard endsAtCaret(with: typed) else { return nil }
        let end = caret - typed.utf16.count
        let context = String(decoding: Array(text.utf16)[..<end], as: UTF16.self)
        return String(context.suffix(limit))
    }
}
