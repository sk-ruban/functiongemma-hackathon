import AppKit

enum AppLauncher {
    private static let searchPaths = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/Applications/Utilities",
    ]

    static func open(name: String) -> Bool {
        for dir in searchPaths {
            let path = "\(dir)/\(name).app"
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                let config = NSWorkspace.OpenConfiguration()
                let semaphore = DispatchSemaphore(value: 0)
                var success = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                    success = error == nil
                    semaphore.signal()
                }
                semaphore.wait()
                if success { return true }
            }
        }
        return openViaProcess(name: name)
    }

    private static func openViaProcess(name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", name]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
