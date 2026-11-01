import Cocoa
import GobakuCore

enum FocusedTextError: Error, CustomStringConvertible {
    case noFocusedElement(AXError)
    case noValue(AXError)
    case noSelectedRange(AXError)

    var description: String {
        switch self {
        case .noFocusedElement(let e): return "フォーカス中の要素を取得できない (AXError \(e.rawValue))"
        case .noValue(let e): return "入力欄の文字列を取得できない (AXError \(e.rawValue))"
        case .noSelectedRange(let e): return "カーソル位置を取得できない (AXError \(e.rawValue))"
        }
    }
}

enum Accessibility {
    /// 前面アプリのフォーカス中の入力欄を読む。Electron 製のアプリは、
    /// AXManualAccessibility を立てるまでアクセシビリティ情報を公開しないので、失敗したら一度だけ立てて読み直す
    static func focusedText() -> Result<FocusedText, FocusedTextError> {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return .failure(.noFocusedElement(.failure))
        }
        let app = AXUIElementCreateApplication(pid)
        // キー監視のコールバック内で呼ぶので、応答の遅いアプリで監視が止まらないよう待ち時間を短くする
        AXUIElementSetMessagingTimeout(app, 0.2)
        var result = read(app)
        if case .failure(.noFocusedElement) = result {
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            result = read(app)
        }
        return result
    }

    private static func read(_ app: AXUIElement) -> Result<FocusedText, FocusedTextError> {
        var focused: CFTypeRef?
        let fe = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        guard fe == .success, let focused else { return .failure(.noFocusedElement(fe)) }
        let element = focused as! AXUIElement

        var value: CFTypeRef?
        let ve = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard ve == .success, let text = value as? String else { return .failure(.noValue(ve)) }

        var rangeRef: CFTypeRef?
        let re = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        var range = CFRange()
        guard re == .success, let rangeRef, AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else {
            return .failure(.noSelectedRange(re))
        }
        return .success(FocusedText(text: text, caret: range.location, selectionLength: range.length))
    }
}
