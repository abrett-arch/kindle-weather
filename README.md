# kindle-weather

An always-on Hobart weather screen for a jailbroken Kindle Paperwhite (7th gen), used in
landscape (1448×1072) with the charging port on the left.

- `render.py` fetches the Bureau of Meteorology forecast and observations (falling back to
  Open-Meteo for anything BOM doesn't return) and draws `dash.png` (rotated for the Kindle),
  `preview.png` (upright), and `delta/`: split-flap frames when the temperatures change and
  the changed rectangles, so the Kindle redraws only what changed.
- `.github/workflows/dash.yml` runs it every 15 minutes and publishes the result to GitHub
  Pages at `https://<owner>.github.io/kindle-weather/dash.png`.
- `kindle/extensions/weatherdash` is the KUAL extension on the Kindle: it downloads the
  image every few minutes, plays the flip animation, and redraws.

Local preview without network: `python render.py --sample --now 2026-10-30T14:00`

Fonts: Inter (SIL Open Font License), see `fonts/LICENSE-Inter.txt`.

## Messages from the iPhone (private)

`web/message.html` is published at `https://<owner>.github.io/kindle-weather/message.html`
(the page itself holds no secrets). It writes `message.txt` to the **private**
`kindle-messages` repository using a token kept only on the phone. A workflow there renders
the message for the Kindle; the Kindle reads it with its own read-only key
(`messages_key.txt` on the Kindle, never in this repository) and shows it until the chosen
time. Nothing about messages is published on this public site.

## Every hour

On the hour the Kindle plays a split-flap "departure board" (place and time, temperature,
feels like) for about 20 seconds, prepared by the workflow in `show/`.

## Setup notes

- Repository Settings → Pages → Source must be **GitHub Actions**.
- The Kindle updates its own scripts from `site/kindle/` (checked against `manifest.txt`)
  every ten minutes, so changes under `kindle/extensions/weatherdash` reach it over wifi.

