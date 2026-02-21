import AppKit
import ApplicationServices

enum ScreenReader {
    static func read(app appName: String) -> String {
        let appElement: AXUIElement
        if appName.lowercased() == "frontmost" {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return "" }
            appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        } else {
            guard let running = NSWorkspace.shared.runningApplications
                .first(where: { $0.localizedName?.lowercased() == appName.lowercased() }) else {
                return ""
            }
            appElement = AXUIElementCreateApplication(running.processIdentifier)
        }

        var texts: [String] = []
        collectText(element: appElement, texts: &texts, depth: 0)
        return texts.joined(separator: "\n")
    }

    private static func collectText(element: AXUIElement, texts: inout [String], depth: Int) {
        if depth > 10 { return }

        for attr in [kAXValueAttribute, kAXTitleAttribute] as [String] {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
               let str = value as? String,
               !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(str)
            }
        }

        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else {
            return
        }

        for child in childArray {
            collectText(element: child, texts: &texts, depth: depth + 1)
        }
    }
}
