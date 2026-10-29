# kindle-weather

An always-on Hobart weather screen for a jailbroken Kindle Paperwhite (7th gen, 1072×1448).

- `render.py` fetches the Bureau of Meteorology forecast and observations (falling back to
  Open-Meteo for anything BOM doesn't return) and draws `dash.png`, plus split-flap
  animation frames whenever the temperature or feels-like temperature changes.
- `.github/workflows/dash.yml` runs it every 15 minutes and publishes the result to GitHub
  Pages at `https://<owner>.github.io/kindle-weather/dash.png`.
- `kindle/extensions/weatherdash` is the KUAL extension on the Kindle: it downloads the
  image every few minutes, plays the flip animation, and redraws.

Local preview without network: `python render.py --sample --now 2026-10-30T14:00`

Fonts: Inter (SIL Open Font License), see `fonts/LICENSE-Inter.txt`.
