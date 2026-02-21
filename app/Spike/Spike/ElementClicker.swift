import AppKit
import ApplicationServices

enum ElementClicker {
    static func click(label: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return findAndPress(element: appElement, label: label.lowercased(), depth: 0)
    }

    private static func findAndPress(element: AXUIElement, label: String, depth: Int) -> Bool {
        if depth > 10 { return false }

        for attr in [kAXTitleAttribute, kAXDescriptionAttribute] as [String] {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
               let str = value as? String,
               str.lowercased().contains(label) {
                let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                if result == .success { return true }
            }
        }

        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else {
            return false
        }

        for child in childArray {
            if findAndPress(element: child, label: label, depth: depth + 1) {
                return true
            }
        }
        return false
    }
}
