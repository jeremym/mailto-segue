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
