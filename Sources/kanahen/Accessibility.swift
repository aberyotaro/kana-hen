import Cocoa
import GobakuCore

enum FocusedTextError: Error, CustomStringConvertible {
    case noFocusedElement(AXError)
    case secureField
    case noValue(AXError)
    case noSelectedRange(AXError)

    var description: String {
        switch self {
        case .noFocusedElement(let e): return "フォーカス中の要素を取得できない (AXError \(e.rawValue))"
        case .secureField: return "パスワード欄"
        case .noValue(let e): return "入力欄の文字列を取得できない (AXError \(e.rawValue))"
        case .noSelectedRange(let e): return "カーソル位置を取得できない (AXError \(e.rawValue))"
        }
    }
}

enum Accessibility {
    /// Electron 製のアプリは AXManualAccessibility を立てるまでアクセシビリティ情報を公開せず、
    /// 立てた直後の問い合わせにも答えない。前面に来た時点で立てておき、Enter の時点では読めるようにする。
    /// Electron 以外のアプリはこの属性を無視する
    static func prepare(_ pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// 前面アプリのフォーカス中の入力欄を読む
    static func focusedText() -> Result<FocusedText, FocusedTextError> {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return .failure(.noFocusedElement(.failure))
        }
        let app = AXUIElementCreateApplication(pid)
        // キー監視のコールバック内で呼ぶので、応答の遅いアプリで監視が止まらないよう待ち時間を短くする
        AXUIElementSetMessagingTimeout(app, 0.2)
        return read(app)
    }

    private static func read(_ app: AXUIElement) -> Result<FocusedText, FocusedTextError> {
        var focused: CFTypeRef?
        let fe = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        guard fe == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return .failure(.noFocusedElement(fe))
        }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        if isSecureField(element) { return .failure(.secureField) }

        var value: CFTypeRef?
        let ve = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard ve == .success, let text = value as? String else { return .failure(.noValue(ve)) }

        var rangeRef: CFTypeRef?
        let re = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        var range = CFRange()
        guard re == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(rangeRef, to: AXValue.self), .cfRange, &range) else {
            return .failure(.noSelectedRange(re))
        }
        return .success(FocusedText(text: text, caret: range.location, selectionLength: range.length))
    }

    private static func isSecureField(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &ref) == .success else {
            return false
        }
        return (ref as? String) == (kAXSecureTextFieldSubrole as String)
    }
}
