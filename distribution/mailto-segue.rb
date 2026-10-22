# Ready-to-use Homebrew cask for the jeremym/homebrew-tap repo.
# scripts/update-tap.sh copies it to Casks/mailto-segue.rb on the first release and
# rewrites the `version` and `sha256` lines on every release, so keep those
# two lines in this exact shape.
cask "mailto-segue" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/jeremym/mailto-segue/releases/download/v#{version}/MailtoSegue-#{version}.zip"
  name "Mailto Segue"
  desc "Route mailto: links and .eml replies to the right account, browser and app"
  homepage "https://github.com/jeremym/mailto-segue"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: :sonoma

  app "Mailto Segue.app"
  binary "#{appdir}/Mailto Segue.app/Contents/Helpers/segue"

  # Not notarized (no Apple Developer ID, by choice). Gatekeeper would block the
  # first launch, so drop the quarantine flag that Homebrew sets on downloads.
  # Integrity is covered by the sha256 above and by the certificate leaf hash in
  # the README (codesign -d -r- "Mailto Segue.app").
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Mailto Segue.app"], must_succeed: false
  end

  uninstall quit: "com.overtonefoundry.segue"

  zap trash: "~/Library/Application Support/Mailto Segue"

  caveats <<~EOS
    Mailto Segue is signed with the project's own certificate, not an Apple Developer
    ID, and is not notarized. The quarantine flag is removed on install so it
    launches without a Gatekeeper prompt.

    Open it once and click "Make Mailto Segue default". Before `brew uninstall`,
    click "Restore Mail as default" (or run `segue restore-default`) so macOS
    doesn't keep pointing mailto: at a missing app.
  EOS
end
