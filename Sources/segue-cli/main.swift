import Foundation
import SegueCore

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "--version", "-v", "version":
    print("segue \(SegueVersion.string)")
case nil, "--help", "-h", "help":
    print("""
    segue \(SegueVersion.string) — route mailto: links and .eml files

    usage:
      segue --version
    """)
default:
    FileHandle.standardError.write(Data("segue: unknown command '\(args[0])'\n".utf8))
    exit(2)
}
