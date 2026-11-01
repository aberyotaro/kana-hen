import Foundation

struct Config: Decodable {
    /// 変換の対象とする最小の文字数
    var minLetters = 4
    /// 英単語でないトークンが占める文字数の割合の下限
    var minJapaneseRatio = 0.5
    /// 入力ソースを切り替えてから打ち直すまでの待ち時間
    var switchDelayMs = 60
    /// 指定するとそのアプリだけで動く（bundle ID）。空ならすべてのアプリ
    var enabledApps: [String] = []
    /// 動かさないアプリ（bundle ID）
    var disabledApps: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "org.alacritty",
    ]
    /// 切り替え先の入力ソース ID。nil なら有効な日本語入力から自動で選ぶ
    var japaneseInputSourceID: String?

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/no-more-gobaku")

    static func load() -> Config {
        let url = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            fputs("no-more-gobaku: \(url.path) を読めませんでした: \(error)\n", stderr)
            exit(1)
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        minLetters = try c.decodeIfPresent(Int.self, forKey: .minLetters) ?? d.minLetters
        minJapaneseRatio = try c.decodeIfPresent(Double.self, forKey: .minJapaneseRatio) ?? d.minJapaneseRatio
        switchDelayMs = try c.decodeIfPresent(Int.self, forKey: .switchDelayMs) ?? d.switchDelayMs
        enabledApps = try c.decodeIfPresent([String].self, forKey: .enabledApps) ?? d.enabledApps
        disabledApps = try c.decodeIfPresent([String].self, forKey: .disabledApps) ?? d.disabledApps
        japaneseInputSourceID = try c.decodeIfPresent(String.self, forKey: .japaneseInputSourceID)
    }

    enum CodingKeys: String, CodingKey {
        case minLetters, minJapaneseRatio, switchDelayMs, enabledApps, disabledApps, japaneseInputSourceID
    }

    func isEnabled(for bundleID: String?) -> Bool {
        guard let id = bundleID else { return enabledApps.isEmpty }
        if disabledApps.contains(id) { return false }
        return enabledApps.isEmpty || enabledApps.contains(id)
    }
}
