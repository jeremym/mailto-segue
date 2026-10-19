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

## M9 — webmail matrix and browsers (real browsers, you)

Use `scripts/route-test.sh` to see the exact URL first, then click a real link with the same
destination. For each service: to + cc + bcc filled, subject `A & B = C + D #1 ?` intact, a
two-line body intact.

- [ ] Gmail by `account.email` (`authuser=`) in Chrome profile "Your Chrome"
- [ ] Gmail by `account.index` (`u/1`) when two accounts are signed in
- [ ] Gmail `windowMode: app` → chromeless compose popup
- [ ] Outlook.com `outlook.live.com/mail/0/deeplink/compose`
- [ ] Microsoft 365 `outlook.office.com/mail/deeplink/compose` (fields may drop after the session expires)
- [ ] Yahoo `compose.mail.yahoo.com`
- [ ] Proton `mail.proton.me/inbox#mailto=` and `u/1`
- [ ] Fastmail `www.fastmail.com/action/compose/?mailto=`
- [ ] Zoho (low confidence; fall back to a template)
- [ ] Brave with `--profile-directory`
- [ ] Firefox `-P default-release` with Firefox already running in that profile
- [ ] Firefox container `Work` (needs the "Open external links in a container" extension)
- [ ] Safari (plain open) · Arc (opens in the current space)
- [ ] `browserHandler` on a Chrome profile with Gmail registered as its mailto handler → Gmail compose
- [ ] `browserHandler` on a profile with no handler → Chrome bounces it, Segue shows the chooser (no loop)
- [ ] Record "verified on <date>" per service in the vault's 03-Research table.

## M10 — main window

- [ ] `open -a Segue` (no link) shows the main window on History; closing it quits Segue.
- [ ] History: search filters; selecting shows "Why it went there"; Send again re-opens the same
      destination; Send elsewhere… shows the chooser; Make a rule from this adds a rule; Open .eml
      reopens the reader; Delete removes it.
- [ ] Destinations: Add each kind; pick a browser and profile from the lists; choose a picture and a
      colour (the tile preview updates); drag to reorder; Test this destination opens a sample email.
- [ ] Rules: add, edit conditions, pick a destination, reorder, toggle; "If nothing matches" picker.
- [ ] Settings: Make Segue default / Restore Mail (both prompts); .eml default; layout, position,
      text size, modifier; history caps and Clear; Check setup lists every destination's state.
- [ ] Edit `config.json` by hand while the window is open → nothing breaks; the next launch picks it up.

## M11 — CLI, x-segue://, resident mode, toasts

- [ ] `segue doctor` prints the setup; `segue route "mailto:a@b.com"` routes like a click;
      `segue open file.eml` opens the reader; `segue settings` opens the window.
- [ ] `segue make-default` / `segue restore-default` show the macOS prompt and a toast with the
      verified result.
- [ ] `segue pause-rules on` → every link shows the chooser; `off` restores rules.
- [ ] A Copy destination shows a "Copied." toast for about a second, then Segue quits.
- [ ] Settings → "Stay running" on: a menu-bar envelope appears with Open Segue, recent hand-offs,
      Pause rules, Quit; Segue appears in System Settings → Login Items; closing the main window
      no longer quits. Off: the item and the login item go away.
- [ ] With "Stay running" on, a link still routes (the running instance handles it) and the
      chooser still takes keys.
