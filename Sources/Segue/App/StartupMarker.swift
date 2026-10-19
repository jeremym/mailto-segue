import AppKit
import Darwin

/// `scripts/cold-start.sh` launches Segue with `--startup-marker <file>` and
/// waits for that file to appear. We write it once the first surface is on
/// screen, after one run-loop pass so the window has actually been drawn.
///
/// The file holds two epoch-millisecond values: `ready exec`. `exec` is the
/// kernel's process start time, so the script can split the total into the
/// LaunchServices part (open → exec) and ours (exec → ready).
enum StartupMarker {
    @MainActor
    static func write(to file: URL, thenQuit: Bool = true) {
        DispatchQueue.main.async {
            let readyMs = Int(Date().timeIntervalSince1970 * 1000)
            let execMs = Int(Timing.processStart.timeIntervalSince1970 * 1000)
            Timing.mark("drawn")
            try? "\(readyMs) \(execMs) \(Timing.report)\n".write(to: file, atomically: true, encoding: .utf8)
            if thenQuit { NSApp.terminate(nil) }
        }
    }
}
