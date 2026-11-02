import Foundation
import GobakuCore

var failures = 0
func expect(_ ok: Bool, _ message: @autoclosure () -> String) {
    if !ok {
        failures += 1
        print("FAIL: \(message())")
    }
}

let detector = Detector(englishWords: Detector.loadEnglishWords(paths: ["/usr/share/dict/words"]))

let kanaCases: [(String, String)] = [
    ("kyouhaiitenkidesune", "きょうはいいてんきですね"),
    ("konnnichiha", "こんにちは"),
    ("matcha", "まっちゃ"),
    ("shinbun", "しんぶん"),
    ("kanzi", "かんじ"),
    ("konya", "こにゃ"),
    ("konnya", "こんや"),
    ("sounandesune.", "そうなんですね。"),
    ("nanisore?", "なにそれ？"),
    ("ra-men", "らーめん"),
]
for (input, kana) in kanaCases {
    let got = Romaji.toKana(input)
    expect(got == kana, "toKana(\(input)) = \(got ?? "nil"), want \(kana)")
}

for input in ["hello", "code", "think", "test", "kubernetes", "akk", "API", "lake"] {
    expect(Romaji.toKana(input) == nil, "toKana(\(input)) should be nil")
}

// 日本語のつもりで英数モードのまま打ちそうな文
let japanese = [
    "kyouhaiitenkidesune", "arigatou", "arigatougozaimasu", "yoroshikuonegaishimasu",
    "sounandesune", "nanisore?", "matcha", "ikimasu", "sorede", "genkidesuka",
    "watashihatanakadesu", "kyouha tenki", "ashitanokaigi", "kakuninshimasu",
    "shiyouwokakunin", "tesutogaotiteru", "mendoukusai", "tabun", "chottomatte",
    "nihongo", "sumimasen", "otsukaresamadesu", "shinkansen",
    "korehananidesuka", "doumodesu", "daijoubu", "naruhodo", "ryoukaidesu",
]
for input in japanese {
    let j = detector.judge(input)
    expect(j.convert, "should convert \(input.debugDescription): \(j.reason)")
}

// 英数モードで正しく打った英語は変換しない
let english = [
    "Thanks for the update", "see you tomorrow", "go home", "same", "made", "taken",
    "this is fine", "anime", "here", "women", "domain", "hidden", "notion", "sure",
    "hope so", "database", "metadata", "runtime", "basename", "automation", "info",
    "repo", "todo", "sudo", "manpage", "tokenization", "configuration", "hai", "ok go",
]
for input in english {
    let j = detector.judge(input)
    expect(!j.convert, "should not convert \(input.debugDescription): \(j.romaji) → \(j.kana)")
}

do {
    let j = detector.judge("OK, kyouha tenki ")
    expect(j.convert && j.romaji == "kyouhatenki", "multi-token: \(j)")
    expect(j.deleteCount == "kyouha tenki ".count, "multi-token deleteCount: \(j.deleteCount)")
}
do {
    let j = detector.judge("I said sounandesune")
    expect(j.convert && j.deleteCount == "sounandesune".count, "keeps preceding English: \(j)")
}

// 英単語＋助詞は助詞の部分だけを変換する
let particleCases: [(String, String, String)] = [
    ("git repositoryha", "ha", "は"),
    ("testdesu", "desu", "です"),
    ("APIga", "ga", "が"),
    ("GitHubdesuka?", "desuka?", "ですか？"),
    ("dockerttedesune", "ttedesune", "ってですね"),
    ("v2toka", "toka", "とか"),
    ("githubha", "ha", "は"),
    ("updateshitai", "shitai", "したい"),
    ("repositoryha tsukaeru?", "hatsukaeru?", "はつかえる？"),
    ("repositoryto", "to", "と"),
    ("repositoryno", "no", "の"),
    ("repositorytoka", "toka", "とか"),
]
for (input, romaji, kana) in particleCases {
    let j = detector.judge(input)
    expect(j.convert && j.romaji == romaji && j.kana == kana,
           "particle \(input.debugDescription): \(j.romaji) → \(j.kana) [\(j.reason)]")
    let typedSuffix = input.hasSuffix("tsukaeru?") ? "ha tsukaeru?" : romaji
    expect(j.deleteCount == typedSuffix.count, "particle deleteCount \(input.debugDescription): \(j.deleteCount)")
}

let spacedParticleCases: [(String, String, String, String)] = [
    ("repository ha", "ha", "は", "ha"),
    ("repository ga", "ga", "が", "ga"),
    ("repository wo", "wo", "を", "wo"),
    ("repository ni", "ni", "に", "ni"),
    ("repository de", "de", "で", "de"),
    ("repository mo", "mo", "も", "mo"),
    ("repository kara", "kara", "から", "kara"),
    ("repository yori", "yori", "より", "yori"),
    ("repository dake", "dake", "だけ", "dake"),
    ("repository nara", "nara", "なら", "nara"),
    ("repository toka", "toka", "とか", "toka"),
    ("repository ha?", "ha?", "は？", "ha?"),
    ("git repository ha", "ha", "は", "ha"),
    ("repository ha ugokanai", "haugokanai", "はうごかない", "ha ugokanai"),
    ("code wo", "wo", "を", "wo"),
    ("test ga", "ga", "が", "ga"),
    ("bug de", "de", "で", "de"),
    ("file ni", "ni", "に", "ni"),
    ("PR wo", "wo", "を", "wo"),
    ("API ga", "ga", "が", "ga"),
    ("v2 ni", "ni", "に", "ni"),
    ("v2 no", "no", "の", "no"),
    ("API to", "to", "と", "to"),
    ("GitHub to", "to", "と", "to"),
    ("GitHub no", "no", "の", "no"),
    ("Kubernetes ha", "ha", "は", "ha"),
    ("repository to onaji", "toonaji", "とおなじ", "to onaji"),
    ("repository no hou", "nohou", "のほう", "no hou"),
    ("Kubernetes no pod ga ochiru", "gaochiru", "がおちる", "ga ochiru"),
    ("PR wo merge shita", "shita", "した", "shita"),
]
for (input, romaji, kana, deleting) in spacedParticleCases {
    let j = detector.judge(input)
    expect(j.convert && j.romaji == romaji && j.kana == kana,
           "spaced \(input.debugDescription): \(j.romaji) → \(j.kana) [\(j.reason)]")
    expect(j.deleteCount == deleting.count, "spaced deleteCount \(input.debugDescription): \(j.deleteCount)")
}

for input in [
    "git push origin main", "to do", "no change", "go home", "a ha",
    "want to", "have to", "going to", "according to", "open to",
    "thanks to", "return to", "default to", "related to", "close to", "next to",
    "introduction to", "commitment to", "configuration to", "implementation to",
    "say no", "and he", "see ya", "absolutely no", "definitely no",
    "go to", "hand made", "custom made",
    "repository to", "repository no", "repository he", "repository ya",
    "Kubernetes no", "Kubernetes to",
    "repository to do", "repository ha home", "API to do",
    "repository go", "repository do",
    "repository demo", "repository made", "repositorymade", "repositorydemo",
    "OK to", "PR to", "made",
] {
    let j = detector.judge(input)
    expect(!j.convert, "english must stay \(input.debugDescription): \(j.romaji) → \(j.kana) [\(j.reason)]")
}

// macOS の /usr/share/dict/words（web2）には shita, kana, dane がある。Linux の wamerican にはない。
do {
    var words = Detector.loadEnglishWords(paths: ["/usr/share/dict/words"])
    words.formUnion(["shita", "kana", "dane"])
    let mac = Detector(englishWords: words)
    let shita = mac.judge("PR wo merge shita")
    expect(shita.convert && shita.romaji == "shita" && shita.kana == "した",
           "dictionary shita still converts: \(shita.romaji) → \(shita.kana) [\(shita.reason)]")
    expect(shita.deleteCount == "shita".count, "dictionary shita deleteCount: \(shita.deleteCount)")
    let kana = mac.judge("kana")
    expect(kana.convert && kana.kana == "かな", "dictionary kana still converts: \(kana.romaji) → \(kana.kana) [\(kana.reason)]")
    let dane = mac.judge("dane")
    expect(dane.convert && dane.kana == "だね", "dictionary dane still converts: \(dane.romaji) → \(dane.kana) [\(dane.reason)]")
    expect(!mac.judge("made").convert, "made stays English beside those endings")
}

// 記号だけの語はローマ字の語に挟まれていれば一緒に打ち直し、前の英文側にあれば残す
do {
    let j = detector.judge("kyouha ?")
    expect(j.convert && j.romaji == "kyouha?" && j.kana == "きょうは？" && j.deleteCount == "kyouha ?".count,
           "trailing punctuation token: \(j)")
    let k = detector.judge("OK ? sounandesune")
    expect(k.convert && k.romaji == "sounandesune" && k.deleteCount == "sounandesune".count,
           "leading punctuation token stays: \(k)")
    expect(!detector.judge("OK ?").convert, "punctuation alone must not convert")
}

for input in ["meme", "haha", "lol hahaha", "gonna", "wanna", "kinda", "gotta"] {
    let j = detector.judge(input)
    expect(!j.convert, "chat slang must not convert \(input.debugDescription): \(j.romaji) → \(j.kana)")
}

// 英単語の一部が助詞に見えても分割しない
for input in ["machine", "release", "panda", "undone", "homemade", "Canada", "Toronto",
              "techno", "promo", "online", "lambda", "URLencode", "227line", "createfilemode",
              "howto", "httpsExampleGuide"] {
    let j = detector.judge(input)
    expect(!j.convert, "should not split \(input.debugDescription): \(j.romaji) → \(j.kana)")
}

do {
    let words: Set<String> = ["gui", "guide", "test"]
    let d = Detector(englishWords: words)
    let guide = d.judge("UserGuide")
    expect(!guide.convert, "UserGuide must stay intact: \(guide.romaji) → \(guide.kana)")
    let kept = d.judge("testga")
    expect(kept.convert && kept.romaji == "ga" && kept.kana == "が",
           "testga still splits the particle: \(kept.romaji) → \(kept.kana)")
}

do {
    var b = InputBuffer(limit: 5)
    for c in "abcdefg" { b.append(c) }
    expect(b.text == "cdefg", "buffer limit: \(b.text)")
    b.backspace()
    expect(b.text == "cdef", "buffer backspace: \(b.text)")
}

do {
    let t0 = Date()
    var b = InputBuffer(idleLimit: 30)
    for c in "kyou" { b.append(c, at: t0) }
    b.append("h", at: t0.addingTimeInterval(29))
    expect(b.text == "kyouh", "buffer keeps text within idle limit: \(b.text)")
    b.append("a", at: t0.addingTimeInterval(29 + 31))
    expect(b.text == "a", "buffer drops text after idle limit: \(b.text)")
}

do {
    let t0 = Date()
    var b = InputBuffer(idleLimit: 30)
    for c in "kyouha" { b.append(c, at: t0) }
    expect(b.consume(at: t0.addingTimeInterval(30)) == "kyouha", "enter at the idle limit still commits")
    for c in "kyouha" { b.append(c, at: t0) }
    expect(b.consume(at: t0.addingTimeInterval(31)) == "", "enter after idle discards")
    expect(b.text.isEmpty, "enter after idle leaves the buffer empty")
}

do {
    let t0 = Date()
    var b = InputBuffer(idleLimit: 30)
    for c in "kyou" { b.append(c, at: t0) }
    b.backspace(at: t0.addingTimeInterval(10))
    expect(b.text == "kyo", "backspace within idle deletes one character: \(b.text)")
    b.backspace(at: t0.addingTimeInterval(10 + 31))
    expect(b.text.isEmpty, "backspace after idle discards the buffer: \(b.text)")
}

// 消してよいのは、消す文字列がカーソル直前にあって選択がないときだけ
do {
    let field = FocusedText(text: "hello kyouha", caret: 12, selectionLength: 0)
    expect(field.endsAtCaret(with: "kyouha"), "caret suffix matches")
    expect(!field.endsAtCaret(with: "kyouhb"), "different text must not match")
    expect(!FocusedText(text: "hello kyouha", caret: 12, selectionLength: 3).endsAtCaret(with: "kyouha"),
           "selection left by autocomplete must not match")
    expect(!FocusedText(text: "kyouha world", caret: 12, selectionLength: 0).endsAtCaret(with: "kyouha"),
           "text elsewhere in the field must not match")
    expect(FocusedText(text: "kyouha world", caret: 6, selectionLength: 0).endsAtCaret(with: "kyouha"),
           "caret in the middle of the field")
    expect(!FocusedText(text: "ha", caret: 2, selectionLength: 0).endsAtCaret(with: "kyouha"),
           "field shorter than typed text must not match")
    expect(FocusedText(text: "絵文字😀 desu", caret: 10, selectionLength: 0).endsAtCaret(with: "desu"),
           "caret is in UTF-16 units")
}

if failures == 0 {
    print("OK")
} else {
    print("\(failures) failure(s)")
    exit(1)
}
