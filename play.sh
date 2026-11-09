#!/usr/bin/env bash
#
# play.sh — launch Hitman: Contracts.
#
#   ./play.sh                      fullscreen (native resolution)
#   ./play.sh --windowed           1280x720 window
#   ./play.sh --windowed 1600x900  custom window size
#
# Set WINEDEBUG to see Wine output, e.g.  WINEDEBUG=+loaddll ./play.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

[ -f "$SCRIPT_DIR/env.sh" ] || { echo "error: env.sh not found next to play.sh — run setup.sh first" >&2; exit 1; }
# shellcheck source=/dev/null
source "$SCRIPT_DIR/env.sh"

GDIR="$WINEPREFIX/drive_c/Games/HitmanContracts"
[ -f "$GDIR/HitmanContracts.exe" ] || { echo "error: game not found at $GDIR" >&2; exit 1; }

MODE="${1:-}"
SIZE="${2:-1280x720}"

case "$MODE" in
  ""|--fullscreen) MODE="fullscreen" ;;
  --windowed)
      printf '%s' "$SIZE" | grep -qE '^[0-9]{3,5}x[0-9]{3,5}$' \
        || { echo "error: window size must look like 1600x900, got: $SIZE" >&2; exit 1; }
      MODE="windowed" ;;
  *)  echo "error: unknown option: $MODE  (try --help)" >&2; exit 1 ;;
esac

# Wine's virtual desktop is a per-prefix registry setting, so set it to match the
# mode we were asked for rather than inheriting whatever the last run used.
REG="$(mktemp "${TMPDIR:-/tmp}/hitman-vd.XXXXXX")"
trap 'rm -f "$REG"' EXIT
if [ "$MODE" = "windowed" ]; then
  printf 'Windows Registry Editor Version 5.00\n\n[HKEY_CURRENT_USER\\Software\\Wine\\Explorer]\n"Desktop"="Default"\n\n[HKEY_CURRENT_USER\\Software\\Wine\\Explorer\\Desktops]\n"Default"="%s"\n' "$SIZE" > "$REG"
else
  printf 'Windows Registry Editor Version 5.00\n\n[HKEY_CURRENT_USER\\Software\\Wine\\Explorer]\n"Desktop"=-\n' > "$REG"
fi
WINEDEBUG=-all "$WINE" regedit "$REG" >/dev/null 2>&1 || true

cd "$GDIR"
# Note: deliberately no "$@" here — our own flags are not the game's flags.
exec "$WINE" 'C:\Games\HitmanContracts\HitmanContracts.exe'
