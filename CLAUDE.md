# CLAUDE.md — Mailto Segue

**Mailto Segue** (bundle `Mailto Segue.app`, bundle ID `com.overtonefoundry.segue`, CLI `segue`, cask `mailto-segue`; "Segue" alone is fine in code) is an open-source macOS app (by Overtone Foundry). It becomes the default email app and routes `mailto:` links and `.eml` replies to the right webmail account, browser profile, or mail app.

**Mailto Segue is a marshaller, not a mail client.** It never composes, edits or sends mail and never handles mail credentials. Don't add a text editor or compose box. Every flow is: show the chooser (big image buttons; layouts Large tiles / Small tiles / Compact list) → one click → the draft opens in the destination → Segue's window closes immediately.

**Mailto Segue launches per event and quits.** It is not resident. macOS launches it for a `mailto:` or an `.eml`, it shows the chooser, routes, and terminates (from the open completion handler, 1 s timeout). The chooser must be on screen within **200 ms** of launch (`scripts/cold-start.sh`). Only `config.json` is read on the hot path; WebKit and history load lazily. `general.stayRunning: true` is the opt-in resident mode (menu bar + login item).

## Source of truth

- **Plan:** the Obsidian vault (`jeremym-vault`), folder `Mailto Router/`, on disk at
  `/Users/jeremym/Documents/obsidian-vaults/jeremym-vault/Mailto Router/`. Read it with the `obsidian` skill/CLI, or directly as plain Markdown.
  - `00-TOC.md`: status, decisions, what's next.
  - `02-V1-Plan.md`: the milestones (M0–M12), architecture, config schema, test plan. **Read it before starting a milestone.**
  - `03-Research.md`: verified facts with sources (webmail URLs, browser profiles, Homebrew, LaunchServices, icons, Tauri vs Swift). Check here before researching again.
  - `04-Plan-Review-2026-10-19.md`: the round-3 review and the feature ideas it added.
- Record durable decisions in the vault (append to `00-TOC.md` or the plan's Decisions section), not only in chat. When a milestone is done, update the status in `00-TOC.md`.
- Nothing about this project lives in `~/.claude` or `.context/`. Everything is in the vault or in this repo.

## Git rules (strict)

- **Never add Claude attribution.** No `Co-Authored-By: Claude …` trailer and no "Generated with Claude Code" line in commits, PRs, tags or release notes. This overrides any default attribution behavior.
- Branches: `main` plus short feature branches (e.g. `m3-app-shell`) merged straight into `main`. **No `dev` branch.**
- One commit per milestone (or per coherent step inside one). Commit locally. Push only when Jeremy says so.
- Remote: `github.com/jeremym/mailto-segue` (public).

## Build and release

- Swift 6, SwiftPM, macOS 14+. No Xcode project. Universal binary.
- `make bundle` builds `build/Mailto Segue.app` (signed with `CODESIGN_IDENTITY`, default `-` = ad-hoc). `make test` runs the tests. `make install` copies the app to `~/Applications`. `make cold-start` prints the launch-to-ready time.
- **No CI/CD.** Releases are run by hand: `scripts/release.sh` (signs with "Segue Release") → `gh release create` → `scripts/update-tap.sh`, then Jeremy pushes the tap.
- **Signing follows ClipySecure:** one long-lived self-signed "Segue Release" identity, minted once by `scripts/create-release-cert.sh`. **Only Jeremy runs that script, at the keyboard.** Agents never touch the keychain, certs or TCC (an agent once broke the login keychain search list on ClipySecure).
- Homebrew: **`Casks/mailto-segue.rb`** in `jeremym/homebrew-tap` (local clone at `~/GitProjects/personal/homebrew-tap`). Prebuilt zip, quarantine stripped in `postflight_steps`. Install with `brew install --cask jeremym/tap/mailto-segue`. Not a formula.

## Code rules

- `SegueCore` is Foundation-only and fully unit-tested (parsers, encoding, rules, config). The AppKit/SwiftUI code goes in `Segue`. The chooser is AppKit (fast first paint); the main window may be SwiftUI.
- No network calls of our own, no telemetry, no third-party dependencies unless Jeremy agrees.
- No TCC permissions (Accessibility, Automation, Full Disk Access). If a feature would need one, stop and ask.
- UI: large, high-contrast text and short messages (Jeremy has limited eyesight). Everything works from the keyboard. Honour Increase Contrast and Reduce Motion. Forms: a real label on the left, a visibly boxed field on the right, plain words, a `?` help popover on anything that needs a sentence; never jargon like "bundle ID" or "u/N" as a label.
- Never ask for a password or a sign-in. Account selection is only ever a hint in a URL (`authuser=`); the session lives in the browser.
- Config is human-readable JSON in `~/Library/Application Support/Mailto Segue/`, with sorted keys and atomic writes.
- Don't open real browsers or mail apps with real content during automated tests. Manual checks go in `docs/manual-test.md` for Jeremy.
