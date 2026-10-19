import Foundation
import SegueCore

/// `segue`: a thin command-line front for the app. Everything goes through
/// LaunchServices (`open`) and the `x-segue://` scheme, so there is exactly
/// one implementation of routing, in the app.

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> String {
    """
    segue \(SegueVersion.string) — route mailto: links and .eml files

    usage:
      segue route "mailto:pat@acme.com?subject=Hi"   route a link (rules, or the chooser)
      segue open message.eml                          open a message in the reader
      segue doctor                                    check the setup and every destination
      segue make-default | restore-default            mailto: handler (macOS will ask you to confirm)
      segue settings | history | destinations | rules open the main window there
      segue pause-rules on|off                        every link shows the chooser while paused
      segue test <destination-id>                     open a sample email through a destination
      segue --version
    """
}

/// The app bundle this CLI lives in (Contents/Helpers/segue), resolved
/// through symlinks, so `open -a` works even if LaunchServices forgot us.
func appBundleURL() -> URL? {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    var url = exe
    while url.path != "/" {
        if url.pathExtension == "app" { return url }
        url.deleteLastPathComponent()
    }
    return nil
}

@discardableResult
func openInSegue(_ target: String, wait: Bool = false) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    var arguments: [String] = []
    if let app = appBundleURL() { arguments += ["-a", app.path] } else { arguments += ["-b", SegueVersion.bundleIdentifier] }
    if wait { arguments.append("-W") }
    arguments.append(target)
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        FileHandle.standardError.write(Data("segue: could not run open: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

func command(_ host: String, _ items: [String: String] = [:]) -> String {
    var c = URLComponents()
    c.scheme = "x-segue"
    c.host = host
    if !items.isEmpty {
        c.queryItems = items.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    return c.url?.absoluteString ?? "x-segue://\(host)"
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("segue: \(message)\n".utf8))
    exit(2)
}

switch args.first {
case nil, "help", "--help", "-h":
    print(usage())

case "--version", "-v", "version":
    print("segue \(SegueVersion.string)")

case "route":
    guard args.count >= 2 else { fail("route needs a mailto: link") }
    let link = args[1]
    guard MailtoParser.isMailto(link) else { fail("not a mailto: link: \(link)") }
    exit(openInSegue(command("route", ["url": link])))

case "open":
    guard args.count >= 2 else { fail("open needs a .eml or .emlx file") }
    let url = URL(fileURLWithPath: args[1]).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { fail("no such file: \(url.path)") }
    exit(openInSegue(url.path))

case "doctor":
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("segue-doctor-\(getpid()).txt")
    try? FileManager.default.removeItem(at: out)
    let status = openInSegue(command("doctor", ["out": out.path]))
    guard status == 0 else { exit(status) }
    var waited = 0.0
    while !FileManager.default.fileExists(atPath: out.path), waited < 10 {
        Thread.sleep(forTimeInterval: 0.05)
        waited += 0.05
    }
    guard let text = try? String(contentsOf: out, encoding: .utf8) else { fail("Segue did not answer. Is it installed and registered? Try: open -a Segue") }
    try? FileManager.default.removeItem(at: out)
    var problems = 0
    for line in text.split(separator: "\n") {
        let ok = line.hasPrefix("ok\t")
        if !ok { problems += 1 }
        let body = line.drop(while: { $0 != "\t" }).dropFirst()
        print((ok ? "  ✓ " : "  ✗ ") + body)
    }
    print(problems == 0 ? "\nAll good." : "\n\(problems) problem(s).")
    exit(problems == 0 ? 0 : 1)

case "make-default":
    exit(openInSegue(command("make-default")))

case "restore-default":
    exit(openInSegue(command("restore-default")))

case "settings", "history", "destinations", "rules", "about":
    exit(openInSegue(command(args[0])))

case "pause-rules":
    guard args.count >= 2, ["on", "off"].contains(args[1]) else { fail("pause-rules needs on or off") }
    exit(openInSegue(command("pause-rules", ["on": args[1] == "on" ? "1" : "0"])))

case "test":
    guard args.count >= 2 else { fail("test needs a destination id (see `segue doctor`)") }
    exit(openInSegue(command("test", ["destination": args[1]])))

default:
    fail("unknown command '\(args[0])'\n\n" + usage())
}
