# Releasing Mailto Segue

Everything happens on your Mac. No CI, no secrets, no tokens: `git` and `gh`
are already signed in through the browser.

## One-time setup (you, at the keyboard)

### 1. The release certificate  ⚠️ password prompts

```sh
scripts/create-release-cert.sh --out Segue-Release
```

Mints the self-signed **"Segue Release"** identity (20 years) in your login
keychain and writes `Segue-Release.p12`, a password-protected backup of the
key. Put the `.p12` in your password manager, then delete it from disk (it's
git-ignored). Never create a second identity: Homebrew keeps the app's
un-quarantined state across upgrades only while the signature stays the same.

The script prints the certificate leaf SHA-1. Paste it into README.md under
"Verifying a download".

### 2. The tap

`jeremym/homebrew-tap` already exists with a local clone at
`~/GitProjects/personal/homebrew-tap`. The first `scripts/update-tap.sh` run
creates `Casks/mailto-segue.rb` there from `distribution/mailto-segue.rb`.

## Cutting a release

From `main`, with a clean tree:

```sh
make test
scripts/release.sh 1.2.3
#   sets the version, commits "Release 1.2.3", builds a universal bundle signed
#   with "Segue Release", verifies it, writes dist/Segue-1.2.3.zip + .sha256,
#   and tags v1.2.3

git push && git push --tags
gh release create v1.2.3 dist/MailtoSegue-1.2.3.zip dist/MailtoSegue-1.2.3.zip.sha256 --title v1.2.3 --generate-notes

scripts/update-tap.sh --tap ~/GitProjects/personal/homebrew-tap --version 1.2.3 --zip dist/MailtoSegue-1.2.3.zip
#   review the diff it prints, then:
git -C ~/GitProjects/personal/homebrew-tap add Casks/mailto-segue.rb
git -C ~/GitProjects/personal/homebrew-tap commit -m "mailto-segue 1.2.3"
git -C ~/GitProjects/personal/homebrew-tap push
```

Then on any Mac:

```sh
brew install --cask jeremym/tap/mailto-segue
open -a "Mailto Segue"
```

## Checking a build without releasing

```sh
scripts/release.sh 0.0.1 --dry-run   # universal, ad-hoc, no commit/tag
```

## Verifying a download (for the README)

```sh
shasum -a 256 MailtoSegue-1.2.3.zip                # matches the .sha256 on the release
codesign -d -r- "/Applications/Mailto Segue.app"   # certificate leaf = H"<leaf hash>"
```
