#!/usr/bin/env bash
#
# setup.sh — build a self-contained Wine prefix that runs Hitman: Contracts on macOS.
#
# You must already own the game. This script never downloads game content; it copies
# the Windows files from a directory you point it at (--game-dir).
#
# Usage:  ./setup.sh --game-dir /path/to/Hitman\ Contracts
#         ./setup.sh --help
#
set -euo pipefail

# ---------------------------------------------------------------- configuration
APP_NAME="Hitman: Contracts"
INSTALL_ROOT="${HC_INSTALL_ROOT:-$HOME/Games}"
GAMEDIR="$INSTALL_ROOT/HitmanContracts"
ENGDIR="$INSTALL_ROOT/.engines"

# Wine engine + support template, from the Sikarugir (Wineskin successor) project.
# WineCX32Bit is required: Contracts is a 32-bit DX8 game, and this engine is the
# wine32on64 build that can still run 32-bit code on Apple Silicon / modern macOS.
ENGINE="WS11WineCX32Bit21.2.0"
TEMPLATE="Template-1.0.27"
ENGINE_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0/${ENGINE}.tar.xz"
TEMPLATE_URL="https://github.com/Sikarugir-App/Template/releases/download/v1.0/${TEMPLATE}.tar.xz"
ENGINE_SHA256="fc82109b0f5135be2972fcbb313607ccb9f595301c0c3631ab046ee8220a3c39"
TEMPLATE_SHA256="dd0778f7b553d63df9b0f4e2cda3f3c6c005aabb75588c84d604afe80cdedbb9"

RESOLUTION="1920x1080"
GAME_SRC=""
WSFIX_SRC=""
FORCE=0
SKIP_VERIFY=0

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------- helpers
c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_red=$'\033[31m'
c_grn=$'\033[32m'; c_ylw=$'\033[33m'; c_blu=$'\033[34m'

step() { printf '%s==>%s %s%s\n' "$c_blu$c_bold" "$c_reset" "$c_bold" "$1$c_reset"; }
info() { printf '    %s\n' "$1"; }
ok()   { printf '    %s✓%s %s\n' "$c_grn" "$c_reset" "$1"; }
warn() { printf '    %s!%s %s\n' "$c_ylw" "$c_reset" "$1" >&2; }
die()  { printf '%serror:%s %s\n' "$c_red$c_bold" "$c_reset" "$1" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

usage() {
  cat <<USAGE
${c_bold}$APP_NAME on macOS${c_reset}

  ./setup.sh --game-dir <path> [options]

${c_bold}Required${c_reset}
  --game-dir <path>     Directory holding your Windows copy of the game
                        (must contain HitmanContracts.exe). See README for how to
                        get these files from Steam on a Mac using steamcmd.

${c_bold}Options${c_reset}
  --resolution <WxH>    Render resolution. Default: $RESOLUTION
  --widescreen-dir <p>  Install a widescreen fix from this directory.
                        Expects d3d8.dll, h3w.dll and h3.ini. Not bundled; see README.
  --install-root <path> Where to put the prefix and engines. Default: $INSTALL_ROOT
  --force               Reinstall over an existing prefix (deletes it first).
  --skip-verify         Skip SHA-256 verification of downloads (not recommended).
  -h, --help            This message.

${c_bold}After setup${c_reset}
  $GAMEDIR/play.sh                  # fullscreen
  $GAMEDIR/play.sh --windowed       # 1280x720 window
  $GAMEDIR/play.sh --windowed 1600x900
USAGE
}

# --------------------------------------------------------------- argument parse
while [ $# -gt 0 ]; do
  case "$1" in
    --game-dir)       GAME_SRC="${2:-}"; shift 2 ;;
    --resolution)     RESOLUTION="${2:-}"; shift 2 ;;
    --widescreen-dir) WSFIX_SRC="${2:-}"; shift 2 ;;
    --install-root)   INSTALL_ROOT="${2:-}"; GAMEDIR="$INSTALL_ROOT/HitmanContracts"; ENGDIR="$INSTALL_ROOT/.engines"; shift 2 ;;
    --force)          FORCE=1; shift ;;
    --skip-verify)    SKIP_VERIFY=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                die "unknown argument: $1  (try --help)" ;;
  esac
done

[ -n "$RESOLUTION" ] || die "--resolution needs a value like 1920x1080"
printf '%s' "$RESOLUTION" | grep -qE '^[0-9]{3,5}x[0-9]{3,5}$' \
  || die "--resolution must look like 1920x1080, got: $RESOLUTION"

# -------------------------------------------------------------------- preflight
step "Checking the machine"
[ "$(uname -s)" = "Darwin" ] || die "this script is macOS-only (got $(uname -s))"
need_cmd curl; need_cmd tar; need_cmd shasum; need_cmd awk
ok "macOS $(sw_vers -productVersion) on $(uname -m)"

if [ "$(uname -m)" = "arm64" ]; then
  # wine32on64 runs 32-bit Windows code inside a 64-bit process, so Rosetta is
  # what actually executes the x86 side on Apple Silicon.
  if /usr/bin/pgrep -q oahd 2>/dev/null || [ -d /Library/Apple/usr/libexec/oah ]; then
    ok "Apple Silicon with Rosetta 2 present"
  else
    warn "Rosetta 2 not detected. Install it with:  softwareupdate --install-rosetta"
  fi
fi

# ------------------------------------------------------------ locate game files
step "Locating your game files"
if [ -z "$GAME_SRC" ]; then
  for cand in \
    "$HOME/Library/Application Support/Steam/steamapps/common/Hitman Contracts" \
    "$HOME/Steam/steamapps/common/Hitman Contracts" \
    "/Applications/Hitman Contracts" ; do
    if [ -f "$cand/HitmanContracts.exe" ]; then GAME_SRC="$cand"; break; fi
  done
fi
[ -n "$GAME_SRC" ] || die "no game directory given. Pass --game-dir <path> (see --help)"
[ -d "$GAME_SRC" ] || die "--game-dir is not a directory: $GAME_SRC"
[ -f "$GAME_SRC/HitmanContracts.exe" ] \
  || die "HitmanContracts.exe not found in: $GAME_SRC"
GAME_SRC="$(cd "$GAME_SRC" && pwd)"
SRC_MB=$(du -sm "$GAME_SRC" | cut -f1)
ok "found game at $GAME_SRC (${SRC_MB} MB)"

# A complete install is ~860 MB; warn rather than fail, since trimmed copies exist.
if [ "$SRC_MB" -lt 500 ]; then
  warn "that looks small for a full install (~860 MB expected) — continuing anyway"
fi

AVAIL_MB=$(df -m "$INSTALL_ROOT" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
NEED_MB=$(( SRC_MB + 900 ))
if [ "${AVAIL_MB:-0}" -gt 0 ] && [ "$AVAIL_MB" -lt "$NEED_MB" ]; then
  die "not enough free space: need ~${NEED_MB} MB, have ${AVAIL_MB} MB"
fi

# ---------------------------------------------------------- existing prefix?
PREFIX="$GAMEDIR/prefix"
if [ -d "$PREFIX" ]; then
  if [ "$FORCE" = "1" ]; then
    step "Removing existing prefix (--force)"
    rm -rf "$PREFIX"
    ok "removed $PREFIX"
  else
    die "a prefix already exists at $PREFIX
       Re-run with --force to rebuild it, or --install-root to install elsewhere."
  fi
fi

mkdir -p "$GAMEDIR" "$ENGDIR"

# ------------------------------------------------------------------- downloads
fetch() {
  local url="$1" out="$2" sha="$3" name
  name="$(basename "$out")"
  if [ -f "$out" ]; then
    info "$name already downloaded"
  else
    info "downloading $name"
    curl -fL --progress-bar -o "$out.part" "$url" \
      || die "download failed: $url"
    mv "$out.part" "$out"
  fi
  if [ "$SKIP_VERIFY" = "1" ]; then
    warn "skipping checksum for $name"
    return
  fi
  local got
  got="$(shasum -a 256 "$out" | awk '{print $1}')"
  if [ "$got" != "$sha" ]; then
    rm -f "$out"
    die "checksum mismatch for $name
       expected $sha
       got      $got
       The file was deleted. Re-run to download again."
  fi
  ok "$name verified"
}

step "Fetching the Wine engine"
fetch "$ENGINE_URL"   "$ENGDIR/${ENGINE}.tar.xz"   "$ENGINE_SHA256"
fetch "$TEMPLATE_URL" "$ENGDIR/${TEMPLATE}.tar.xz" "$TEMPLATE_SHA256"

step "Unpacking"
if [ -d "$ENGDIR/$ENGINE" ]; then
  info "engine already unpacked"
else
  mkdir -p "$ENGDIR/$ENGINE"
  tar -xJf "$ENGDIR/${ENGINE}.tar.xz" -C "$ENGDIR/$ENGINE" || die "failed to unpack engine"
  ok "unpacked $ENGINE"
fi
if [ -d "$ENGDIR/Template" ]; then
  info "template already unpacked"
else
  mkdir -p "$ENGDIR/Template"
  tar -xJf "$ENGDIR/${TEMPLATE}.tar.xz" -C "$ENGDIR/Template" || die "failed to unpack template"
  ok "unpacked $TEMPLATE"
fi

WINE_BIN="$ENGDIR/$ENGINE/wswine.bundle/bin/wine"
[ -x "$WINE_BIN" ] || die "wine binary missing after unpack: $WINE_BIN"

TPL_CONTENTS="$ENGDIR/Template/${TEMPLATE}.app/Contents"
[ -d "$TPL_CONTENTS" ] || die "template Contents missing: $TPL_CONTENTS"

# ------------------------------------------------------------------- write env
step "Writing environment"
cat > "$GAMEDIR/env.sh" <<ENV
# Generated by setup.sh — Wine environment for $APP_NAME (32-bit, DX8).
export GAMEDIR="$GAMEDIR"
export ENGDIR="$ENGDIR"
export TPL="$TPL_CONTENTS"
export ENG="$ENGDIR/$ENGINE/wswine.bundle"

export WINEPREFIX="\$GAMEDIR/prefix"
export WINEARCH=win32
# d3d8=n,b lets a native d3d8.dll (the widescreen fix proxy) load ahead of Wine's.
export WINEDLLOVERRIDES="mscoree,mshtml=;d3d8=n,b"
export WINEDEBUG=\${WINEDEBUG:--all}

# x86_64 support libs (freetype, gnutls, SDL2, MoltenVK) from the template.
export DYLD_FALLBACK_LIBRARY_PATH="\$TPL/Frameworks:/usr/lib:/usr/local/lib"
export VK_ICD_FILENAMES="\$TPL/Resources/vulkan/icd.d/MoltenVK_icd.json"
export VK_DRIVER_FILES="\$VK_ICD_FILENAMES"

export WINE="\$ENG/bin/wine"
ENV
ok "env.sh"

# shellcheck source=/dev/null
source "$GAMEDIR/env.sh"

# --------------------------------------------------------------- create prefix
step "Creating the Wine prefix (first run takes a minute)"
mkdir -p "$WINEPREFIX"
WINEDEBUG=-all "$WINE" wineboot --init >/dev/null 2>&1 || true
# wineboot returns before the prefix is finished; wait for the registry to land.
for _ in $(seq 1 90); do
  [ -f "$WINEPREFIX/system.reg" ] && [ -d "$WINEPREFIX/drive_c/windows/system32" ] && break
  sleep 1
done
[ -f "$WINEPREFIX/system.reg" ] || die "prefix creation failed (no system.reg)"
WINEDEBUG=-all "$ENG/bin/wineserver" -w 2>/dev/null || true
ok "prefix ready at $WINEPREFIX"

# ------------------------------------------------------------------ copy game
step "Installing game files"
DEST="$WINEPREFIX/drive_c/Games/HitmanContracts"
mkdir -p "$DEST"
# -a keeps timestamps; trailing /. copies contents, not the directory itself.
cp -a "$GAME_SRC/." "$DEST/" || die "copying game files failed"
ok "copied to C:\\Games\\HitmanContracts (${SRC_MB} MB)"

# ------------------------------------------------------------- widescreen fix
if [ -n "$WSFIX_SRC" ]; then
  step "Installing widescreen fix"
  [ -d "$WSFIX_SRC" ] || die "--widescreen-dir is not a directory: $WSFIX_SRC"
  missing=""
  for f in d3d8.dll h3w.dll h3.ini; do
    [ -f "$WSFIX_SRC/$f" ] || missing="$missing $f"
  done
  [ -z "$missing" ] || die "widescreen dir is missing:$missing"
  cp -a "$WSFIX_SRC/d3d8.dll" "$WSFIX_SRC/h3w.dll" "$WSFIX_SRC/h3.ini" "$DEST/"
  # The fix reads h3.ini from the game root and from scripts/ depending on build.
  mkdir -p "$DEST/scripts"
  cp -a "$WSFIX_SRC/h3.ini" "$DEST/scripts/h3.ini"
  ok "widescreen fix files installed"
else
  info "no --widescreen-dir given; skipping widescreen fix (see README)"
fi

# Sync the widescreen fix to --resolution. Done unconditionally, because the fix may
# already be present in the copied game files rather than coming from --widescreen-dir;
# if h3.ini disagrees with HitmanContracts.ini the game can fail to start.
if [ -f "$DEST/h3.ini" ]; then
  w="${RESOLUTION%x*}"; h="${RESOLUTION#*x}"
  for ini in "$DEST/h3.ini" "$DEST/scripts/h3.ini"; do
    [ -f "$ini" ] || continue
    awk -v w="$w" -v h="$h" '
      /^[[:space:]]*Width[[:space:]]*=/  { print "Width = " w;  next }
      /^[[:space:]]*Height[[:space:]]*=/ { print "Height = " h; next }
      { print }' "$ini" > "$ini.tmp" && mv "$ini.tmp" "$ini"
  done
  ok "widescreen fix set to ${RESOLUTION}"
fi

# --------------------------------------------------------------- patch the ini
# Keys in this ini are space-separated ("Resolution 1920x1080"), not key=value.
ini_set() {
  local key="$1" val="$2" file="$3"
  if awk -v k="$key" '$1==k{found=1} END{exit !found}' "$file"; then
    awk -v k="$key" -v v="$val" '$1==k{print k" "v; next} {print}' "$file" \
      > "$file.tmp" && mv "$file.tmp" "$file"
  else
    printf '%s %s\n' "$key" "$val" >> "$file"
  fi
}

step "Applying the input and resolution fixes"
INI="$DEST/HitmanContracts.ini"
[ -f "$INI" ] || die "HitmanContracts.ini not found in the copied game files"
cp -a "$INI" "$INI.orig"

# THE mouse fix. Contracts drives input through DirectInput8; with these keys unset
# its fallback path never sees mouse button state under Wine, so look works but
# clicks do nothing. They must be 1 (enable DirectInput), not 0.
ini_set UseDirectInputMouse    1 "$INI"
ini_set UseDirectInputKeyboard 1 "$INI"
ini_set Resolution "$RESOLUTION" "$INI"
ok "UseDirectInputMouse 1 / UseDirectInputKeyboard 1 / Resolution $RESOLUTION"

# The game reads its control rebinds from this file and does not recreate it if you
# delete it, so make sure a valid one exists. An empty Controls block is fine.
CFG="$DEST/HitmanContracts.cfg"
if [ -f "$CFG" ]; then
  ok "HitmanContracts.cfg present"
else
  printf '<Settings>\n<Controls>\n</Controls>\n</Settings>\n' > "$CFG"
  ok "created required HitmanContracts.cfg"
fi

# ------------------------------------------------------------- install launcher
step "Installing the launcher"
if [ -f "$SELF_DIR/play.sh" ]; then
  cp -a "$SELF_DIR/play.sh" "$GAMEDIR/play.sh"
  chmod +x "$GAMEDIR/play.sh"
  ok "$GAMEDIR/play.sh"
else
  warn "play.sh not found next to setup.sh; launcher not installed"
fi

printf '\n%sDone.%s Launch the game with:\n\n    %s%s/play.sh%s\n\n' \
  "$c_grn$c_bold" "$c_reset" "$c_bold" "$GAMEDIR" "$c_reset"
printf 'Windowed instead:\n\n    %s/play.sh --windowed 1600x900\n\n' "$GAMEDIR"
