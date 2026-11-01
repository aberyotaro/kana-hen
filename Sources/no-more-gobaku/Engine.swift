import Cocoa
import Carbon
import GobakuCore

/// 自分が送ったキーイベントの目印
private let syntheticMarker: Int64 = 0x524F_4D41

private enum Key {
    static let returnKey: Int64 = 36
    static let enter: Int64 = 76
    static let delete: CGKeyCode = 51
    /// JIS の「かな」キー。US 配列の Mac でも日本語入力に切り替わる
    static let kana: CGKeyCode = 104

    /// US / JIS 配列で共通の仮想キーコード（文字, キーコード, Shift が必要か）
    static let codes: [Character: (CGKeyCode, Bool)] = {
        var m: [Character: (CGKeyCode, Bool)] = [:]
        let letters: [(Character, CGKeyCode)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
            ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
            ("y", 16), ("t", 17), ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37),
            ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        for (c, k) in letters { m[c] = (k, false) }
        m["-"] = (27, false)
        m[","] = (43, false)
        m["."] = (47, false)
        m["?"] = (44, true)
        m["!"] = (18, true)
        return m
    }()
}

final class Engine {
    let detector: Detector
    let config: Config
    let verbose: Bool

    private var buffer = InputBuffer()
    private var converting = false
    /// 変換中に届いた本物のキー。打ち直しより先に入らないよう溜めておき、打ち直しのあとに流す
    private var heldDuringConversion: [CGEvent] = []
    private var tap: CFMachPort?
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    init(detector: Detector, config: Config, verbose: Bool) {
        self.detector = detector
        self.config = config
        self.verbose = verbose
    }

    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let engine = Unmanaged<Engine>.fromOpaque(refcon!).takeUnretainedValue()
                return engine.handle(type, event)
            },
            userInfo: refcon
        ) else { return false }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // 前面アプリが変わったらカーソル位置が分からなくなる
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.buffer.reset() }
        return true
    }

    /// 入力モードは変更通知だと取りこぼすことがあるため、キーごとに問い合わせる（数 µs）
    private func isKanaMode() -> Bool {
        InputSource.currentID().map(InputSource.isKanaMode) ?? false
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            buffer.reset()
        case .keyDown:
            return handleKeyDown(event) ? pass : nil
        default:
            break
        }
        return pass
    }

    /// キーをそのまま通すなら true
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker { return true }
        if converting {
            if let copy = event.copy() { heldDuringConversion.append(copy) }
            return false
        }
        if isKanaMode() {
            buffer.reset()
            return true
        }

        let flags = event.flags
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            buffer.reset()
            return true
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case Key.returnKey, Key.enter:
            let text = buffer.text
            buffer.reset()
            if flags.contains(.maskShift) { return true }
            return !tryConvert(text)
        case Int64(Key.delete):
            buffer.backspace()
            return true
        default:
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            if length == 1, (0x20..<0x7F).contains(chars[0]), let scalar = Unicode.Scalar(chars[0]) {
                buffer.append(Character(scalar))
            } else {
                // 矢印・Tab・Esc などでカーソル位置が分からなくなる
                buffer.reset()
            }
            return true
        }
    }

    /// 変換を始めたら true（Enter は握りつぶす）
    private func tryConvert(_ text: String) -> Bool {
        guard !text.isEmpty else {
            log("Enter: 英数モードで打った文字がないため何もしません")
            return false
        }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard config.isEnabled(for: app) else {
            log("Enter: \(app ?? "不明なアプリ") では無効にしています")
            return false
        }
        let judgment = detector.judge(text)
        guard judgment.convert else {
            log("Enter: 変換しません（\(judgment.reason)）")
            return false
        }
        guard !IsSecureEventInputEnabled() else { return false }
        guard InputSource.find(config.japaneseInputSourceID) != nil else {
            log("日本語の入力ソースが見つからないため変換しません")
            return false
        }
        // 記録と入力欄がずれていると、打っていない文字まで Backspace で消してしまう。
        // 読めない欄（アクセシビリティ情報を出さないアプリ）は確認できないので従来どおり進める
        let typed = String(text.suffix(judgment.deleteCount))
        switch Accessibility.focusedText() {
        case .success(let field):
            guard field.endsAtCaret(with: typed) else {
                log("Enter: 入力欄の内容が記録と一致しないため変換しません")
                return false
            }
        case .failure(let error):
            log("Enter: 入力欄を確認できないまま変換します（\(error)）")
        }
        log("\(judgment.romaji) → \(judgment.kana)")

        converting = true
        DispatchQueue.main.async { [self] in
            for _ in 0..<judgment.deleteCount { post(Key.delete) }
            // TISSelectInputSource は日本語入力だとメニューバーだけ切り替わり、
            // 入力中のアプリに反映されないことがあるため、かなキーを送る
            post(Key.kana)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.switchDelayMs)) { [self] in
                for c in judgment.romaji {
                    if let (code, shift) = Key.codes[c] { post(code, shift: shift) }
                }
                converting = false
                replayHeldKeys()
            }
        }
        return true
    }

    private func replayHeldKeys() {
        let held = heldDuringConversion
        heldDuringConversion = []
        for down in held {
            down.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            down.post(tap: .cghidEventTap)
            // 本物の keyUp は握りつぶした keyDown より先にアプリへ届いているので、対になる keyUp を送り直す
            if let up = down.copy() {
                up.type = .keyUp
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func post(_ code: CGKeyCode, shift: Bool = false) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down) else { continue }
            e.flags = shift ? .maskShift : []
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    private func log(_ message: String) {
        if verbose { print("no-more-gobaku: \(message)") }
    }
}
