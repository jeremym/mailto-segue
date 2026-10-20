import XCTest
@testable import SegueCore

final class BrowserProfilesTests: XCTestCase {
    func testChromiumLocalState() {
        let json = """
        { "profile": { "info_cache": {
            "Profile 2": { "name": "Side", "user_name": "" },
            "Default": { "name": "Your Chrome", "user_name": "jeremy@example.com" },
            "Profile 1": { "name": "Work", "user_name": "me@work.com" },
            "Guest Profile": { "name": "" }
        } }, "other": 1 }
        """
        let profiles = ChromiumProfiles.parse(localState: Data(json.utf8))
        XCTAssertEqual(profiles.map(\.directory), ["Default", "Profile 1", "Profile 2", "Guest Profile"])
        XCTAssertEqual(profiles[0].userName, "jeremy@example.com")
        XCTAssertEqual(profiles[1].name, "Work")
        XCTAssertNil(profiles[2].userName)
        XCTAssertEqual(profiles[3].name, "Guest Profile", "empty name falls back to the directory")
    }

    func testChromiumGarbageIsEmpty() {
        XCTAssertEqual(ChromiumProfiles.parse(localState: Data("nope".utf8)), [])
        XCTAssertEqual(ChromiumProfiles.parse(localState: Data("{}".utf8)), [])
    }

    func testChromiumSupportFolders() {
        XCTAssertEqual(ChromiumProfiles.supportFolder(forBundleID: "com.google.Chrome"), "Google/Chrome")
        XCTAssertEqual(ChromiumProfiles.supportFolder(forBundleID: "com.brave.Browser"), "BraveSoftware/Brave-Browser")
        XCTAssertNil(ChromiumProfiles.supportFolder(forBundleID: "com.apple.Safari"))
        let url = ChromiumProfiles.localStateURL(forBundleID: "com.microsoft.edgemac", applicationSupport: URL(fileURLWithPath: "/tmp/AS"))
        XCTAssertEqual(url?.path, "/tmp/AS/Microsoft Edge/Local State")
    }

    func testFirefoxProfilesIniWithInstallSection() {
        let ini = """
        [General]
        StartWithLastProfile=1
        Version=2

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/5ezn22e2.default-release

        [Install2656FF1E876E9973]
        Default=Profiles/5ezn22e2.default-release
        Locked=1

        [Profile1]
        Name=default
        IsRelative=1
        Path=Profiles/zjwhq583.default
        Default=1
        """
        let profiles = FirefoxProfiles.parse(profilesIni: ini)
        XCTAssertEqual(profiles.map(\.name), ["default-release", "default"])
        XCTAssertTrue(profiles[0].isDefault, "the Install section wins over Default=1")
        XCTAssertFalse(profiles[1].isDefault)
    }

    func testFirefoxLegacyDefaultFlag() {
        let ini = "[Profile0]\nName=a\nPath=p/a\n[Profile1]\nName=b\nPath=p/b\nDefault=1\n"
        let profiles = FirefoxProfiles.parse(profilesIni: ini)
        XCTAssertEqual(profiles.first?.name, "b")
        XCTAssertTrue(profiles.first!.isDefault)
    }
}
