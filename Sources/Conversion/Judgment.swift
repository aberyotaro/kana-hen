/// 打ち直しの 1 区間。かなはかなモードでローマ字を打ち、英字はそのまま打つ。
public enum Span: Equatable {
    case kana(romaji: String, kana: String)
    case literal(String)
}

public struct Judgment: Equatable {
    public let convert: Bool
    public let spans: [Span]
    /// 打ち直す前に Backspace で消す文字数（スペースを含む）
    public let deleteCount: Int
    public let reason: String

    public var romaji: String {
        spans.reduce(into: "") { if case .kana(let r, _) = $1 { $0 += r } }
    }
    public var kana: String {
        spans.reduce(into: "") { if case .kana(_, let k) = $1 { $0 += k } }
    }
}
