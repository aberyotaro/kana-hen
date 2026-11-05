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
