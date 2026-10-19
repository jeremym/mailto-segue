# Segue

**Every `mailto:` link, exactly where you want it.**

Segue is a small, open-source macOS app that becomes your default email app and then hands each email off to the right place:

- Gmail in **a specific account**, in **a specific browser and profile**
- a desktop mail app (Mail, Mimestream, Outlook, Spark, Thunderbird…)
- or just your clipboard

When you click an email link, a **chooser** pops up with a big button for each of your destinations: "Gmail — work", "Yahoo", "Mail". Each button has its own picture. Click one (or press its number) and it's gone. You can also let **rules** decide for you, e.g. "links clicked in Slack → work Gmail" or "anything to `acme.com` → work Gmail".

Double-click an **`.eml` file** and Segue shows the message with the same big buttons underneath: **Reply with Gmail — work**, **Reply with Yahoo**… Click one, the window closes, and the reply opens in that account with the original quoted. Segue marks the account that received the email with a ★.

Got lots of addresses? Switch the chooser from **Large tiles** to **Small tiles** or a **Compact list**.

### What Segue is *not*

Segue is a **marshaller**, not a mail client. It never composes, edits or sends email, and it never asks for your mail password. It decides *where* a draft opens. You still type your message in Gmail, Yahoo, Mail.app, or wherever it lands.

> **Status:** planning is done and the code is not written yet. v1.0 is coming. Nothing below works until then.

---

## Install (once v0.1 ships)

```sh
brew install jeremym/tap/segue
```

This is a Homebrew **formula that builds Segue on your Mac** from this repo's source. You only need the Xcode Command Line Tools (`xcode-select --install`).

Why build from source? Segue isn't signed with a paid Apple Developer ID. An app compiled on your own Mac is never quarantined, so macOS's Gatekeeper never complains. No "Open Anyway", no `xattr` commands.

Other ways in:

- **From a clone:** `make install`, which puts `Segue.app` in `~/Applications`.
- **Release zip:** download it from GitHub Releases. Then open **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine ~/Applications/Segue.app`.

## Quick start (planned)

1. Open Segue and click **Make Segue default**. macOS will ask you to confirm.
2. Add a destination, e.g. **Gmail — account 1 — Arc**. Give it a picture and a color if you like.
3. Click any `mailto:` link. Click a button or press its number. **Esc** cancels.
4. Want to skip the chooser next time? Toggle **Always for this app** or **Always for this domain** in the chooser.

## Privacy

- No telemetry, no accounts, no network calls. Segue only opens the URLs you asked for.
- HTML email is shown with every remote image and script blocked, so tracking pixels never fire.
- Settings and history stay on your Mac in `~/Library/Application Support/Segue/`. The settings file is plain JSON you can edit by hand or keep in your dotfiles.
- History keeps full message text (compressed, never attachments). It's capped at 500 items or 50 MB, whichever comes first, which is usually under 10 MB in practice. You can clear it with one click or turn it off.
- No Accessibility, Automation or Full Disk Access permissions needed.

---

## How this project is run

### Releases are made by hand

There is no CI/CD. There's no build farm, no release bot, and no pipeline of 14 YAML files, because the whole engineering org is one guy and his Mac. He is both the build server and the on-call rotation. If other people ever join, CI gets added then.

A release looks like this:

```sh
make test
scripts/release.sh 1.2.3           # universal build, ad-hoc signed zip, sha256, git tag
gh release create v1.2.3 build/Segue-1.2.3.zip
scripts/update-tap.sh 1.2.3        # bumps url + sha256 in Formula/segue.rb
# then commit + push the tap by hand
```

### The Homebrew tap

Segue lives in [`jeremym/homebrew-tap`](https://github.com/jeremym/homebrew-tap) as **`Formula/segue.rb`**, next to the casks already in that tap.

- It's a formula, not a cask, on purpose. Homebrew only quarantines cask downloads, and `homebrew/cask` has refused apps that fail Gatekeeper since 2026-09-01.
- The formula downloads the tagged source tarball, runs `make bundle`, and installs `Segue.app` plus the `segue` command-line tool.
- After you install, link the app into `~/Applications` (the formula prints the exact command) and open it once.

### Branches

- `main` is always the latest.
- Work happens on short feature branches that merge straight into `main`.
- There's no `dev` branch. It's one person working fast.

### Signing

Builds are **ad-hoc signed** (`codesign -s -`). That's free and automatic, and it's enough because Segue needs no special permissions.

---

## Tech

- Native Swift 6, SwiftUI with a few AppKit pieces, built with Swift Package Manager. No Xcode project.
- macOS 14 Sonoma or later. Universal binary (Apple silicon + Intel).
- The `mailto:` parser follows RFC 6068. The `.eml` parser follows RFC 5322 and MIME. Both are plain Foundation code with unit tests.

## License

[MIT](LICENSE)

---

Made by [Overtone Foundry](https://overtonefoundry.com).
