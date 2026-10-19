import Darwin
import Foundation

/// Cheap launch-phase marks, reported by `scripts/cold-start.sh`. Reading the
/// clock costs nothing, so the marks stay in release builds.
enum Timing {
    nonisolated(unsafe) private static var marks: [(String, Int)] = []

    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }()

    static var msSinceExec: Int { Int(Date().timeIntervalSince(processStart) * 1000) }

    static func mark(_ label: String) {
        marks.append((label, msSinceExec))
    }

    static var report: String {
        marks.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    }
}
