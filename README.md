# Hitman: Contracts on macOS

Scripted setup that runs **Hitman: Contracts** (2004) on modern macOS, including Apple
Silicon, through a purpose-built 32-bit Wine prefix.

No Whisky, CrossOver, or Porting Kit needed — `setup.sh` builds and configures the
prefix itself, applies the fixes the game needs under Wine, and installs a launcher.

> **You need to already own the game.** Nothing here downloads game content. You point
> `setup.sh` at your own copy of the Windows files.

---

## Why this exists

Getting Contracts running on a Mac has three non-obvious failure modes. All three are
handled automatically:

| Symptom | Cause | Fix applied |
| --- | --- | --- |
| Mouse look works, **clicks do nothing** | The game drives input through DirectInput8. With `UseDirectInputMouse` unset, its fallback path never receives mouse button state under Wine. | `UseDirectInputMouse 1` and `UseDirectInputKeyboard 1` added to `HitmanContracts.ini`. Must be `1`, not `0`. |
| Mouse/keyboard rebinds don't stick | `HitmanContracts.cfg` holds the bindings and the game does **not** recreate it if deleted. | A minimal valid `.cfg` is written if absent. |
| Game won't start when a widescreen fix is installed | `h3.ini` and `HitmanContracts.ini` disagree on resolution. | Both are written to the same `--resolution`. |
| Game won't start as 32-bit at all | Contracts is a 32-bit DX8 binary; most current Wine builds dropped 32-bit support on macOS. | Uses the `WineCX32Bit` (`wine32on64`) engine, which still runs 32-bit code. |

## Requirements

- macOS (tested on macOS 26 / Darwin 25.x)
- Apple Silicon or Intel. On Apple Silicon you need Rosetta 2:
  ```sh
  softwareupdate --install-rosetta
  ```
- ~2 GB free disk space (≈860 MB game + ≈900 MB engine and prefix)
- Your own copy of the game's Windows files

## 1. Get your game files

If you own Contracts on Steam but are on a Mac, the store page won't install it (it's a
Windows-only title). Use `steamcmd` to download the Windows depot with your own account:

```sh
brew install --cask steamcmd

steamcmd \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir "$HOME/Downloads/HitmanContracts" \
  +login YOUR_STEAM_USERNAME \
  +app_update 247430 validate \
  +quit
```

`247430` is the Steam appid for Hitman: Contracts. You'll be prompted for your password
and Steam Guard code. A complete download is ~860 MB and must contain
`HitmanContracts.exe`.

Copying the folder from an existing Windows installation works equally well.

## 2. Run setup

```sh
git clone https://github.com/YOUR_USERNAME/hitman-contracts-mac.git
cd hitman-contracts-mac
./setup.sh --game-dir "$HOME/Downloads/HitmanContracts"
```

Options:

```
--game-dir <path>       Your Windows copy of the game (must hold HitmanContracts.exe)
--resolution <WxH>      Render resolution. Default: 1920x1080
--widescreen-dir <p>    Install a widescreen fix from this directory (see below)
--install-root <path>   Where the prefix and engine live. Default: ~/Games
--force                 Rebuild over an existing prefix
--skip-verify           Skip SHA-256 checks on downloads (not recommended)
```

## 3. Play

```sh
~/Games/HitmanContracts/play.sh                     # fullscreen
~/Games/HitmanContracts/play.sh --windowed          # 1280x720 window
~/Games/HitmanContracts/play.sh --windowed 1600x900 # custom size
```

## Widescreen fix (optional)

A third-party widescreen patch exists for Contracts. It isn't bundled here, since its
redistribution terms are unclear. Download it yourself — the
[PCGamingWiki community file](https://community.pcgamingwiki.com/files/file/2789-hitman-contracts-widescreen-fix/)
is one source — then point setup at the folder containing `d3d8.dll`, `h3w.dll` and
`h3.ini`:

```sh
./setup.sh --game-dir ~/Downloads/HitmanContracts --widescreen-dir ~/Downloads/hc-widescreen
```

Setup copies those files in, rewrites `h3.ini` to your chosen resolution, and relies on
the `d3d8=n,b` override already set in `env.sh` so the fix's proxy DLL loads ahead of
Wine's own `d3d8`.

## Layout

After setup:

```
~/Games/
├── .engines/
│   ├── WS11WineCX32Bit21.2.0/   wine32on64 engine
│   └── Template/                x86_64 support libs (freetype, SDL2, MoltenVK)
└── HitmanContracts/
    ├── env.sh                   generated environment
    ├── play.sh                  launcher
    └── prefix/                  the Wine prefix
        └── drive_c/Games/HitmanContracts/
```

## Troubleshooting

**Clicks still don't register.** Confirm the fix actually landed:

```sh
grep UseDirectInput ~/Games/HitmanContracts/prefix/drive_c/Games/HitmanContracts/HitmanContracts.ini
```

Expect `UseDirectInputMouse 1` and `UseDirectInputKeyboard 1`. The value must be `1`.

**Game exits a few seconds after starting.** If you launched it from a script, a
background shell, or anything that doesn't give the window focus, the game reaches its
main menu and then quits on its own after roughly 15-30 seconds. This is expected and is
not a configuration problem — run `play.sh` from a normal terminal and click into the
window. If it also exits while focused, check that `h3.ini` (if you installed the
widescreen fix) and `HitmanContracts.ini` agree on resolution:

```sh
cd ~/Games/HitmanContracts/prefix/drive_c/Games/HitmanContracts
grep ^Resolution HitmanContracts.ini; grep -iE 'Width|Height' h3.ini 2>/dev/null
```

**See what Wine is doing.** The launcher silences Wine by default:

```sh
WINEDEBUG=+loaddll ~/Games/HitmanContracts/play.sh 2>&1 | tee /tmp/hitman.log
```

`fixme:d3d_shader:print_glsl_info_log` warnings are normal and harmless.

**Mouse feels wrong in windowed mode.** Match the window size to the render resolution,
or play fullscreen — a mismatch between the two makes cursor position scale oddly:

```sh
./setup.sh --game-dir <path> --resolution 1280x720 --force
~/Games/HitmanContracts/play.sh --windowed 1280x720
```

**Start over.** The prefix is disposable:

```sh
rm -rf ~/Games/HitmanContracts
./setup.sh --game-dir <path>
```

## Notes

- `HitmanContracts.ini` lists `DrawDll RenderD3D.dll` and `SoundDll SoundEngine.dll`.
  In the 2013 Steam build (build 175) those DLLs aren't shipped and are never loaded —
  rendering goes through Wine's `wined3d`. Their absence is not a problem.
- Your original `HitmanContracts.ini` is preserved as `HitmanContracts.ini.orig` inside
  the prefix before any edits.
- Engine downloads are checksum-verified against pinned SHA-256 values in `setup.sh`.

## Credits

- [Sikarugir-App](https://github.com/Sikarugir-App) — the Wine engines and support
  template this builds on, successors to Wineskin.
- The DirectInput mouse fix is long-documented by the community, including on the
  [Steam forums](https://steamcommunity.com/app/247430/discussions/0/541907867758944232/),
  the [WineHQ forums](https://forum.winehq.org/viewtopic.php?t=8499), and
  [CodeWeavers](https://www.codeweavers.com/compatibility/crossover/tips/hitman-contracts/mouse-fix).

## Legal

These are scripts and configuration only. They contain no game code, assets, or
third-party binaries. Hitman: Contracts is © IO Interactive. Use your own legally
obtained copy.
