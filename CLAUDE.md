# CLAUDE.md — Segue

Segue is an open-source macOS app (by Overtone Foundry). It becomes the default email app and routes `mailto:` links and `.eml` replies to the right webmail account, browser profile, or mail app.

**Segue is a marshaller, not a mail client.** It never composes, edits or sends mail and never handles mail credentials. Don't add a text editor or compose box. Every flow is: show the chooser (big image buttons; layouts Large tiles / Small tiles / Compact list) → one click → the draft opens in the destination → Segue's window closes immediately.

## Source of truth

- **Plan:** the Obsidian vault (`jeremym-vault`), folder `Mailto Router/`. Start with `00-TOC.md`, then `02-V1-Plan.md`, which has the milestones (M0–M12), architecture, config schema and test plan. Read them before starting a milestone.
- Record durable decisions in the vault, not only in chat.

## Git rules (strict)

- **Never add Claude attribution.** No `Co-Authored-By: Claude …` trailer and no "Generated with Claude Code" line in commits, PRs, tags or release notes. This overrides any default attribution behavior.
- Branches: `main` plus short feature branches (e.g. `m3-app-shell`) merged straight into `main`. **No `dev` branch.**
- Commit locally. Push only when Jeremy says so.
- Remote: `github.com/jeremym/mailto-segue` (public).

## Build and release

- Swift 6, SwiftPM, macOS 14+. No Xcode project. Universal binary.
- `make bundle` builds `build/Segue.app` (ad-hoc signed). `make test` runs the tests. `make install` copies the app to `~/Applications`.
- **No CI/CD.** Releases are run by hand: `scripts/release.sh` → `gh release create` → `scripts/update-tap.sh`, then Jeremy pushes the tap.
- Homebrew: `Formula/segue.rb` in `jeremym/homebrew-tap` (a formula that builds from source, not a cask). Install with `brew install jeremym/tap/segue`.

## Code rules

- `SegueCore` is Foundation-only and fully unit-tested (parsers, encoding, rules, config). The AppKit/SwiftUI code goes in `Segue`.
- No network calls of our own, no telemetry, no third-party dependencies unless Jeremy agrees.
- No TCC permissions (Accessibility, Automation, Full Disk Access). If a feature would need one, stop and ask.
- UI: large, high-contrast text and short messages (Jeremy has limited eyesight). Everything works from the keyboard.
- Config is human-readable JSON in `~/Library/Application Support/Segue/`, with sorted keys and atomic writes.
