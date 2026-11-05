extension Detector {
    static let builtinEnglish: [String] = [
        "been", "seen", "taken", "given", "eaten", "beaten", "bitten", "hidden",
        "ridden", "bidden", "sudden", "happen", "kitten", "gotten", "chosen",
        "risen", "woken", "women", "wooden", "token", "open", "amen", "omen",
        "season", "reason", "nation", "session", "mission", "union", "onion",
        "opinion", "domain", "remain", "again", "teen", "keen", "noon", "moon", "soon",
        "info", "repo", "todo", "nano", "inode", "sudo", "ubuntu", "debian", "mongo",
        "deno", "rebase", "goroutine", "tokenize", "memoize", "demo", "promo", "techno",
        "website", "callsite", "campsite", "worksite", "jobsite", "offsite", "onsite", "homesite",
        "pesto", "github", "gitlab", "golang", "docker", "python", "javascript",
        "typescript", "slack", "claude", "iphone", "macos", "linux", "json", "yaml", "howto",
        "haha", "hahaha", "hehe", "meme", "gonna", "wanna", "kinda", "gotta", "sorta", "emo",
    ]

    static let minGluedEnglishLength = 4

    static let spacedLiteralTailParticles: Set<String> = ["ha", "ga", "wo", "ni", "mo"]

    static let particles: Set<String> = [
        "ha", "ga", "wo", "ni", "de", "no", "mo", "to", "ka", "ne", "yo", "da", "ya",
        "desu", "deshita", "desho", "deshou", "dayo", "dane", "dakedo", "janai", "jan",
        "tte", "toka", "kara", "made", "dake", "demo", "nara", "nano", "nanda", "mitai",
        "ppoi", "kedo", "yone", "kana", "kamo", "yori", "suru", "shita", "shite", "shitai",
        "shinai", "shimasu", "shimashita", "dekiru", "dekita", "sareta", "saseru",
        "kudasai", "kure", "kureru", "kureta", "hoshii", "morau", "moratta", "moraeru",
        "onegai", "onegaishimasu", "masu", "mashita", "masen", "mashou", "imasu", "imashita",
        "shiteru", "shiteta", "shitemasu", "shiteiru", "shiteita", "shiteoku", "shiteoite",
        "shitearu", "shitara", "shitemo", "shimasen", "shimashou", "shiyou", "sareru", "saremasu",
        "dekinai", "dekimasu", "dekimasen", "teiru", "teita", "teru", "tara", "tari",
        "nai", "nakatta", "naku", "nakute", "rashii", "shirenai",
        "-", ",", ".", "?", "!",
    ]

    static let particleSpellings: Set<String> = Set(particles.flatMap(spellingVariants))

    static let spellingAlternatives: [(String, String)] = [
        ("shi", "si"), ("chi", "ti"), ("tsu", "tu"), ("sha", "sya"), ("shu", "syu"), ("sho", "syo"),
        ("ja", "zya"), ("ju", "zyu"), ("jo", "zyo"), ("ji", "zi"),
    ]

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

    static let englishHomographParticles: Set<String> = ["made", "demo", "nano", "masu", "tara", "tari"]

    static let japaneseEndings: Set<String> = Set(
        particles.filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) }
    ).subtracting(englishHomographParticles)

    static let compoundEndings: Set<String> = Set(
        particleSpellings.filter { $0.count >= 4 && $0.allSatisfy(\.isLetter) }
    ).subtracting(englishHomographParticles)

    static let bareSpacedParticles: Set<String> = [
        "ha", "ga", "wo", "ni", "de", "mo",
        "kara", "yori", "dake", "nara", "toka",
    ]

    static let englishWordParticles: Set<String> = ["to", "no", "he", "ya"]

    static let spacedParticles: Set<String> = bareSpacedParticles.union(englishWordParticles)

    static let counters: Set<String> = Set([
        "ji", "jikan", "fun", "pun", "byou", "nichi", "gatsu", "kagetsu", "nen", "shuukan",
        "kai", "kaime", "ko", "hon", "bon", "pon", "mai", "nin", "en", "sai",
        "ban", "banme", "bai", "ken", "dai", "man", "oku", "sen", "hyaku", "wari", "tsu",
    ].flatMap(spellingVariants))
}
