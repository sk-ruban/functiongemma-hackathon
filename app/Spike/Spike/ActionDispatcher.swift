import Foundation

final class ActionDispatcher {
    func dispatch(_ calls: [ToolCall]) async -> [ActionResult] {
        var results: [ActionResult] = []
        for call in calls {
            let result: ActionResult
            switch call.name {
            case "open_app":
                let name = call.arguments["name"] ?? ""
                let success = AppLauncher.open(name: name)
                result = ActionResult(toolName: "open_app", success: success, message: success ? "Opened \(name)" : "Could not open \(name)")
                if success {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            case "keyboard_shortcut":
                let keys = call.arguments["keys"] ?? ""
                let success = KeyboardSimulator.pressShortcut(keys)
                result = ActionResult(toolName: "keyboard_shortcut", success: success, message: success ? "Pressed \(keys)" : "Failed to press \(keys)")
            case "type_text":
                let text = call.arguments["text"] ?? ""
                KeyboardSimulator.typeText(text)
                result = ActionResult(toolName: "type_text", success: true, message: "Typed \"\(text)\"")
            case "click_element":
                let label = call.arguments["label"] ?? ""
                let success = ElementClicker.click(label: label)
                result = ActionResult(toolName: "click_element", success: success, message: success ? "Clicked \(label)" : "Could not find \(label)")
            case "read_screen":
                let app = call.arguments["app"] ?? "frontmost"
                let text = ScreenReader.read(app: app)
                result = ActionResult(toolName: "read_screen", success: !text.isEmpty, message: text.isEmpty ? "No text found" : String(text.prefix(200)))
            default:
                result = ActionResult(toolName: call.name, success: false, message: "Unknown tool: \(call.name)")
            }
            results.append(result)
        }
        return results
    }
}
