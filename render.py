#!/usr/bin/env python3
"""Render a Hobart weather dashboard as a greyscale PNG for a Kindle Paperwhite 3.

Data: Bureau of Meteorology (unofficial JSON API used by the BOM app/website),
falling back to Open-Meteo for anything BOM doesn't return.

Usage:
  python render.py                 # live data -> out/dash.png
  python render.py --sample        # sample data (no network) -> out/dash.png
  python render.py --out path.png
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------- settings
PLACE = "Hobart"
LAT, LON = -42.8821, 147.3272
TZ = ZoneInfo("Australia/Hobart")
W, H = 1072, 1448                     # Paperwhite 3 portrait, 300 ppi
M = 60                                # outer margin
HERE = Path(__file__).resolve().parent
FONTS = HERE / "fonts"
UA = "Mozilla/5.0 (kindle-weather dashboard; personal use)"

BLACK, DARK, MID, LIGHT, PALE, WHITE = 0, 60, 120, 190, 228, 255


# ---------------------------------------------------------------- helpers
WARNINGS: list[str] = []


def warn(msg: str) -> None:
    WARNINGS.append(msg)
    print(msg, file=sys.stderr)

def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / f"{name}.otf"), size)


def get_json(url: str, timeout: int = 20):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def parse_time(s: str | None) -> datetime | None:
    if not s:
        return None
    s = s.replace("Z", "+00:00")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=TZ)
    return dt.astimezone(TZ)


def fmt_time(dt: datetime | None) -> str:
    if not dt:
        return "—"
    h = dt.hour % 12 or 12
    return f"{h}:{dt.minute:02d} {'am' if dt.hour < 12 else 'pm'}"


def fmt_hour(dt: datetime) -> str:
    h = dt.hour % 12 or 12
    return f"{h}{'am' if dt.hour < 12 else 'pm'}"


def deg(v) -> str:
    return "—" if v is None else f"{round(v)}°"


COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
           "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


def compass(degrees) -> str:
    if degrees is None:
        return ""
    return COMPASS[int((degrees % 360) / 22.5 + 0.5) % 16]


UV_WORDS = [(3, "Low"), (6, "Moderate"), (8, "High"), (11, "Very high"), (99, "Extreme")]


def uv_word(uv) -> str:
    if uv is None:
        return ""
    for limit, word in UV_WORDS:
        if uv < limit:
            return word
    return "Extreme"


# ---------------------------------------------------------------- data: BOM
def geohash(lat: float, lon: float, precision: int = 6) -> str:
    chars = "0123456789bcdefghjkmnpqrstuvwxyz"
    lat_r, lon_r = [-90.0, 90.0], [-180.0, 180.0]
    out, bits, bit, even = [], 0, 0, True
    while len(out) < precision:
        rng, val = (lon_r, lon) if even else (lat_r, lat)
        mid = (rng[0] + rng[1]) / 2
        if val > mid:
            bits = bits * 2 + 1
            rng[0] = mid
        else:
            bits = bits * 2
            rng[1] = mid
        even = not even
        bit += 1
        if bit == 5:
            out.append(chars[bits])
            bits, bit = 0, 0
    return "".join(out)


BOM = "https://api.weather.bom.gov.au/v1"


def bom_geohash() -> str:
    try:
        res = get_json(f"{BOM}/locations?search={urllib.parse.quote(PLACE)}")
        for loc in res.get("data", []):
            if loc.get("name", "").lower() == PLACE.lower() and loc.get("state") == "TAS":
                return loc["geohash"][:6]
    except Exception as e:  # noqa: BLE001
        warn(f"BOM search failed: {e}")
    return geohash(LAT, LON, 6)


def fetch_bom() -> dict:
    gh = bom_geohash()
    out: dict = {"sources": set()}

    try:
        obs = get_json(f"{BOM}/locations/{gh}/observations")["data"]
        out["now"] = {
            "temp": obs.get("temp"),
            "feels": obs.get("temp_feels_like"),
            "wind_dir": (obs.get("wind") or {}).get("direction"),
            "wind_kmh": (obs.get("wind") or {}).get("speed_kilometre"),
            "gust_kmh": (obs.get("gust") or {}).get("speed_kilometre"),
            "humidity": obs.get("humidity"),
            "rain_since_9am": obs.get("rain_since_9am"),
            "station": (obs.get("station") or {}).get("name"),
        }
        out["sources"].add("BOM")
    except Exception as e:  # noqa: BLE001
        warn(f"BOM observations failed: {e}")

    try:
        days = []
        for d in get_json(f"{BOM}/locations/{gh}/forecasts/daily")["data"]:
            rain = d.get("rain") or {}
            amt = rain.get("amount") or {}
            astro = d.get("astronomical") or {}
            days.append({
                "date": parse_time(d["date"]).date(),
                "max": d.get("temp_max"),
                "min": d.get("temp_min"),
                "icon": d.get("icon_descriptor"),
                "text": d.get("short_text"),
                "rain_chance": rain.get("chance"),
                "rain_min": amt.get("min"),
                "rain_max": amt.get("max"),
                "sunrise": parse_time(astro.get("sunrise_time")),
                "sunset": parse_time(astro.get("sunset_time")),
                "uv": (d.get("uv") or {}).get("max_index"),
            })
        out["days"] = days
        out["sources"].add("BOM")
    except Exception as e:  # noqa: BLE001
        warn(f"BOM daily failed: {e}")

    try:
        hours = []
        for h in get_json(f"{BOM}/locations/{gh}/forecasts/hourly")["data"]:
            hours.append({
                "time": parse_time(h["time"]),
                "temp": h.get("temp"),
                "feels": h.get("temp_feels_like"),
                "rain_chance": (h.get("rain") or {}).get("chance"),
                "icon": h.get("icon_descriptor"),
                "is_night": h.get("is_night"),
            })
        out["hourly"] = hours
        out["sources"].add("BOM")
    except Exception as e:  # noqa: BLE001
        warn(f"BOM hourly failed: {e}")
    return out


# ---------------------------------------------------------------- data: Open-Meteo
WMO = {0: "sunny", 1: "mostly_sunny", 2: "partly_cloudy", 3: "cloudy",
       45: "fog", 48: "fog", 51: "light_shower", 53: "light_shower", 55: "shower",
       56: "light_rain", 57: "rain", 61: "light_rain", 63: "rain", 65: "heavy_shower",
       66: "light_rain", 67: "rain", 71: "snow", 73: "snow", 75: "snow", 77: "snow",
       80: "light_shower", 81: "shower", 82: "heavy_shower", 85: "snow", 86: "snow",
       95: "storm", 96: "storm", 99: "storm"}
WMO_TEXT = {"sunny": "Sunny", "mostly_sunny": "Mostly sunny", "partly_cloudy": "Partly cloudy",
            "cloudy": "Cloudy", "fog": "Fog", "light_shower": "Light showers", "shower": "Showers",
            "heavy_shower": "Heavy showers", "light_rain": "Light rain", "rain": "Rain",
            "snow": "Snow", "storm": "Thunderstorms"}


NOW_TEXT = {"sunny": "Sunny", "clear": "Clear", "mostly_sunny": "Mostly sunny",
            "partly_cloudy": "Partly cloudy", "cloudy": "Cloudy", "hazy": "Hazy", "dusty": "Dusty",
            "fog": "Foggy", "light_shower": "Light showers", "shower": "Showers",
            "heavy_shower": "Heavy showers", "light_rain": "Light rain", "rain": "Rain",
            "storm": "Storms", "snow": "Snow", "frost": "Frost", "windy": "Windy", "cyclone": "Cyclone"}


def fetch_open_meteo() -> dict:
    q = {
        "latitude": LAT, "longitude": LON, "timezone": "Australia/Hobart", "forecast_days": 7,
        "wind_speed_unit": "kmh",
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,"
                   "wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day",
        "hourly": "temperature_2m,apparent_temperature,precipitation_probability,weather_code,is_day",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,"
                 "precipitation_sum,sunrise,sunset,uv_index_max",
    }
    d = get_json("https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(q))
    c = d["current"]
    out = {"sources": {"Open-Meteo"}}
    out["now"] = {
        "temp": c.get("temperature_2m"), "feels": c.get("apparent_temperature"),
        "wind_dir": compass(c.get("wind_direction_10m")), "wind_kmh": c.get("wind_speed_10m"),
        "gust_kmh": c.get("wind_gusts_10m"), "humidity": c.get("relative_humidity_2m"),
        "rain_since_9am": None, "station": None,
        "icon": WMO.get(c.get("weather_code")), "is_night": not c.get("is_day", 1),
    }
    dd = d["daily"]
    out["days"] = [{
        "date": datetime.fromisoformat(dd["time"][i]).date(),
        "max": dd["temperature_2m_max"][i], "min": dd["temperature_2m_min"][i],
        "icon": WMO.get(dd["weather_code"][i]),
        "text": WMO_TEXT.get(WMO.get(dd["weather_code"][i]), ""),
        "rain_chance": dd["precipitation_probability_max"][i],
        "rain_min": None, "rain_max": dd["precipitation_sum"][i],
        "sunrise": parse_time(dd["sunrise"][i]), "sunset": parse_time(dd["sunset"][i]),
        "uv": dd["uv_index_max"][i],
    } for i in range(len(dd["time"]))]
    hh = d["hourly"]
    out["hourly"] = [{
        "time": parse_time(hh["time"][i]), "temp": hh["temperature_2m"][i],
        "feels": hh["apparent_temperature"][i],
        "rain_chance": hh["precipitation_probability"][i],
        "icon": WMO.get(hh["weather_code"][i]), "is_night": not hh["is_day"][i],
    } for i in range(len(hh["time"]))]
    return out


def fetch_live() -> dict:
    data = {"sources": set()}
    try:
        data = fetch_bom()
    except Exception as e:  # noqa: BLE001
        warn(f"BOM failed entirely: {e}")
    missing = [k for k in ("now", "days", "hourly") if not data.get(k)]
    if missing:
        try:
            om = fetch_open_meteo()
            for k in missing:
                data[k] = om[k]
            data["sources"] |= om["sources"]
        except Exception as e:  # noqa: BLE001
            warn(f"Open-Meteo failed: {e}")
    if not data.get("days"):
        raise SystemExit("No forecast data from any source")
    return data


# ---------------------------------------------------------------- sample data
def sample_data(now: datetime) -> dict:
    base = now.replace(minute=0, second=0, microsecond=0)
    today = now.date()
    days_spec = [
        (17, 8, "shower", "Showers easing.", 70, 1, 4),
        (19, 9, "partly_cloudy", "Partly cloudy.", 20, 0, 0.4),
        (22, 10, "mostly_sunny", "Mostly sunny.", 5, 0, 0),
        (16, 9, "rain", "Rain. Windy.", 90, 5, 15),
        (14, 6, "light_shower", "Shower or two.", 50, 0, 2),
        (18, 7, "sunny", "Sunny.", 0, 0, 0),
        (20, 10, "cloudy", "Cloudy.", 30, 0, 1),
    ]
    days = []
    for i, (mx, mn, icon, text, rc, rmin, rmax) in enumerate(days_spec):
        d = today + timedelta(days=i)
        days.append({
            "date": d, "max": mx, "min": mn, "icon": icon, "text": text,
            "rain_chance": rc, "rain_min": rmin, "rain_max": rmax,
            "sunrise": datetime(d.year, d.month, d.day, 5, 58, tzinfo=TZ),
            "sunset": datetime(d.year, d.month, d.day, 19, 59, tzinfo=TZ),
            "uv": 6 + (i % 3),
        })
    hourly = []
    for i in range(1, 26):
        t = base + timedelta(hours=i)
        temp = 12.5 + 5.5 * math.sin((t.hour - 9) / 24 * 2 * math.pi)
        rain = [70, 60, 50, 40, 30, 20, 10, 10, 5, 5, 5, 10, 10, 20, 30, 40, 50, 60, 60, 50, 40, 30, 20, 20, 10][i - 1]
        feels = temp - 2.2 - 1.3 * math.cos((t.hour - 3) / 24 * 2 * math.pi)
        hourly.append({"time": t, "temp": temp, "feels": feels, "rain_chance": rain,
                       "icon": "shower" if rain > 40 else "partly_cloudy",
                       "is_night": t.hour < 6 or t.hour >= 20})
    return {
        "sources": {"Sample data"},
        "now": {"temp": 11.4, "feels": 8.6, "wind_dir": "NW", "wind_kmh": 19, "gust_kmh": 35,
                "humidity": 72, "rain_since_9am": 2.4, "station": "Hobart (Ellerslie Road)"},
        "days": days, "hourly": hourly,
    }


# ---------------------------------------------------------------- icons
def _cloud(d: ImageDraw.ImageDraw, cx, cy, s, fill=LIGHT, outline=BLACK):
    """Cloud centred at (cx, cy), width ~ s."""
    lw = max(3, int(s * 0.045))
    parts = [  # (dx, dy, r) relative to s
        (-0.24, 0.06, 0.20), (0.0, -0.08, 0.27), (0.25, 0.04, 0.21),
    ]
    base = (cx - s * 0.44, cy + 0.02 * s, cx + s * 0.46, cy + 0.26 * s)
    for pad, colour in ((lw, outline), (0, fill)):
        for dx, dy, r in parts:
            rr = s * r + pad
            d.ellipse((cx + dx * s - rr, cy + dy * s - rr, cx + dx * s + rr, cy + dy * s + rr), fill=colour)
        d.rounded_rectangle((base[0] - pad, base[1] - pad, base[2] + pad, base[3] + pad),
                            radius=s * 0.12 + pad, fill=colour)


def _sun(d, cx, cy, s, rays=True):
    r = s * 0.2
    lw = max(3, int(s * 0.05))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=BLACK)
    if rays:
        for k in range(8):
            a = k * math.pi / 4
            r1, r2 = r * 1.45, r * 2.0
            d.line((cx + r1 * math.cos(a), cy + r1 * math.sin(a),
                    cx + r2 * math.cos(a), cy + r2 * math.sin(a)), fill=BLACK, width=lw)


def _moon(d, cx, cy, s):
    r = s * 0.26
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=BLACK)
    o = r * 0.55
    d.ellipse((cx - r + o, cy - r - o * 0.5, cx + r + o, cy + r - o * 0.5), fill=WHITE)


def _drops(d, cx, cy, s, n=3, heavy=False):
    lw = max(3, int(s * (0.06 if heavy else 0.045)))
    L = s * (0.18 if heavy else 0.13)
    for i in range(n):
        x = cx + (i - (n - 1) / 2) * s * 0.2
        d.line((x + L * 0.35, cy, x - L * 0.35, cy + L), fill=BLACK, width=lw)


def _flakes(d, cx, cy, s, n=3):
    lw = max(2, int(s * 0.035))
    r = s * 0.06
    for i in range(n):
        x = cx + (i - (n - 1) / 2) * s * 0.22
        y = cy + s * 0.06
        for k in range(3):
            a = k * math.pi / 3
            d.line((x - r * math.cos(a), y - r * math.sin(a), x + r * math.cos(a), y + r * math.sin(a)),
                   fill=BLACK, width=lw)


def _bolt(d, cx, cy, s):
    p = [(0.04, 0), (-0.1, 0.2), (0.0, 0.2), (-0.06, 0.38), (0.12, 0.14), (0.02, 0.14), (0.1, 0)]
    d.polygon([(cx + x * s, cy + y * s) for x, y in p], fill=BLACK)


def _fog(d, cx, cy, s):
    lw = max(3, int(s * 0.05))
    for i, w in enumerate((0.7, 0.55, 0.7, 0.45)):
        y = cy - s * 0.2 + i * s * 0.14
        d.line((cx - s * w / 2, y, cx + s * w / 2, y), fill=BLACK, width=lw)


def draw_icon(img: Image.Image, kind: str | None, box, night: bool = False):
    """Draw icon `kind` (BOM icon_descriptor vocabulary) centred in box (x0,y0,x1,y1)."""
    x0, y0, x1, y1 = box
    s = min(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    # draw at 3x and downsample for clean anti-aliased edges
    k = 3
    layer = Image.new("L", (int(s * k), int(s * k)), WHITE)
    d = ImageDraw.Draw(layer)
    S = s * k
    c = S / 2
    kind = (kind or "cloudy").lower()

    def celestial(x, y, size):
        (_moon if night else lambda dd, a, b, z: _sun(dd, a, b, z))(d, x, y, size)

    if kind in ("sunny", "clear"):
        celestial(c, c, S)
    elif kind == "mostly_sunny":
        celestial(c - S * 0.1, c - S * 0.12, S * 0.95)
        _cloud(d, c + S * 0.12, c + S * 0.14, S * 0.55, fill=PALE)
    elif kind == "partly_cloudy":
        celestial(c - S * 0.16, c - S * 0.16, S * 0.85)
        _cloud(d, c + S * 0.06, c + S * 0.08, S * 0.8)
    elif kind in ("cloudy", "hazy", "dusty"):
        _cloud(d, c + S * 0.16, c - S * 0.12, S * 0.6, fill=PALE)
        _cloud(d, c - S * 0.04, c + S * 0.06, S * 0.85)
    elif kind in ("light_shower", "shower", "heavy_shower"):
        celestial(c - S * 0.2, c - S * 0.24, S * 0.7)
        _cloud(d, c + S * 0.04, c - S * 0.02, S * 0.8)
        _drops(d, c + S * 0.02, c + S * 0.26, S, n=2 if kind == "light_shower" else 3,
               heavy=kind == "heavy_shower")
    elif kind in ("light_rain", "rain"):
        _cloud(d, c, c - S * 0.1, S * 0.9)
        _drops(d, c, c + S * 0.22, S, n=2 if kind == "light_rain" else 3, heavy=kind == "rain")
    elif kind in ("storm", "cyclone"):
        _cloud(d, c, c - S * 0.12, S * 0.9, fill=MID)
        _bolt(d, c, c + S * 0.08, S)
    elif kind in ("snow", "frost"):
        _cloud(d, c, c - S * 0.12, S * 0.9)
        _flakes(d, c, c + S * 0.22, S)
    elif kind == "fog":
        _cloud(d, c, c - S * 0.18, S * 0.8, fill=PALE)
        _fog(d, c, c + S * 0.18, S * 0.9)
    elif kind == "windy":
        lw = int(S * 0.045)
        for i, (w, off) in enumerate(((0.62, 0), (0.75, 0.05), (0.5, -0.06))):
            y = c - S * 0.16 + i * S * 0.16
            d.line((c - S * w / 2 + S * off, y, c + S * w / 2 + S * off, y), fill=BLACK, width=lw)
            d.arc((c + S * w / 2 + S * off - S * 0.08, y - S * 0.16, c + S * w / 2 + S * off + S * 0.08, y),
                  start=270, end=110, fill=BLACK, width=lw)
    else:
        _cloud(d, c, c, S * 0.85)

    layer = layer.resize((int(s), int(s)), Image.LANCZOS)
    img.paste(layer, (int(cx - s / 2), int(cy - s / 2)))


# ---------------------------------------------------------------- split-flap numbers
FLAP = True        # split-flap tiles for the big temperatures (--plain turns off)
TILE_OVERRIDE: dict | None = None   # {"temp": [spec,...], "feels": [...]} while drawing animation frames
HERO_BOX = (0, 0, W, H)             # filled in by render(): region the flip animation repaints
DRUM = " -0123456789"               # order of characters on each flap drum


def tile_text(value) -> str:
    """Characters shown on the tiles: at least two tiles, blank-padded on the left."""
    return ("--" if value is None else str(round(value))).rjust(2)


def _tile(ch: str, tile_w: int, tile_h: int) -> Image.Image:
    t = Image.new("L", (tile_w, tile_h), WHITE)
    d = ImageDraw.Draw(t)
    rad = int(tile_w * 0.1)
    mid = tile_h // 2
    d.rounded_rectangle((0, 0, tile_w - 1, tile_h - 1), radius=rad, fill=40)          # lower flap
    d.rounded_rectangle((0, 0, tile_w - 1, mid), radius=rad, fill=62)                 # upper flap
    d.rectangle((0, mid - rad, tile_w - 1, mid), fill=62)
    if ch.strip():
        f = font("InterDisplay-SemiBold", int(tile_h * 0.80))
        cw = d.textlength(ch, font=f)
        bb = d.textbbox((0, 0), ch, font=f)
        d.text(((tile_w - cw) / 2, (tile_h - (bb[3] - bb[1])) / 2 - bb[1]), ch, font=f, fill=WHITE)
    d.line((0, mid, tile_w, mid), fill=WHITE, width=3)                                # the split
    for hx in (5, tile_w - 11):                                                       # hinge notches
        d.rectangle((hx, mid - 7, hx + 6, mid + 7), fill=WHITE)
    return t


def draw_flap_number(img, specs, x, y, tile_w=100, tile_h=168):
    """Draw tiles. Each spec is a character, or (top, bottom) for a tile caught mid-flip:
    the upper half already shows the next character, the lower half still the old one."""
    d = ImageDraw.Draw(img)
    gap = int(tile_w * 0.08)
    mid = tile_h // 2
    for i, spec in enumerate(specs):
        x0 = x + i * (tile_w + gap)
        if isinstance(spec, tuple):
            top, bottom = _tile(spec[0], tile_w, tile_h), _tile(spec[1], tile_w, tile_h)
            img.paste(top.crop((0, 0, tile_w, mid)), (x0, y))
            img.paste(bottom.crop((0, mid, tile_w, tile_h)), (x0, y + mid))
            d.line((x0, y + mid, x0 + tile_w, y + mid), fill=WHITE, width=3)
        else:
            img.paste(_tile(spec, tile_w, tile_h), (x0, y))
    dx = x + len(specs) * (tile_w + gap) + 4
    r = tile_h * 0.085
    d.ellipse((dx, y + 4, dx + 2 * r, y + 4 + 2 * r), outline=BLACK, width=max(4, int(r * 0.42)))


def flip_frames(old: str, new: str, max_steps: int = 6) -> list[list]:
    """Tile specs for each animation frame taking `old` to `new` (strings of tile characters).
    Each tile rolls forward round its drum (capped at max_steps flips); every flip is two
    frames: mid-flip (top new / bottom old), then settled."""
    n = max(len(old), len(new))
    old, new = old.rjust(n), new.rjust(n)
    paths = []
    for a, b in zip(old, new):
        ia, ib = DRUM.index(a) if a in DRUM else 0, DRUM.index(b) if b in DRUM else 0
        dist = (ib - ia) % len(DRUM)
        steps = min(dist, max_steps)
        paths.append([DRUM[(ib - steps + k + 1) % len(DRUM)] for k in range(steps)])
    frames, cur = [], list(old)
    for step in range(max((len(p) for p in paths), default=0)):
        nxt = [p[step] if step < len(p) else cur[i] for i, p in enumerate(paths)]
        frames.append([(nxt[i], cur[i]) if nxt[i] != cur[i] else cur[i] for i in range(n)])
        frames.append(list(nxt))
        cur = nxt
    return frames


# ---------------------------------------------------------------- render
def text_w(d, txt, f):
    return d.textlength(txt, font=f)


def render(data: dict, now: datetime) -> Image.Image:
    img = Image.new("L", (W, H), WHITE)
    d = ImageDraw.Draw(img)

    f_place = font("InterDisplay-Bold", 62)
    f_date = font("Inter-Medium", 34)
    f_small = font("Inter-Regular", 28)
    f_small_b = font("Inter-SemiBold", 28)
    f_temp = font("InterDisplay-SemiBold", 220)
    f_cond = font("InterDisplay-SemiBold", 46)
    f_det = font("Inter-Regular", 33)
    f_det_b = font("Inter-SemiBold", 33)
    f_h2 = font("Inter-SemiBold", 30)
    f_row = font("Inter-Medium", 36)
    f_row_b = font("InterDisplay-Bold", 40)
    f_row_s = font("Inter-Regular", 30)
    f_axis = font("Inter-Medium", 25)

    days = data.get("days") or []
    hourly = [h for h in (data.get("hourly") or []) if h["time"] and h["time"] > now][:24]
    now_obs = data.get("now") or {}
    today = next((x for x in days if x["date"] == now.date()), days[0] if days else {})
    tomorrow_idx = next((i for i, x in enumerate(days) if x["date"] > now.date()), None)

    # is it night? use today's sunrise/sunset when known
    sr, ss = today.get("sunrise"), today.get("sunset")
    night = bool(sr and ss and not (sr <= now <= ss))

    # ---- header
    y = 52
    d.text((M, y), PLACE, font=f_place, fill=BLACK)
    d.text((M, y + 78), now.strftime("%A %-d %B"), font=f_date, fill=MID)
    upd = f"Updated {fmt_time(now)}"
    d.text((W - M - text_w(d, upd, f_small), y + 22), upd, font=f_small, fill=MID)
    if sr and ss:
        sun = f"↑ {fmt_time(sr)}   ↓ {fmt_time(ss)}"
        d.text((W - M - text_w(d, sun, f_small), y + 84), sun, font=f_small, fill=MID)

    # ---- hero: icon | temperature | feels like  (equal weight)
    hero_y = 188
    global HERO_BOX
    HERO_BOX = (M + 270, hero_y, W - M, hero_y + 182)
    h0 = hourly[0] if hourly else {}
    icon_now = now_obs.get("icon") or h0.get("icon") or today.get("icon")
    draw_icon(img, icon_now, (M + 12, hero_y + 2, M + 212, hero_y + 182), night=night)
    cond = NOW_TEXT.get((icon_now or "").lower(), "")
    if night and cond in ("Sunny", "Mostly sunny"):
        cond = {"Sunny": "Clear", "Mostly sunny": "Mostly clear"}[cond]
    f_cond = font("InterDisplay-SemiBold", 36)
    d.text((M + 112 - text_w(d, cond, f_cond) / 2, hero_y + 180), cond, font=f_cond, fill=BLACK)

    t_now = now_obs.get("temp") if now_obs.get("temp") is not None else h0.get("temp")
    f_now = now_obs.get("feels") if now_obs.get("feels") is not None else h0.get("feels")
    col_w = (W - M - (M + 270)) // 2
    for ci, (val, lab) in enumerate(((t_now, "TEMPERATURE"), (f_now, "FEELS LIKE"))):
        cx0 = M + 270 + ci * col_w
        if FLAP:
            key = "temp" if ci == 0 else "feels"
            specs = (TILE_OVERRIDE or {}).get(key) or list(tile_text(val))
            draw_flap_number(img, specs, cx0 + 8, hero_y + 6)
        else:
            d.text((cx0, hero_y - 22), deg(val), font=font("InterDisplay-SemiBold", 190), fill=BLACK)
        d.text((cx0 + 8, hero_y + 184), lab, font=font("Inter-SemiBold", 30), fill=MID)

    # ---- stats strip: wind | humidity | rain since 9am
    sy0 = 452
    d.line((M, sy0 - 22, W - M, sy0 - 22), fill=LIGHT, width=2)
    f_lab = font("Inter-SemiBold", 26)
    f_val = font("InterDisplay-Bold", 56)
    f_unit = font("Inter-Medium", 30)
    f_sub = font("Inter-Regular", 28)
    stats = []
    if now_obs.get("wind_kmh") is not None:
        stats.append(("WIND", f"{now_obs.get('wind_dir') or ''} {round(now_obs['wind_kmh'])}".strip(), " km/h",
                      f"gusts {round(now_obs['gust_kmh'])} km/h" if now_obs.get("gust_kmh") else ""))
    if now_obs.get("humidity") is not None:
        stats.append(("HUMIDITY", f"{round(now_obs['humidity'])}", "%", ""))
    if now_obs.get("rain_since_9am") is not None:
        stats.append(("RAIN SINCE 9AM", f"{now_obs['rain_since_9am']:g}", " mm", ""))
    elif pday_preview := (today.get("rain_chance")):
        stats.append(("RAIN CHANCE", f"{pday_preview}", "%", "today"))
    if stats:
        sw = (W - 2 * M) / len(stats)
        for i, (lab, val, unit, sub) in enumerate(stats):
            x0 = M + i * sw + (0 if i == 0 else 28)
            if i:
                d.line((M + i * sw, sy0, M + i * sw, sy0 + 108), fill=LIGHT, width=2)
            d.text((x0, sy0), lab, font=f_lab, fill=MID)
            d.text((x0, sy0 + 30), val, font=f_val, fill=BLACK)
            d.text((x0 + text_w(d, val, f_val) + 2, sy0 + 52), unit, font=f_unit, fill=DARK)
            if sub:
                d.text((x0, sy0 + 98), sub, font=f_sub, fill=MID)

    # ---- day summary panel (today, or tomorrow once it's evening)
    py0, py1 = 598, 718
    show_tomorrow = now.hour >= 18 and tomorrow_idx is not None
    pday = days[tomorrow_idx] if show_tomorrow else today
    d.rounded_rectangle((M, py0, W - M, py1), radius=22, fill=PALE)
    label = "Tomorrow" if show_tomorrow else "Today"
    d.text((M + 32, py0 + 14), label.upper(), font=f_h2, fill=MID)
    hi_lo = f"{deg(pday.get('min'))}  –  {deg(pday.get('max'))}"
    d.text((M + 32, py0 + 46), hi_lo, font=font("InterDisplay-Bold", 56), fill=BLACK)
    rx = M + 380
    d.text((rx, py0 + 16), (pday.get("text") or "").rstrip("."), font=f_row, fill=BLACK)
    bits = []
    if pday.get("rain_chance") is not None:
        r = f"{pday['rain_chance']}% rain"
        if pday.get("rain_max"):
            lo = pday.get("rain_min") or 0
            r += f", {lo:g}–{pday['rain_max']:g} mm" if lo != pday["rain_max"] else f", {lo:g} mm"
        bits.append(r)
    if pday.get("uv") is not None:
        bits.append(f"UV {round(pday['uv'])} {uv_word(pday['uv']).lower()}")
    d.text((rx, py0 + 68), " · ".join(bits), font=f_row_s, fill=DARK)

    # ---- hourly chart: temperature (solid) + feels like (dashed) + rain chance bars
    cy0 = 736
    d.text((M, cy0), "NEXT 24 HOURS", font=f_h2, fill=MID)
    # legend
    lx = W - M
    for name, kind in (("Rain chance", "bar"), ("Feels like", "dash"), ("Temp", "solid")):
        tw = text_w(d, name, f_axis)
        lx -= tw
        d.text((lx, cy0 + 4), name, font=f_axis, fill=DARK)
        lx -= 50
        ly = cy0 + 20
        if kind == "solid":
            d.line((lx, ly, lx + 38, ly), fill=BLACK, width=6)
        elif kind == "dash":
            for k_ in range(0, 38, 14):
                d.line((lx + k_, ly, lx + min(k_ + 8, 38), ly), fill=DARK, width=5)
        else:
            d.rectangle((lx + 10, ly - 13, lx + 28, ly + 11), fill=PALE)
            d.rectangle((lx + 10, ly - 2, lx + 28, ly + 11), fill=DARK)
        lx -= 26
    gx0, gx1 = M + 6, W - M - 6
    gt0, gt1 = cy0 + 90, cy0 + 186          # temperature band
    gr0, gr1 = cy0 + 270, cy0 + 330         # rain-chance band (0-100%)
    if len(hourly) >= 2:
        vals = [v for h in hourly for v in (h.get("temp"), h.get("feels")) if v is not None]
        tmin, tmax = math.floor(min(vals)), math.ceil(max(vals))
        if tmax - tmin < 6:
            pad = (6 - (tmax - tmin)) / 2
            tmin, tmax = tmin - pad, tmax + pad
        n = len(hourly)
        step = (gx1 - gx0) / (n - 1)
        xs = [gx0 + i * step for i in range(n)]

        def ty(t):
            return gt1 - (t - tmin) / (tmax - tmin) * (gt1 - gt0)

        for i, h in enumerate(hourly):          # night shading
            if h.get("is_night"):
                xa = xs[i] - step / 2
                d.rectangle((max(gx0, xa), gt0 - 44, min(gx1, xa + step), gt1 + 40), fill=PALE)
        # rain chance: one pale 0-100% track per hour, filled to the chance; % row above
        f_pct = font("Inter-SemiBold", 25)
        bw = max(6, step * 0.6)
        for i, h in enumerate(hourly):
            rc = max(0, min(100, h.get("rain_chance") or 0))
            d.rectangle((xs[i] - bw / 2, gr0, xs[i] + bw / 2, gr1), fill=PALE)
            if rc > 0:
                d.rectangle((xs[i] - bw / 2, gr1 - max(3, (gr1 - gr0) * rc / 100), xs[i] + bw / 2, gr1), fill=DARK)
        for i, h in enumerate(hourly):
            if i % 3 or h.get("rain_chance") is None:
                continue
            rc = round(h["rain_chance"])
            lab = f"{rc}%"
            lw_ = text_w(d, lab, f_pct)
            xl = min(max(xs[i] - lw_ / 2, gx0 - 6), gx1 - lw_ + 6)
            d.text((xl, gr0 - 34), lab, font=f_pct, fill=BLACK if rc >= 30 else MID)
        k = 3                                   # lines, supersampled
        LW, LH = gx1 - gx0 + 40, gt1 - gt0 + 100
        def series(key):
            return [((x - gx0 + 20) * k, (ty(h[key]) - gt0 + 50) * k)
                    for x, h in zip(xs, hourly) if h.get(key) is not None]
        feels_pts, temp_pts = series("feels"), series("temp")
        if len(feels_pts) >= 2:
            fl = Image.new("L", (LW * k, LH * k), 0)
            fd = ImageDraw.Draw(fl)
            dash, gap, acc, on = 16 * k, 10 * k, 0.0, True
            for (xa, ya), (xb, yb) in zip(feels_pts, feels_pts[1:]):
                seg = math.hypot(xb - xa, yb - ya)
                pos = 0.0
                while pos < seg:
                    run = min((dash if on else gap) - acc, seg - pos)
                    if on:
                        t0, t1 = pos / seg, (pos + run) / seg
                        fd.line((xa + (xb - xa) * t0, ya + (yb - ya) * t0,
                                 xa + (xb - xa) * t1, ya + (yb - ya) * t1), fill=255, width=5 * k)
                    pos += run
                    acc += run
                    if acc >= (dash if on else gap) - 1e-6:
                        acc, on = 0.0, not on
            fl = fl.resize((LW, LH), Image.LANCZOS)
            img.paste(DARK, (gx0 - 20, gt0 - 50), fl)
        if len(temp_pts) >= 2:
            tl = Image.new("L", (LW * k, LH * k), 0)
            td = ImageDraw.Draw(tl)
            td.line(temp_pts, fill=255, width=7 * k, joint="curve")
            tl = tl.resize((LW, LH), Image.LANCZOS)
            img.paste(BLACK, (gx0 - 20, gt0 - 50), tl)

        for i, h in enumerate(hourly):          # labels every 3 hours
            if i % 3:
                continue
            t, fe = h.get("temp"), h.get("feels")
            if t is not None:
                above = fe is None or t >= fe
                lab = deg(t)
                lw_ = text_w(d, lab, f_small_b)
                d.text((xs[i] - lw_ / 2, ty(t) - 44 if above else ty(t) + 10), lab, font=f_small_b, fill=BLACK)
            if fe is not None and round(fe) != round(t if t is not None else -99):
                lab = deg(fe)
                lw_ = text_w(d, lab, f_small)
                below = t is None or fe < t
                d.text((xs[i] - lw_ / 2, ty(fe) + 8 if below else ty(fe) - 42), lab, font=f_small, fill=MID)
            lab = fmt_hour(h["time"])
            lw_ = text_w(d, lab, f_axis)
            d.text((min(max(xs[i] - lw_ / 2, gx0 - 6), gx1 - lw_ + 6), gr1 + 10), lab, font=f_axis, fill=MID)

    # ---- next days
    ry = 1130
    d.line((M, ry - 18, W - M, ry - 18), fill=LIGHT, width=2)
    start = (tomorrow_idx + 1) if show_tomorrow else (tomorrow_idx or 1)
    rows = [x for x in days[start:start + 5]]
    row_h = 54
    for i, day in enumerate(rows):
        y0 = ry + i * row_h
        d.text((M, y0 + 4), day["date"].strftime("%a"), font=f_row_b, fill=BLACK)
        draw_icon(img, day.get("icon"), (M + 104, y0 - 2, M + 154, y0 + 48))
        d.text((M + 178, y0 + 8), (day.get("text") or "").rstrip("."), font=f_row_s, fill=DARK)
        rc = day.get("rain_chance")
        if rc is not None:
            rtxt = f"{rc}%"
            d.text((W - M - 290 - text_w(d, rtxt, f_row_s), y0 + 8), rtxt, font=f_row_s,
                   fill=BLACK if rc >= 50 else MID)
        lo, hi = deg(day.get("min")), deg(day.get("max"))
        d.text((W - M - 230, y0 + 4), lo, font=f_row, fill=MID)
        d.text((W - M - text_w(d, hi, f_row_b), y0 + 2), hi, font=f_row_b, fill=BLACK)

    # ---- footer
    src = " + ".join(sorted(data.get("sources") or []))
    station = now_obs.get("station")
    foot = f"{src}" + (f" · obs {station}" if station else "")
    d.text((M, H - 36), foot, font=font("Inter-Regular", 22), fill=LIGHT)
    return img


def hero_values(data: dict, now: datetime):
    hourly = [h for h in (data.get("hourly") or []) if h["time"] and h["time"] > now]
    h0 = hourly[0] if hourly else {}
    obs = data.get("now") or {}
    t = obs.get("temp") if obs.get("temp") is not None else h0.get("temp")
    f = obs.get("feels") if obs.get("feels") is not None else h0.get("feels")
    return t, f


def main():
    import hashlib
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", action="store_true", help="use built-in sample data")
    ap.add_argument("--out", default=str(HERE / "out" / "dash.png"))
    ap.add_argument("--now", help="pretend local time, e.g. 2026-10-30T14:00")
    ap.add_argument("--plain", action="store_true", help="plain numbers instead of split-flap tiles")
    ap.add_argument("--prev", help="previous state.json (to animate from)")
    ap.add_argument("--fake-prev", help="pretend previous tiles, e.g. '9,7' (testing)")
    a = ap.parse_args()
    global FLAP, TILE_OVERRIDE
    FLAP = not a.plain
    now = datetime.now(TZ)
    if a.now:
        now = datetime.fromisoformat(a.now).replace(tzinfo=TZ)
    data = sample_data(now) if a.sample else fetch_live()

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img = render(data, now)
    img.save(out, optimize=True)
    digest = hashlib.md5(out.read_bytes()).hexdigest()

    t, f = hero_values(data, now)
    state = {"temp": tile_text(t), "feels": tile_text(f), "generated": now.isoformat()}
    (out.parent / "state.json").write_text(json.dumps(state))
    (out.parent / "status.json").write_text(json.dumps({
        "generated": now.isoformat(), "sources": sorted(data["sources"]), "warnings": WARNINGS,
        "now": {k: v for k, v in (data.get("now") or {}).items() if isinstance(v, (int, float, str)) or v is None},
        "today": {k: str(v) for k, v in (data.get("days") or [{}])[0].items()},
    }, indent=1))

    # flip animation: frames of the tile area going from the previous reading to this one
    prev = None
    if a.fake_prev:
        pt, pf = a.fake_prev.split(",")
        prev = {"temp": pt.rjust(2), "feels": pf.rjust(2)}
    elif a.prev and Path(a.prev).is_file():
        try:
            prev = json.loads(Path(a.prev).read_text())
        except Exception:  # noqa: BLE001
            prev = None
    anim_dir = out.parent / "anim"
    anim_dir.mkdir(exist_ok=True)
    for old in anim_dir.glob("f*.png"):
        old.unlink()
    lines = [f"id {digest}"]
    if FLAP and prev:
        ft = flip_frames(prev.get("temp", state["temp"]), state["temp"])
        ff = flip_frames(prev.get("feels", state["feels"]), state["feels"])
        n = max(len(ft), len(ff))
        x0, y0, x1, y1 = HERO_BOX
        for i in range(n):
            TILE_OVERRIDE = {"temp": ft[i] if i < len(ft) else list(state["temp"]),
                             "feels": ff[i] if i < len(ff) else list(state["feels"])}
            frame = render(data, now).crop(HERO_BOX)
            name = f"f{i:02d}.png"
            frame.save(anim_dir / name, optimize=True)
            lines.append(f"{name} {x0} {y0}")
        TILE_OVERRIDE = None
    (anim_dir / "anim.txt").write_text("\n".join(lines) + "\n")
    print(f"wrote {out} ({', '.join(sorted(data['sources']))}); {len(lines) - 1} flip frames")


if __name__ == "__main__":
    main()
