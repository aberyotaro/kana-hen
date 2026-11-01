import Carbon

enum InputSource {
    static func id(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    static func currentID() -> String? {
        id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
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
