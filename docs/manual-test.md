# Manual checklist

Things an agent can't verify without opening real browsers and mail apps on
your Mac. Tick them when you run a milestone build (`make install`, then
`open ~/Applications/Segue.app`).

## M3 — app shell

- [ ] `open -a ~/Applications/Segue.app "mailto:you@example.com?subject=Hi"` with a config whose
      `fallback` is a Gmail-in-Chrome destination → Chrome opens the compose form in the right
      profile → Segue is gone from Activity Monitor within a second.
- [ ] Same with `"windowMode": "app"` → a chromeless compose window.
- [ ] A `type: app` destination for Mail → Mail opens the draft; no loop.
- [ ] A `browserHandler` destination for a Chrome profile whose mailto handler is Gmail → Gmail
      compose opens. If the profile has no handler, Chrome bounces the link back and Segue
      shows the chooser (M4) instead of looping.
- [ ] Make Segue the default (placeholder window reports the state): click a mailto in Safari,
      Slack and a PDF in Preview. Each lands where the fallback says.
- [ ] Click **Keep** on the system prompt → Segue reports it is *not* the default.
- [ ] Restore Mail as the default → Mail handles links again.

## Dev tools

- `scripts/route-test.sh [mailto] [destination-id]` runs the real app in dry-run mode and prints
  the plan (URL, browser, arguments, clipboard) without opening anything.
- `scripts/cold-start.sh` measures launch → first window.

## M4 — chooser

- [ ] Click a mailto with two or more destinations → the chooser appears centred on the screen
      with the mouse, already key: the number keys pick, arrows move the highlight, Enter picks it,
      Esc closes. Focus goes back to the app you came from after Esc.
- [ ] Clicking outside the panel closes it.
- [ ] Typing letters filters the tiles; Delete edits the filter; Esc clears it first.
- [ ] ⌘1 / ⌘2 / ⌘3 switch Large tiles / Small tiles / Compact list and the choice sticks.
- [ ] First launch with no `config.json`: the chooser already shows Mail, Gmail per signed-in
      Chrome/Brave profile (or one Gmail in the default browser) and Copy address.
- [ ] With "Increase contrast" on in System Settings → opaque panel, thicker borders.
- [ ] VoiceOver reads each tile as "<name>, sends as <address>, key <k>, button".
- `scripts/snapshot-chooser.sh` renders all three layouts to `.context/snapshots/` for a look
  without opening anything.

## M5 — release and tap (you, once the cert exists)

- [ ] `scripts/create-release-cert.sh --out Segue-Release` → identity in the keychain, `.p12` in the
      password manager, leaf hash pasted into README.md.
- [ ] `scripts/release.sh 0.1.0` → `dist/Segue-0.1.0.zip`, tag `v0.1.0`; `gh release create …`.
- [ ] `scripts/update-tap.sh --tap ~/GitProjects/personal/homebrew-tap --version 0.1.0 --zip dist/Segue-0.1.0.zip`,
      commit and push the tap.
- [ ] On a clean Mac (or after `brew uninstall --cask segue`): `brew install --cask jeremym/tap/segue`
      → `open -a Segue` launches with no Gatekeeper prompt → Make Segue default → links route.
- [ ] `brew upgrade` later keeps the default and shows no prompt.

## M6 — rules

- [ ] A rule "sourceApp is com.tinyspeck.slackmacgap → Gmail — work": a link clicked in Slack
      skips the chooser and lands in work Gmail; the same link from Safari shows the chooser.
- [ ] Hold ⌥ while clicking a link that a rule covers → the chooser shows anyway.
- [ ] In the chooser, press ⇧A then pick a tile → `config.json` gains an "Always for <app>" rule and
      the next link from that app skips the chooser. ⇧D does the same for the recipient's domain.
- [ ] With `learnDefault` on, the tile you picked last time for this app (or domain) is highlighted
      next time, so Enter repeats it.

## M7/M8 — .eml reader

- [ ] Settings → "Make Segue default for .eml" (M10) or `open -a Segue file.eml`: the reader shows
      headers, the plain text, Reply / Reply All / Forward, Show HTML, Reveal attachments.
- [ ] Show HTML renders with no remote images (block a tracking pixel: nothing loads, no network).
- [ ] The ★ tile is the account that received the message; Enter picks it.
- [ ] Click "Reply with Gmail — work" on a message that account received → Chrome opens the real
      Gmail thread (search by Message-ID), not a new compose. Reply there keeps the thread.
- [ ] Click "Reply with Mail" → Mail opens a draft with the original quoted and Re: subject.
- [ ] Forward → "Reveal attachments" opens a Finder folder with the files to drag in.
- [ ] A long message → the URL carries a short body and the quoted text is on the clipboard with a toast (M11).
- [ ] Drag an `.eml` out of Mail onto Segue's Dock icon → the reader opens.
- [ ] ⌘+ / ⌘− zoom the text; R / A / F switch the mode; Esc closes without sending anything.
- [ ] `eml.autoRoute: true` + the replyFromReceiver rule → the reader is skipped.
