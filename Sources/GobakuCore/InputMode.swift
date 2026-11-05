import Foundation

/// 英数キー・かなキーを押した直後の入力モード。
/// 日本語入力はキーを受けた時点でモードを変えるが、入力ソースの問い合わせ結果が追いつくのは
/// 100 ms ほどあと。その間に打ったキーを古いモードとして扱うと、打ち始めの文字を記録し損ねる
public struct InputModeTracker {
    let window: TimeInterval
    private var pending: (ascii: Bool, until: Date)?

    public init(window: TimeInterval = 1) {
        self.window = window
    }

    public mutating func modeKeyPressed(ascii: Bool, at now: Date = Date()) {
        pending = (ascii, now.addingTimeInterval(window))
    }

    /// 問い合わせた結果（reported）より、直前に押したモードキーを優先する。
    /// 問い合わせ結果が追いついたら、または window を過ぎたら、問い合わせ結果に戻る
    public mutating func isASCII(reported: Bool, at now: Date = Date()) -> Bool {
        guard let p = pending else { return reported }
        if reported == p.ascii || now > p.until {
            pending = nil
            return reported
        }
        return p.ascii
    }
}
