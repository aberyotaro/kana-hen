/// 打ち直しの 1 区間。かなはかなモードでローマ字を打ち、英字はそのまま打つ。
public enum Span: Equatable {
    case kana(romaji: String, kana: String)
    case literal(String)
}

public struct Judgment: Equatable {
    public let convert: Bool
    /// 打ち直す区間を先頭から順に並べたもの。最後がかななら変換待ちのまま残す
    public let spans: [Span]
    /// 打ち直す前に Backspace で消す文字数（スペースを含む）
    public let deleteCount: Int
    public let reason: String

    /// かな区間のローマ字をつないだもの（単語間のスペースは除く）
    public var romaji: String {
        spans.reduce(into: "") { if case .kana(let r, _) = $1 { $0 += r } }
    }
    public var kana: String {
        spans.reduce(into: "") { if case .kana(_, let k) = $1 { $0 += k } }
    }
}
