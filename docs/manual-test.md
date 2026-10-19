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
