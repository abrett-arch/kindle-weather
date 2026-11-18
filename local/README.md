# Running the dashboard from the Mac

The Mac makes the screen every 10 minutes and the Kindle fetches it over the home wifi; GitHub is the hourly backstop.

- `install.sh` sets everything up (Python, two background jobs, the Kindle's address). Run it again whenever the Mac's wifi address changes, or with the Kindle plugged in to point the Kindle at the Mac.
- `render_site.sh` makes a new screen at 4, 14, 24, 34, 44 and 54 minutes past each hour (BOM posts a reading every 10 minutes). Its log is `render.log`.
- `serve.sh` serves the `site` folder on port 8080. Open `http://<the Mac's address>:8080/` in a browser to see the current screen.
- `uninstall.sh` stops both jobs.

While the Mac sleeps, the Kindle switches to GitHub's hourly screen, and back to the Mac when it wakes.

Phone messages go through GitHub (the private kindle-messages repository), not the Mac.

## Where the Kindle looks

The Kindle tries the addresses in its `config.sh` in order: `IMAGE_URL` (the Mac at 192.168.0.49), then each one in `IMAGE_URLS` (the Mac at 192.168.0.2, then GitHub). When the one it is using stops answering it moves to the next that does, and while it is on a later one it checks every ten minutes whether an earlier one (the Mac) is back. The address in use is remembered in `active_url` on the Kindle.

GitHub makes a new screen about once an hour, so while the Mac sleeps the Kindle shows a screen up to an hour or so old instead of the no-connection notice. The notice only appears when nothing on the list answers for 20 minutes.

If the modem gives the Mac an address that isn't on the list, plug the Kindle in and run `install.sh`: it puts the new address first and keeps the others (GitHub included) after it. To stop the address moving at all: System Settings → Wi-Fi → Details… → TCP/IP → Configure IPv4 → "Using DHCP with manual address" → 192.168.0.49.

`serve.log` lists every request the server answers, so a line from the Kindle's address every minute or so means it is checking in.
