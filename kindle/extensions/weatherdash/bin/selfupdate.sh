#!/bin/sh
# Over-the-air update of this extension from the published site (kindle/manifest.txt).
# Exit 0 = new code installed (caller should restart itself); 1 = nothing to do or failed.
. /mnt/us/extensions/weatherdash/bin/lib.sh
. "$DIR/config.sh"
BASE="${IMAGE_URL%/*}/kindle"
N="$DIR/update.new"
rm -rf "$N"; mkdir -p "$N"
get "$BASE/manifest.txt?t=$(date +%s)" "$N/manifest.txt" || exit 1
ver="$(sed -n 's/^version //p' "$N/manifest.txt")"
[ -n "$ver" ] || exit 1
[ "$ver" = "$(cat "$DIR/code_version" 2>/dev/null)" ] && { rm -rf "$N"; exit 1; }
# download and verify every file before touching anything
while read -r sum path; do
  [ "$sum" = "version" ] && continue
  [ -n "$path" ] || continue
  mkdir -p "$N/$(dirname "$path")"
  get "$BASE/$path" "$N/$path" || exit 1
  [ "$(md5sum "$N/$path" | cut -d' ' -f1)" = "$sum" ] || { echo "checksum mismatch: $path"; exit 1; }
  case "$path" in *.sh) sh -n "$N/$path" || { echo "syntax error: $path"; exit 1; } ;; esac
done < "$N/manifest.txt"
# install: keep a backup of the current code, then put each new file in place atomically
rm -rf "$DIR/previous"; mkdir -p "$DIR/previous/bin"
cp -f "$DIR"/bin/*.sh "$DIR/previous/bin/" 2>/dev/null
cp -f "$DIR/config.sh" "$DIR/menu.json" "$DIR/previous/" 2>/dev/null
while read -r sum path; do
  [ "$sum" = "version" ] && continue
  [ -n "$path" ] || continue
  mkdir -p "$DIR/$(dirname "$path")"
  cp -f "$N/$path" "$DIR/$path.tmp" && mv -f "$DIR/$path.tmp" "$DIR/$path" \
    || { echo "install failed at $path"; exit 1; }
done < "$N/manifest.txt"
echo "$ver" > "$DIR/code_version"
rm -rf "$N"
echo "installed $ver"
exit 0
