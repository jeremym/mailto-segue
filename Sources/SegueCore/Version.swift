/// The single source of truth for Segue's version.
/// `scripts/bundle.sh` reads it into Info.plist; `scripts/release.sh` bumps it.
public enum SegueVersion {
    public static let string = "0.0.1"
    public static let bundleIdentifier = "com.overtonefoundry.segue"
}
