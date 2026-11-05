/// ローマ字をひらがなに変換する。IME と同じく最長一致で解釈する。
///
/// 英文の誤検出を減らすため、日常のローマ字入力で使わない綴り
/// （l/x の小書き、v 行、th/dh など）はあえて受け付けない。
public enum Romaji {
    static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

    static let punctuation: [Character: String] = [
        "-": "ー", ",": "、", ".": "。", "?": "？", "!": "！",
    ]

    static let table: [String: String] = {
        var t: [String: String] = [:]
        let rows: [(String, [String])] = [
            ("", ["あ", "い", "う", "え", "お"]),
            ("k", ["か", "き", "く", "け", "こ"]),
            ("g", ["が", "ぎ", "ぐ", "げ", "ご"]),
            ("s", ["さ", "し", "す", "せ", "そ"]),
            ("z", ["ざ", "じ", "ず", "ぜ", "ぞ"]),
            ("t", ["た", "ち", "つ", "て", "と"]),
            ("d", ["だ", "ぢ", "づ", "で", "ど"]),
            ("n", ["な", "に", "ぬ", "ね", "の"]),
            ("h", ["は", "ひ", "ふ", "へ", "ほ"]),
            ("b", ["ば", "び", "ぶ", "べ", "ぼ"]),
            ("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]),
            ("m", ["ま", "み", "む", "め", "も"]),
            ("r", ["ら", "り", "る", "れ", "ろ"]),
        ]
        let vs = ["a", "i", "u", "e", "o"]
        for (c, kana) in rows {
            for (v, k) in zip(vs, kana) { t[c + v] = k }
        }

        let yRows: [(String, String)] = [
            ("k", "き"), ("g", "ぎ"), ("s", "し"), ("z", "じ"), ("j", "じ"),
            ("t", "ち"), ("c", "ち"), ("d", "ぢ"), ("n", "に"), ("h", "ひ"),
            ("b", "び"), ("p", "ぴ"), ("m", "み"), ("r", "り"),
        ]
        for (c, i) in yRows {
            t[c + "ya"] = i + "ゃ"
            t[c + "yu"] = i + "ゅ"
            t[c + "yo"] = i + "ょ"
        }

        let extra: [String: String] = [
            "ya": "や", "yu": "ゆ", "yo": "よ", "wa": "わ", "wo": "を",
            "shi": "し", "chi": "ち", "tsu": "つ", "fu": "ふ", "ji": "じ",
            "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "she": "しぇ",
            "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "che": "ちぇ",
            "ja": "じゃ", "ju": "じゅ", "jo": "じょ", "je": "じぇ",
            "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ",
        ]
        t.merge(extra) { _, new in new }
        return t
    }()

    /// 全体をローマ字として解釈できればひらがなを返す。できなければ nil。
    public static func toKana(_ input: String) -> String? {
        let s = Array(input)
        var out = ""
        var i = 0
        while i < s.count {
            let c = s[i]
            let next: Character? = i + 1 < s.count ? s[i + 1] : nil

            if let p = punctuation[c] {
                out += p
                i += 1
                continue
            }

            if c == "n" {
                if next == "n" {
                    out += "ん"
                    i += 2
                    continue
                }
                if next == nil || (!vowels.contains(next!) && next != "y") {
                    out += "ん"
                    i += 1
                    continue
                }
            }

            // 促音: kk, tt, ss... と tch
            if let n = next, !vowels.contains(c), c != "n", c.isLetter,
               n == c || (c == "t" && n == "c" && i + 2 < s.count && s[i + 2] == "h") {
                out += "っ"
                i += 1
                continue
            }

            var matched = false
            for len in stride(from: 3, through: 1, by: -1) where i + len <= s.count {
                if let kana = table[String(s[i..<i + len])] {
                    out += kana
                    i += len
                    matched = true
                    break
                }
            }
            if !matched { return nil }
        }
        return out
    }
}
