extension Detector {
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
        // site は「して」の別の綴りなので、辞書にない -site の複合語は英語として載せる
        "website", "callsite", "campsite", "worksite", "jobsite", "offsite", "onsite", "homesite",
        "pesto", "github", "gitlab", "golang", "docker", "python", "javascript",
        "typescript", "slack", "claude", "iphone", "macos", "linux", "json", "yaml", "howto",
        // チャットでよく打つ口語。辞書にないうえ、ローマ字としても読めてしまう
        "haha", "hahaha", "hehe", "meme", "gonna", "wanna", "kinda", "gotta", "sorta", "emo",
    ]

    static let minGluedEnglishLength = 4

    /// 英文の中の to / no / he / ya / de（de facto, Tour de France）は助詞ではないので、英文では使わない助詞だけを対象にする
    static let spacedLiteralTailParticles: Set<String> = ["ha", "ga", "wo", "ni", "mo"]

    /// 英単語の直後に付く助詞・語尾。この組み合わせだけで後半ができている場合に限って分割する
    static let particles: Set<String> = [
        "ha", "ga", "wo", "ni", "de", "no", "mo", "to", "ka", "ne", "yo", "da", "ya",
        "desu", "deshita", "desho", "deshou", "dayo", "dane", "dakedo", "janai", "jan",
        "tte", "toka", "kara", "made", "dake", "demo", "nara", "nano", "nanda", "mitai",
        "ppoi", "kedo", "yone", "kana", "kamo", "yori", "suru", "shita", "shite", "shitai",
        "shinai", "shimasu", "shimashita", "dekiru", "dekita", "sareta", "saseru",
        // してください・しています などの語尾。ite / iru / you は "SQLite" "thankyou" のように
        // 英語の語尾にもなるので、単独では入れず shite などと組にした形だけを入れる
        "kudasai", "kure", "kureru", "kureta", "hoshii", "morau", "moratta", "moraeru",
        "onegai", "onegaishimasu", "masu", "mashita", "masen", "mashou", "imasu", "imashita",
        "shiteru", "shiteta", "shitemasu", "shiteiru", "shiteita", "shiteoku", "shiteoite",
        "shitearu", "shitara", "shitemo", "shimasen", "shimashou", "shiyou", "sareru", "saremasu",
        "dekinai", "dekimasu", "dekimasen", "teiru", "teita", "teru", "tara", "tari",
        "nai", "nakatta", "naku", "nakute", "rashii", "shirenai",
        "-", ",", ".", "?", "!",
    ]

    /// 訓令式などの別の書き方も含めた助詞・語尾。"site"（して）のように英単語と同じ綴りになるものがあるため、
    /// japaneseEndings には入れず、英単語の後ろに続く助詞の連なりとしてだけ認める
    static let particleSpellings: Set<String> = Set(particles.flatMap(spellingVariants))

    static let spellingAlternatives: [(String, String)] = [
        ("shi", "si"), ("chi", "ti"), ("tsu", "tu"), ("sha", "sya"), ("shu", "syu"), ("sho", "syo"),
        ("ja", "zya"), ("ju", "zyu"), ("jo", "zyo"), ("ji", "zi"),
    ]

    /// "deshita" → deshita, desita
    static func spellingVariants(_ word: String) -> [String] {
        var results = [""]
        var rest = Substring(word)
        while !rest.isEmpty {
            if let (from, to) = spellingAlternatives.first(where: { rest.hasPrefix($0.0) }) {
                results = results.flatMap { [$0 + from, $0 + to] }
                rest = rest.dropFirst(from.count)
            } else {
                let c = rest.removeFirst()
                results = results.map { $0 + String(c) }
            }
        }
        return results
    }

    static let maxParticleLength = particleSpellings.map(\.count).max()!

    /// made / demo / nano は助詞表にもある英単語。masu / tara / tari は辞書にある語（地名・人名など）
    static let englishHomographParticles: Set<String> = ["made", "demo", "nano", "masu", "tara", "tari"]

    /// 4 文字以上の助詞・語尾。to / no / ya は短いのでここには入らず、辞書の判定のまま。
    static let japaneseEndings: Set<String> = Set(
        particles.filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) }
    ).subtracting(englishHomographParticles)

    /// 英単語 2 つの複合語かを調べるとき、後半として英単語とみなさない語尾。別の綴りも含める
    static let compoundEndings: Set<String> = Set(
        particleSpellings.filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) }
    ).subtracting(englishHomographParticles)

    static let bareSpacedParticles: Set<String> = [
        "ha", "ga", "wo", "ni", "de", "mo",
        "kara", "yori", "dake", "nara", "toka", "tte",
    ]

    static let englishWordParticles: Set<String> = ["to", "no", "he", "ya"]

    static let spacedParticles: Set<String> = bareSpacedParticles.union(englishWordParticles)

    /// 数字の直後に付く助数詞のうち、英単語と同じ綴りか 1 文字のもの。"18ji" → 18じ。
    /// ここにない単位も、英単語でないローマ字なら数字の後ろで変換する（Detector.isNumberUnit）。
    /// 末尾の ん は nn とも打つ（6kenn）。do（度）は 3do（3DO）と紛れるので入れない
    static let counters: Set<String> = Set([
        "ji", "jikan", "fun", "pun", "byou", "nichi", "gatsu", "kagetsu", "nen", "shuukan",
        "kai", "kaime", "ko", "hon", "bon", "pon", "mai", "nin", "en", "sai",
        "ban", "banme", "bai", "ken", "dai", "man", "oku", "sen", "hyaku", "wari", "tsu",
    ].flatMap(spellingVariants).flatMap { $0.hasSuffix("n") ? [$0, $0 + "n"] : [$0] })
}
