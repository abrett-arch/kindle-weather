# Weather dashboard settings (edit on the Kindle over USB, or ask Claude)
IMAGE_URL="http://192.168.0.49:8080/dash.png"
# Also tried, in this order, when the address above stops answering. The Kindle goes back to an earlier one
# (the Mac) as soon as it answers again. GitHub, last, renders about once an hour: the backstop for when the Mac sleeps.
IMAGE_URLS="http://192.168.0.2:8080/dash.png https://abrett-arch.github.io/kindle-weather/dash.png"
REFRESH_MINUTES=1       # how often to check for changes (a tiny file; the image downloads only when it changed)
BATTERY_REFRESH_MINUTES=3  # on battery: check this often instead (every minute near the hour)
LIGHT=16                # front light, kept on permanently: 0 (off) to 24 (brightest)
MSG_REPO="abrett-arch/kindle-messages"   # private repository the phone page writes messages to
