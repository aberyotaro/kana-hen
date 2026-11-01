/// 英数モードで打たれた文字を、カーソル位置が変わるまで溜めておく。
public struct InputBuffer {
    public private(set) var text = ""
    let limit: Int

    public init(limit: Int = 256) {
        self.limit = limit
    }

    public mutating func append(_ c: Character) {
        text.append(c)
        if text.count > limit { text.removeFirst(text.count - limit) }
    }

    public mutating func backspace() {
        if !text.isEmpty { text.removeLast() }
    }

    public mutating func reset() {
        text = ""
    }
}
