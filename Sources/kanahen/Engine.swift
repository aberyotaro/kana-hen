import Cocoa
import Carbon
import GobakuCore

/// 自分が送ったキーイベントの目印
private let syntheticMarker: Int64 = 0x524F_4D41

private let diagTimestamp: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.timeZone = .current
    return f
}()

/// 常時ログ。打った文字・かな・文字数は渡さない（verbose と無関係に出る）
private func diag(_ message: String) {
    print("\(diagTimestamp.string(from: Date())) kanahen: \(message)")
}

private enum Key {
    static let returnKey: Int64 = 36
    static let enter: Int64 = 76
    static let delete: CGKeyCode = 51
    /// JIS の「かな」キー。US 配列の Mac でも日本語入力に切り替わる
    static let kana: CGKeyCode = 104
    /// JIS の「英数」キー
    static let eisu: CGKeyCode = 102

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
    private var inputMode = InputModeTracker()
    /// かなモードの変換待ちのうち、Shift+英字から始まる英字の区間
    private var composition = CompositionTracker()
    private var modeLagLogged = false
    private var converting = false
    private var enabledForFrontApp = true
    /// 変換中に届いた本物のキー。打ち直しより先に入らないよう溜めておき、打ち直しのあとに流す
    private var heldDuringConversion: [CGEvent] = []
    private var tap: CFMachPort?
    private var secureInputWasOn = false
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

        frontAppChanged(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.frontAppChanged(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        return true
    }

    private func frontAppChanged(_ app: NSRunningApplication?) {
        // 前面アプリが変わったらカーソル位置が分からなくなる
        buffer.reset()
        composition.reset()
        // 対象外のアプリ（ターミナルなど）では、打った文字を記録しない
        enabledForFrontApp = config.isEnabled(for: app?.bundleIdentifier)
        // Electron 製アプリは最初の問い合わせで入力欄を返さないので、Enter より前に準備させておく
        if enabledForFrontApp, let app { Accessibility.prepare(app.processIdentifier) }
    }


    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            diag(type == .tapDisabledByTimeout ? "event tap disabled (timeout)" : "event tap disabled (user input)")
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                diag("event tap re-enabled (enabled=\(CGEvent.tapIsEnabled(tap: tap)))")
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            buffer.reset()
            composition.reset()
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
        let secure = IsSecureEventInputEnabled()
        if secure != secureInputWasOn {
            secureInputWasOn = secure
            diag(secure ? "secure input on" : "secure input off")
        }
        if secure {
            buffer.reset()
            return true
        }
        if converting {
            if let copy = event.copy() { heldDuringConversion.append(copy) }
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == Int64(Key.eisu) || keyCode == Int64(Key.kana) {
            inputMode.modeKeyPressed(ascii: keyCode == Int64(Key.eisu))
            modeLagLogged = false
            buffer.reset()
            composition.reset()
            return true
        }
        // 入力モードは変更通知だと取りこぼすことがあるため、キーごとに問い合わせる
        let reported = InputSource.isCurrentASCII()
        let ascii = inputMode.isASCII(reported: reported)
        if ascii != reported, !modeLagLogged {
            modeLagLogged = true
            diag("input mode not yet switched after mode key; using the mode key")
        }
        if !enabledForFrontApp {
            buffer.reset()
            composition.reset()
            return true
        }
        if !ascii {
            buffer.reset()
            return handleKanaModeKey(event, keyCode: keyCode)
        }
        composition.reset()

        let flags = event.flags
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            buffer.reset()
            return true
        }

        switch keyCode {
        case Key.returnKey, Key.enter:
            let text = buffer.consume()
            if flags.contains(.maskShift) { return true }
            let started = DispatchTime.now().uptimeNanoseconds
            let converted = tryConvert(text)
            let ms = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            if ms >= 500 { diag("Enter handling took \(ms) ms") }
            return !converted
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

    /// かなモードのキー。Shift+英字から打った英単語＋助詞（"Draftde"）が変換待ちの末尾にあれば、
    /// Enter で助詞だけをかなに打ち直す。キーをそのまま通すなら true
    private func handleKanaModeKey(_ event: CGEvent, keyCode: Int64) -> Bool {
        guard let id = InputSource.currentID(), InputSource.isKanaMode(id) else {
            composition.reset()
            return true
        }
        let flags = event.flags
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskAlphaShift]).isEmpty {
            composition.reset()
            return true
        }
        switch keyCode {
        case Key.returnKey, Key.enter:
            let run = composition.asciiRun
            composition.reset()
            guard let run, !flags.contains(.maskShift) else { return true }
            return !tryConvertComposition(run)
        case Int64(Key.delete):
            composition.backspace()
            return true
        default:
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            // スペースは変換、矢印・Tab・Esc は候補の操作なので、変換待ちの中身が分からなくなる
            if length == 1, (0x21..<0x7F).contains(chars[0]), let scalar = Unicode.Scalar(chars[0]) {
                composition.type(Character(scalar))
            } else {
                composition.reset()
            }
            return true
        }
    }

    /// 変換待ちの末尾の英字（run）の助詞だけを打ち直したら true（Enter は握りつぶす）
    private func tryConvertComposition(_ run: String) -> Bool {
        let judgment = detector.judge(run)
        guard judgment.convert, judgment.deleteCount <= run.count, judgment.spans.count == 1,
              case .kana(let romaji, let kana) = judgment.spans[0] else {
            log("Enter（かなモード）: 変換しません（\(judgment.reason)）")
            return false
        }
        // 変換待ちの中身は打ったキーから推定しているだけなので、入力欄で確かめられないときは何もしない。
        // 日本語入力が途中でひらがなに戻していれば（"PRha" → "PRは"）、ここで一致しなくなる
        let typed = String(run.suffix(judgment.deleteCount))
        guard case .success(let field) = Accessibility.focusedText(), field.compositionEnds(with: typed) else {
            log("Enter（かなモード）: 入力欄で変換待ちの中身を確かめられないため変換しません")
            diag("kana-mode conversion aborted: composition not confirmed")
            return false
        }
        log("Enter（かなモード）: \(romaji) → \(kana)")

        converting = true
        DispatchQueue.main.async { [self] in
            for _ in 0..<judgment.deleteCount { post(Key.delete) }
            // かなキーを受けると、日本語入力は変換待ちを残したままひらがなに戻る（標準の日本語入力・Google 日本語入力）
            post(Key.kana)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.switchDelayMs)) { [self] in
                for c in romaji {
                    if let (code, shift) = Key.codes[c] { post(code, shift: shift) }
                }
                converting = false
                replayHeldKeys()
            }
        }
        return true
    }

    /// 変換を始めたら true（Enter は握りつぶす）
    private func tryConvert(_ text: String) -> Bool {
        guard !text.isEmpty else {
            log("Enter: 英数モードで打った文字がないため何もしません")
            return false
        }
        var judgment = detector.judge(text)
        // かなモードで確定した英単語のあとに、英数モードで助詞だけを打った場合は、入力欄の直前の文字とつないで判定する。
        // 入力欄の読み取りはキー入力を止めるので、英文の Enter では読まないよう、短すぎて判定できない記録に限る
        var field: Result<FocusedText, FocusedTextError>?
        if !judgment.convert, text.count < detector.minLetters {
            let read = Accessibility.focusedText()
            field = read
            if case .success(let f) = read, let context = f.text(before: text) {
                judgment = detector.judge(text, after: context)
            }
        }
        guard judgment.convert else {
            log("Enter: 変換しません（\(judgment.reason)）")
            return false
        }
        guard InputSource.find(config.japaneseInputSourceID) != nil else {
            log("日本語の入力ソースが見つからないため変換しません")
            diag("conversion aborted: no Japanese input source")
            return false
        }
        // 記録と入力欄がずれていると、打っていない文字まで Backspace で消してしまう。
        // 読めない欄（アクセシビリティ情報を出さないアプリ）は確認できないので従来どおり進める
        let typed = String(text.suffix(judgment.deleteCount))
        switch field ?? Accessibility.focusedText() {
        case .success(let field):
            guard field.endsAtCaret(with: typed) else {
                log("Enter: 入力欄の内容が記録と一致しないため変換しません")
                // 中身は出さず、ずれ方だけを残す（改行の数え方がアプリで違うなど）
                diag("conversion aborted: field mismatch (\(field.mismatchSummary(typed: typed)))")
                return false
            }
        case .failure(.secureField):
            log("Enter: パスワード欄のため変換しません")
            diag("conversion aborted: secure field")
            return false
        case .failure(let error):
            log("Enter: 入力欄を確認できないまま変換します（\(error)）")
        }
        log(judgment.spans.map { span -> String in
            switch span {
            case .kana(let romaji, let kana): return "\(romaji) → \(kana)"
            case .literal(let text): return "\(text.debugDescription) そのまま"
            }
        }.joined(separator: " / "))

        converting = true
        DispatchQueue.main.async { [self] in
            for _ in 0..<judgment.deleteCount { post(Key.delete) }
            replay(judgment.spans[...])
        }
        return true
    }

    /// 区間を順に打ち直す。モードキーを送り、switchDelayMs 以上待って入力モードが切り替わってから打つ
    private func replay(_ spans: ArraySlice<Span>) {
        guard let span = spans.first else {
            converting = false
            replayHeldKeys()
            return
        }
        // TISSelectInputSource は日本語入力だとメニューバーだけ切り替わり、
        // 入力中のアプリに反映されないことがあるため、かなキー・英数キーを送る
        let wantASCII: Bool
        switch span {
        case .kana: post(Key.kana); wantASCII = false
        case .literal: post(Key.eisu); wantASCII = true
        }
        waitForMode(ascii: wantASCII, started: DispatchTime.now()) { [self] in
            switch span {
            case .kana(let romaji, _):
                for c in romaji {
                    if let (code, shift) = Key.codes[c] { post(code, shift: shift) }
                }
            case .literal(let text):
                typeLiteral(text)
            }
            replay(spans.dropFirst())
        }
    }

    /// 日本語入力は切り替えに時間がかかることがあり（しばらく使っていなかった直後など）、
    /// 決まった時間だけ待つと、かなのつもりのローマ字が英字のまま入る
    private func waitForMode(ascii: Bool, started: DispatchTime, then body: @escaping () -> Void) {
        let poll = 10
        let timeoutMs = 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(poll)) { [self] in
            let ms = Int((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
            let switched = InputSource.isCurrentASCII() == ascii
            if ms < config.switchDelayMs || (!switched && ms < timeoutMs) {
                waitForMode(ascii: ascii, started: started, then: body)
                return
            }
            if !switched {
                diag("input mode switch timed out after \(ms) ms")
            } else if ms > config.switchDelayMs + poll {
                diag("input mode switch took \(ms) ms")
            }
            body()
        }
    }

    private func typeLiteral(_ text: String) {
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: down) else { continue }
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                e.flags = []
                e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                e.post(tap: .cghidEventTap)
            }
        }
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
        if verbose { print("kanahen: \(message)") }
    }
}
