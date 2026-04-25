import SwiftUI
import AppKit
import Carbon.HIToolbox

struct KeyEvent {
    let keyCode: UInt16
    let characters: String           // shift-aware (e.g. "?" for Shift+/)
    let charactersIgnoringShift: String
    let modifiers: NSEvent.ModifierFlags
}

/// Installs a local key monitor for the lifetime of the view. SwiftUI's
/// .onKeyPress doesn't reliably deliver F-keys or Tab, so we use AppKit.
struct KeyCatcher: NSViewRepresentable {
    let onKey: (KeyEvent) -> Bool  // return true if handled

    func makeNSView(context: Context) -> NSView {
        let v = CatcherView()
        v.onKey = onKey
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onKey = onKey
    }

    final class CatcherView: NSView {
        var onKey: ((KeyEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil, window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self = self, self.window?.isKeyWindow == true else { return event }
                    let ke = KeyEvent(keyCode: event.keyCode,
                                      characters: event.characters ?? "",
                                      charactersIgnoringShift: event.charactersIgnoringModifiers ?? "",
                                      modifiers: event.modifierFlags)
                    if self.onKey?(ke) == true { return nil }
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            super.removeFromSuperview()
        }
    }
}

enum Keys {
    static let tab: UInt16      = UInt16(kVK_Tab)
    static let space: UInt16    = UInt16(kVK_Space)
    static let enter: UInt16    = UInt16(kVK_Return)
    static let delete: UInt16   = UInt16(kVK_Delete)
    static let up: UInt16       = UInt16(kVK_UpArrow)
    static let down: UInt16     = UInt16(kVK_DownArrow)
    static let escape: UInt16   = UInt16(kVK_Escape)
    static let f2: UInt16       = UInt16(kVK_F2)
    static let f3: UInt16       = UInt16(kVK_F3)
    static let f5: UInt16       = UInt16(kVK_F5)
    static let f6: UInt16       = UInt16(kVK_F6)
    static let f7: UInt16       = UInt16(kVK_F7)
    static let o: UInt16        = UInt16(kVK_ANSI_O)
    static let a: UInt16        = UInt16(kVK_ANSI_A)
    static let one: UInt16      = UInt16(kVK_ANSI_1)
    static let two: UInt16      = UInt16(kVK_ANSI_2)
    static let three: UInt16    = UInt16(kVK_ANSI_3)
    static let left: UInt16     = UInt16(kVK_LeftArrow)
    static let right: UInt16    = UInt16(kVK_RightArrow)
    static let home: UInt16     = UInt16(kVK_Home)
    static let end: UInt16      = UInt16(kVK_End)
    static let d: UInt16        = UInt16(kVK_ANSI_D)
    static let g: UInt16        = UInt16(kVK_ANSI_G)
    static let pageUp: UInt16   = UInt16(kVK_PageUp)
    static let pageDown: UInt16 = UInt16(kVK_PageDown)
}
