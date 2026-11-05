import Foundation

/// 打ち直しの 1 区間。かなはかなモードでローマ字を打ち、英字はそのまま打つ。
public enum Span: Equatable {
    case kana(romaji: String, kana: String)
    case literal(String)
}

public struct Judgment: Equatable {
    public var convert: Bool
    /// 打ち直す区間を先頭から順に並べたもの。最後がかななら変換待ちのまま残す
    public var spans: [Span]
    /// 打ち直す前に Backspace で消す文字数（スペースを含む）
    public var deleteCount: Int
    public var reason: String

    /// かな区間のローマ字をつないだもの（単語間のスペースは除く）
    public var romaji: String {
        spans.reduce(into: "") { if case .kana(let r, _) = $1 { $0 += r } }
    }
    public var kana: String {
        spans.reduce(into: "") { if case .kana(_, let k) = $1 { $0 += k } }
    }
}

/// 英数モードで打たれた末尾の文字列が「日本語のつもりのローマ字」かを判定する。
public final class Detector {
    public var minLetters: Int
    /// ローマ字トークンのうち、英単語でないものが占める文字数の割合の下限
    public var minJapaneseRatio: Double
    let englishWords: Set<String>

    public init(englishWords: Set<String>, minLetters: Int = 4, minJapaneseRatio: Double = 0.5) {
        self.englishWords = englishWords
        self.minLetters = minLetters
        self.minJapaneseRatio = minJapaneseRatio
    }

    /// ローマ字としても読める英単語のうち、システム辞書に載っていない活用形など
    static let builtinEnglish: [String] = [
        "been", "seen", "taken", "given", "eaten", "beaten", "bitten", "hidden",
        "ridden", "bidden", "sudden", "happen", "kitten", "gotten", "chosen",
        "risen", "woken", "women", "wooden", "token", "open", "amen", "omen",
        "season", "reason", "nation", "session", "mission", "union", "onion",
        "opinion", "domain", "remain", "again", "teen", "keen", "noon", "moon", "soon",
        // 開発でよく打つ語
        "info", "repo", "todo", "nano", "inode", "sudo", "ubuntu", "debian", "mongo",
        "deno", "rebase", "goroutine", "tokenize", "memoize", "demo", "promo", "techno",
        "pesto", "github", "gitlab", "golang", "docker", "python", "javascript",
        "typescript", "slack", "claude", "iphone", "macos", "linux", "json", "yaml", "howto",
        // チャットでよく打つ口語。辞書にないうえ、ローマ字としても読めてしまう
        "haha", "hahaha", "hehe", "meme", "gonna", "wanna", "kinda", "gotta", "sorta", "emo",
    ]

    /// 英単語とみなすか。辞書にない複合語（database, runtime）や -tion 語も英語として扱う
    func isEnglish(_ word: String) -> Bool {
        // ホストの辞書は OS で違う。web2 は shita を載せるが、語尾は日本語。
        if Self.japaneseEndings.contains(word) { return false }
        if englishWords.contains(word) { return true }
        if word.contains("tion") || word.contains("sion") { return true }

        // 前半 3 文字以上・後半 4 文字以上の英単語 2 つに分けられるか。
        // 後半を 4 文字以上にするのは mat+cha (matcha) のような誤判定を避けるため
        let chars = Array(word)
        guard chars.count >= 7 else { return false }
        for split in 3...(chars.count - 4) {
            let tail = String(chars[split...])
            if Self.japaneseEndings.contains(tail) { continue }
            if englishWords.contains(String(chars[..<split])),
               englishWords.contains(tail) {
                return true
            }
        }
        return false
    }

    public static func loadEnglishWords(paths: [String]) -> Set<String> {
        var words = Set(builtinEnglish)
        for path in paths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let w = line.trimmingCharacters(in: .whitespaces).lowercased()
                if !w.isEmpty, !w.hasPrefix("#") { words.insert(w) }
            }
        }
        return words
    }

    public func judge(_ text: String) -> Judgment {
        let base = judgeRomajiTail(text)
        if base.convert { return base }
        let chars = Array(text)
        var end = chars.count
        while end > 0, chars[end - 1] == " " { end -= 1 }
        return judgeGluedEnglish(chars: chars, end: end)
            ?? judgeSpacedLiteralTail(chars: chars, end: end)
            ?? base
    }

    private func judgeRomajiTail(_ text: String) -> Judgment {
        let chars = Array(text)
        var end = chars.count
        while end > 0, chars[end - 1] == " " { end -= 1 }

        // 末尾から、ローマ字として読めるトークンをさかのぼって集める
        var tokens: [(start: Int, word: String, kana: String)] = []
        var hasParticleSplit = false
        var i = end
        while i > 0 {
            var start = i
            while start > 0, chars[start - 1] != " " { start -= 1 }
            let word = String(chars[start..<i])
            // "kyouha ?" の "?" のように記号だけの語は、ローマ字の語に挟まれていれば一緒に打ち直す
            if !word.contains(where: \.isLetter), let kana = Romaji.toKana(word) {
                tokens.append((start, word, kana))
                if start == 0 { break }
                i = start
                while i > 0, chars[i - 1] == " " { i -= 1 }
                continue
            }
            guard let kana = Romaji.toKana(word) else {
                // "repositoryha" のような「英単語＋助詞」なら助詞の部分だけを拾う
                if let split = splitParticle(word) {
                    tokens.append((start + split.offset, split.suffix, split.kana))
                    hasParticleSplit = true
                }
                break
            }
            tokens.append((start, word, kana))
            if start == 0 { break }
            i = start
            while i > 0, chars[i - 1] == " " { i -= 1 }
        }
        // 先頭側に残った記号だけの語は、前の英文に属するので打ち直さない
        while let earliest = tokens.last, !earliest.word.contains(where: \.isLetter) { tokens.removeLast() }

        guard let first = tokens.last else {
            return Judgment(convert: false, spans: [], deleteCount: 0, reason: "ローマ字ではない")
        }
        let hasSpacedParticle = !hasParticleSplit && isSpacedParticle(chars: chars, earliest: first)
        tokens.reverse()

        let romaji = tokens.map(\.word).joined()
        let kana = tokens.map(\.kana).joined()
        var result = Judgment(convert: false, spans: [.kana(romaji: romaji, kana: kana)],
                              deleteCount: chars.count - first.start, reason: "")

        var letters = 0
        var japaneseLetters = 0
        for (index, t) in tokens.enumerated() {
            let w = t.word.filter(\.isLetter)
            letters += w.count
            if ((hasParticleSplit || hasSpacedParticle) && index == 0) || !isEnglish(w) {
                japaneseLetters += w.count
            }
        }

        if hasSpacedParticle && remainderBelowJapaneseRatio(tokens) {
            result.reason = "助詞の後ろが英単語"
        } else if !hasParticleSplit && !hasSpacedParticle && letters < minLetters {
            result.reason = "短すぎる (\(letters) < \(minLetters))"
        } else if japaneseLetters == 0 || Double(japaneseLetters) / Double(letters) < minJapaneseRatio {
            result.reason = "英単語が多い"
        } else {
            result.convert = true
            result.reason = "日本語と判定"
        }
        return result
    }

    /// "korehatestwo" → これは + test + を。末尾の 1 語が「ローマ字＋英単語＋助詞」のときだけ分割する
    private func judgeGluedEnglish(chars: [Character], end: Int) -> Judgment? {
        var start = end
        while start > 0, chars[start - 1] != " " { start -= 1 }
        let word = String(chars[start..<end])
        guard Romaji.toKana(word) == nil, splitParticle(word) == nil,
              let spans = splitGluedEnglish(word) else { return nil }
        return Judgment(convert: true, spans: spans, deleteCount: chars.count - start,
                        reason: "ローマ字・英単語・助詞の連結と判定")
    }

    static let minGluedEnglishLength = 4

    func splitGluedEnglish(_ word: String) -> [Span]? {
        let chars = Array(word)
        guard !isEnglish(word) else { return nil }
        for suffixStart in 0..<chars.count {
            let head = chars[..<suffixStart]
            guard head.count >= minLetters + Self.minGluedEnglishLength,
                  head.allSatisfy({ $0.isASCII && $0.isLowercase }) else { continue }
            let suffix = String(chars[suffixStart...])
            guard isParticleChain(suffix), let suffixKana = Romaji.toKana(suffix) else { continue }
            let suffixLetters = suffix.filter(\.isLetter)
            if !Self.particles.contains(suffixLetters), isEnglish(suffixLetters) { continue }

            for split in minLetters...(head.count - Self.minGluedEnglishLength) {
                let reading = String(head[..<split])
                let english = String(head[split...])
                guard englishWords.contains(english),
                      Romaji.toKana(english) == nil,
                      !englishWords.contains(english + suffixLetters),
                      Romaji.toKana(reading) != nil,
                      !isEnglish(reading) else { continue }
                return [.kana(romaji: reading, kana: Romaji.toKana(reading)!),
                        .literal(english),
                        .kana(romaji: suffix, kana: suffixKana)]
            }
        }
        return nil
    }

    /// 英文の中の to / no / he / ya / de（de facto, Tour de France）は助詞ではないので、英文では使わない助詞だけを対象にする
    static let spacedLiteralTailParticles: Set<String> = ["ha", "ga", "wo", "ni", "mo"]

    /// "repository ni push" → repository + に + " push"。助詞より後ろがローマ字でない語（英単語）だけのとき、助詞だけを打ち直す
    private func judgeSpacedLiteralTail(chars: [Character], end: Int) -> Judgment? {
        var words: [(start: Int, end: Int, text: String)] = []
        var i = 0
        while i < end {
            if chars[i] == " " { i += 1; continue }
            let start = i
            while i < end, chars[i] != " " { i += 1 }
            words.append((start, i, String(chars[start..<i])))
        }

        var hasUnreadableAfter = false
        for index in stride(from: words.count - 1, through: 1, by: -1) {
            let word = words[index]
            if index < words.count - 1, hasUnreadableAfter,
               Self.spacedLiteralTailParticles.contains(word.text),
               isSpacedEnglishWord(words[index - 1].text),
               let kana = Romaji.toKana(word.text) {
                return Judgment(
                    convert: true,
                    spans: [.kana(romaji: word.text, kana: kana),
                            .literal(String(chars[word.end..<chars.count]))],
                    deleteCount: chars.count - word.start,
                    reason: "英単語・助詞・英単語と判定")
            }
            let unreadable = Romaji.toKana(word.text) == nil
            guard unreadable || isEnglish(word.text.lowercased()) else { return nil }
            hasUnreadableAfter = hasUnreadableAfter || unreadable
        }
        return nil
    }

    /// 英単語の直後に付く助詞・語尾。この組み合わせだけで後半ができている場合に限って分割する
    static let particles: Set<String> = [
        "ha", "ga", "wo", "ni", "de", "no", "mo", "to", "ka", "ne", "yo", "da", "ya",
        "desu", "deshita", "desho", "deshou", "dayo", "dane", "dakedo", "janai", "jan",
        "tte", "toka", "kara", "made", "dake", "demo", "nara", "nano", "nanda", "mitai",
        "ppoi", "kedo", "yone", "kana", "kamo", "yori", "suru", "shita", "shite", "shitai",
        "shinai", "shimasu", "shimashita", "dekiru", "dekita", "sareta", "saseru",
        "-", ",", ".", "?", "!",
    ]
    static let maxParticleLength = particles.map(\.count).max()!

    /// made / demo / nano は助詞表にもある英単語。
    static let englishHomographParticles: Set<String> = ["made", "demo", "nano"]

    /// 4 文字以上の助詞・語尾。to / no / ya は短いのでここには入らず、辞書の判定のまま。
    static let japaneseEndings: Set<String> = Set(
        particles.filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) }
    ).subtracting(englishHomographParticles)

    static let bareSpacedParticles: Set<String> = [
        "ha", "ga", "wo", "ni", "de", "mo",
        "kara", "yori", "dake", "nara", "toka",
    ]

    static let englishWordParticles: Set<String> = ["to", "no", "he", "ya"]

    static let spacedParticles: Set<String> = bareSpacedParticles.union(englishWordParticles)

    /// "repositoryha" → ("ha", "は")。前半が英単語で、後半が助詞の組み合わせのときだけ分割する
    func splitParticle(_ word: String) -> (offset: Int, suffix: String, kana: String)? {
        let chars = Array(word)
        guard !isEnglish(word.lowercased()) else { return nil }

        for offset in 2..<max(2, chars.count) {
            let prefix = String(chars[..<offset])
            let suffix = String(chars[offset...])
            guard isParticleChain(suffix), isEnglishPrefix(prefix),
                  let kana = Romaji.toKana(suffix) else { continue }
            // "createfilemode" の mode のように後半が英単語なら、英単語の途中で切っている
            let suffixLetters = suffix.filter(\.isLetter)
            if !Self.particles.contains(suffixLetters), isEnglish(suffixLetters) { continue }
            if cutsInsideDictionaryWord(prefix: prefix, suffixLetters: suffixLetters) { continue }
            return (offset, suffix, kana)
        }
        return nil
    }

    private func cutsInsideDictionaryWord(prefix: String, suffixLetters: String) -> Bool {
        guard let last = Self.segments(prefix).last else { return false }
        return englishWords.contains((last + suffixLetters).lowercased())
    }

    /// 前半として認める語。辞書にある英単語 1 語か、GitHub / API / v2 のような大文字・数字混じりの語
    func isEnglishPrefix(_ prefix: String) -> Bool {
        guard prefix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        // 複合語まで認めると createfile+mode のような識別子を拾うため、辞書の 1 語に限る
        if prefix.count >= 3, englishWords.contains(prefix.lowercased()) { return true }

        // 先頭だけ大文字（Canada, Toronto）は地名などでよくあるので認めない
        guard prefix.dropFirst().contains(where: \.isUppercase) || prefix.contains(where: \.isNumber),
              let last = Self.segments(prefix).last else { return false }
        // 最後の区切りが単語として終わっていること（URLenco+de, 227li+ne を除く）
        if last.allSatisfy(\.isNumber) { return true }
        if last.count >= 2, last.allSatisfy(\.isUppercase) { return true }
        return last.count >= 3 && englishWords.contains(last.lowercased())
    }

    /// "GitHub" → ["Git", "Hub"], "URLencode" → ["URL", "encode"], "v2" → ["v", "2"]
    static func segments(_ s: String) -> [String] {
        let chars = Array(s)
        var result: [String] = []
        var current = ""
        for (i, c) in chars.enumerated() {
            if let p = current.last {
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let boundary = p.isNumber != c.isNumber
                    || (p.isLowercase && c.isUppercase)
                    || (p.isUppercase && c.isUppercase && next?.isLowercase == true)
                    || (p.isUppercase && c.isLowercase && current.count > 1 && current.allSatisfy(\.isUppercase))
                if boundary {
                    result.append(current)
                    current = ""
                }
            }
            current.append(c)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    func isParticleChain(_ s: String) -> Bool {
        let chars = Array(s)
        guard !chars.isEmpty else { return false }
        var reachable = [Bool](repeating: false, count: chars.count + 1)
        reachable[0] = true
        for i in 0..<chars.count where reachable[i] {
            for len in 1...min(Self.maxParticleLength, chars.count - i)
            where Self.particles.contains(String(chars[i..<i + len])) {
                reachable[i + len] = true
            }
        }
        return reachable[chars.count] && chars.contains(where: \.isLetter)
    }

    private func isSpacedParticle(
        chars: [Character], earliest: (start: Int, word: String, kana: String)
    ) -> Bool {
        guard let particle = Self.spacedParticleLetters(earliest.word),
              let anchor = previousWord(in: chars, before: earliest.start) else { return false }
        return isSpacedAnchor(anchor, particle: particle)
    }

    static func spacedParticleLetters(_ token: String) -> String? {
        var letters = ""
        var sawPunctuation = false
        for c in token {
            if c.isLetter {
                if sawPunctuation { return nil }
                letters.append(c)
            } else if Romaji.punctuation[c] != nil {
                sawPunctuation = true
            } else {
                return nil
            }
        }
        guard Self.spacedParticles.contains(letters) else { return nil }
        return letters
    }

    private func previousWord(in chars: [Character], before index: Int) -> String? {
        var i = index
        while i > 0, chars[i - 1] == " " { i -= 1 }
        guard i < index, i > 0 else { return nil }
        let end = i
        var start = end
        while start > 0, chars[start - 1] != " " { start -= 1 }
        guard start < end else { return nil }
        return String(chars[start..<end])
    }

    private func isSpacedAnchor(_ word: String, particle: String) -> Bool {
        guard isSpacedEnglishWord(word) else { return false }
        if Self.englishWordParticles.contains(particle) {
            return isTechnicalToken(word)
        }
        return true
    }

    private func isSpacedEnglishWord(_ word: String) -> Bool {
        if isEnglishPrefix(word) { return true }
        return word.count >= 3
            && word.allSatisfy({ $0.isASCII && $0.isLetter })
            && word.first?.isUppercase == true
    }

    private func isTechnicalToken(_ word: String) -> Bool {
        let chars = Array(word)
        guard chars.count >= 2,
              chars.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        if chars.contains(where: \.isNumber) { return true }
        if chars.contains(where: \.isLowercase) {
            return chars.dropFirst().contains(where: \.isUppercase)
        }
        return chars.count >= 3 && chars.allSatisfy(\.isUppercase)
    }

    private func remainderBelowJapaneseRatio(_ tokens: [(start: Int, word: String, kana: String)]) -> Bool {
        var letters = 0
        var japanese = 0
        for t in tokens.dropFirst() {
            let w = String(t.word.filter(\.isLetter))
            guard !w.isEmpty else { continue }
            letters += w.count
            if !isEnglish(w) { japanese += w.count }
        }
        guard letters > 0 else { return false }
        return japanese == 0 || Double(japanese) / Double(letters) < minJapaneseRatio
    }
}

extension Detector {
    /// 入力欄でカーソルの直前にある英単語の後ろに、英数モードで打った文字（typed）が続くとして判定する。
    /// かなモードで英単語を打って確定し、英数モードに切り替えて助詞だけを打った場合（"Draft" + "de"）は、
    /// typed だけでは短すぎて判定できないため、入力欄の直前の文字（context）を前につなぐ。
    /// 打ち直すのは typed の中だけで、context の文字は消さない
    public func judge(_ typed: String, after context: String) -> Judgment {
        let own = judge(typed)
        guard !own.convert else { return own }
        let word = Self.trailingWord(of: context)
        guard !word.isEmpty else { return own }
        var joined = judge(word + typed)
        guard joined.convert, joined.deleteCount <= typed.count else { return own }
        joined.reason += "（入力欄の直前の \(word.count) 文字とつないで判定）"
        return joined
    }

    /// 末尾のスペースと、その前に続く ASCII の英数字。"PRはDraft" → "Draft"、"push origin " → "origin "
    static func trailingWord(of context: String) -> String {
        let chars = Array(context)
        var i = chars.count
        while i > 0, chars[i - 1] == " " { i -= 1 }
        let spaceStart = i
        while i > 0, chars[i - 1].isASCII, chars[i - 1].isLetter || chars[i - 1].isNumber { i -= 1 }
        guard i < spaceStart else { return "" }
        return String(chars[i...])
    }
}
