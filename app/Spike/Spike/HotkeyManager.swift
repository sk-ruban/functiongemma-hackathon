import HotKey
import AppKit

final class HotkeyManager {
    private var hotKey: HotKey?
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void

    init(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        hotKey = HotKey(key: .grave, modifiers: [.control, .option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.onKeyDown()
        }
        hotKey?.keyUpHandler = { [weak self] in
            self?.onKeyUp()
        }
    }
}
