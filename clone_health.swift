import AppKit
import CoreGraphics
import Darwin

// Read window metadata only: no screen capture or Accessibility permission.
guard CommandLine.arguments.count == 2 else { exit(2) }
let path = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
let apps = NSWorkspace.shared.runningApplications.filter { app in
    // LaunchServices can temporarily point the same bundle ID at a staged copy.
    // Match the kernel's executable path instead of the registered bundle URL.
    var executable = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(app.processIdentifier, &executable, UInt32(executable.count))
    return length > 0 && String(cString: executable).hasPrefix(path + "/Contents/")
        && !app.isTerminated && app.isFinishedLaunching
}
let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
for app in apps {
    for window in windows {
        guard let pid = window[kCGWindowOwnerPID as String] as? Int,
              pid == Int(app.processIdentifier),
              let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              // Stage Manager can shrink an inactive login window to a thumbnail.
              // Exclude menu strips and small square utility windows, not thumbnails.
              let width = bounds["Width"] as? Double, width >= 40,
              let height = bounds["Height"] as? Double, height >= 80 else { continue }
        exit(0)
    }
}
exit(1)
