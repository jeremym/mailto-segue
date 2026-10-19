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
            let execMs = processStartEpochMs() ?? readyMs
            try? "\(readyMs) \(execMs)\n".write(to: file, atomically: true, encoding: .utf8)
            if thenQuit { NSApp.terminate(nil) }
        }
    }

    private static func processStartEpochMs() -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Int(tv.tv_sec) * 1000 + Int(tv.tv_usec) / 1000
    }
}
