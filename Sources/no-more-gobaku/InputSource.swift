import Carbon

enum InputSource {
    static func id(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// 今の入力が英数（キーを押した文字がそのまま入る）かどうか。
    /// 「かなでなければ英数」とすると、カタカナや中国語入力の確定の Enter まで横取りしてしまうので、
    /// キーボード配列そのもの（ABC など）と、日本語入力の英数モード（ID が .Roman で終わる）に限る
    static func isCurrentASCII() -> Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceType),
           Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() == kTISTypeKeyboardLayout {
            return true
        }
        return id(of: source)?.hasSuffix(".Roman") ?? false
    }

    /// ひらがな（かな）入力のモードかどうか。ことえり・Google 日本語入力・ATOK の ID に対応する
    static func isKanaMode(_ id: String) -> Bool {
        id.hasSuffix(".Japanese") || id.hasSuffix(".Japanese.base") || id.hasSuffix(".Hiragana")
    }

    static func enabled() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return [] }
        return (list as NSArray).map { $0 as! TISInputSource }
    }

    static func find(_ wanted: String?) -> TISInputSource? {
        let sources = enabled()
        if let wanted {
            return sources.first { id(of: $0) == wanted }
        }
        return sources.first { id(of: $0).map(isKanaMode) ?? false }
    }
}
