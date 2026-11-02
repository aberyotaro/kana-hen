import Foundation

public struct Judgment: Equatable {
    public var convert: Bool
    /// IME に打ち直すローマ字（単語間のスペースは除く）
    public var romaji: String
    public var kana: String
    /// 打ち直す前に Backspace で消す文字数（スペースを含む）
    public var deleteCount: Int
    public var reason: String
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
        if englishWords.contains(word) { return true }
        if word.contains("tion") || word.contains("sion") { return true }

        // 前半 3 文字以上・後半 4 文字以上の英単語 2 つに分けられるか。
        // 後半を 4 文字以上にするのは mat+cha (matcha) のような誤判定を避けるため
        let chars = Array(word)
        guard chars.count >= 7 else { return false }
        for split in 3...(chars.count - 4) {
            if englishWords.contains(String(chars[..<split])),
               englishWords.contains(String(chars[split...])) {
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
            return Judgment(convert: false, romaji: "", kana: "", deleteCount: 0, reason: "ローマ字ではない")
        }
        let hasSpacedParticle = !hasParticleSplit && isSpacedParticle(chars: chars, earliest: first)
        tokens.reverse()

        let romaji = tokens.map(\.word).joined()
        let kana = tokens.map(\.kana).joined()
        var result = Judgment(convert: false, romaji: romaji, kana: kana,
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
