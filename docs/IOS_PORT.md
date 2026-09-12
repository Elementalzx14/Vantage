# Vantage iOS emulators

This branch adds a native iOS libretro host and builds four emulator cores from
pinned source revisions. The earlier iOS preview has been confirmed by the tester
to open and display the game library. Native playback needs physical iPhone testing.

| Console | Bundled core | First test formats |
| --- | --- | --- |
| NES | FCEUmm | .nes |
| SNES | Snes9x | .sfc, .smc |
| Game Boy / Game Boy Color | Gambatte | .gb, .gbc |
| Game Boy Advance | mGBA | .gba |

Use uncompressed ROMs for this first emulator build. Other consoles are not yet
available. Support for all JellyEmu games remains a long-term target, not a claim
made by this build. BIOS-dependent games and cross-core cloud states need separate
verification. No games or BIOS files are bundled with the app.

## Install and test

1. Download the latest successful `Vantage-iOS-unsigned-<number>` artifact from
   Actions and extract `Vantage-unsigned.ipa` from the outer ZIP.
2. Upload the IPA to Signulous. Sign all embedded frameworks with the app and
   retain the same bundle identifier to preserve the app's existing data.
3. Open Vantage and visit Cores. All four should show **Included in this app**.
   License information is available from each core's info button.
4. Start a game from one of the listed systems. Check video and sound, then hold
   a direction while pressing A or B. Test both portrait and landscape layouts.
5. Use the floating game menu to save state, exit the game, reopen it and load.
   Test the game's own battery save separately, including after closing the app.
6. Background and reopen the app; check pause/resume and audio. If available,
   connect a Bluetooth controller and test controls. Home opens the game menu;
   Menu and Options map to Start and Select.

Server addresses and credentials are entered in the installed app, never embedded
in source or workflows. Use HTTPS remotely. Local-network HTTP is enabled by the
iOS project. Keep private server details, tokens and game lists out of public issues.

## Implementation

- `packages/vantage_emulator` registers the existing emulator method channel only
  on iOS. `CoreHost.hpp` owns the libretro lifecycle, input, software pixel formats,
  state serialization and battery/RTC files. Calls run on one serial queue.
- The iOS bridge publishes BGRA Flutter textures, sends PCM through AVAudioEngine,
  and handles audio interruptions, volume, pause/resume and playback speed.
- iPhone multitouch controls send standard libretro button IDs. Apple controller
  key names are mapped separately from Android and Windows defaults.
- Cores are bundled as frameworks. The app validates core paths against its own
  bundle and never downloads executable cores. Unsupported consoles are rejected
  before a ROM is downloaded.
- iOS ROM downloads use the session token and a partial file, renamed only after
  completion. SRAM/RTC is written beside the cached ROM on pause, stop and periodically.
- The native Android/Windows projects and release workflow are unchanged. Existing
  dependency versions are retained; the only new dependency is the local iOS plugin.

## Reproduce the build

Use Flutter **3.38.5** / Dart **3.10.4** and the committed lockfile. From this PC,
`tool/flutter-local.ps1` uses the project-local SDK without changing system PATH.
Windows desktop plugin setup requires symlink support; after dependencies resolve,
local tests can run with `./tool/flutter-local.ps1 test --no-pub`.

The macOS workflow runs:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
python3 tool/build_ios_cores.py
bash tool/test_native_core.sh
flutter build ios --release --no-codesign --no-pub
bash tool/package_unsigned_ios.sh
```

`tool/ios_cores.json` pins source identities. The build provides corresponding core
source archives, original licenses, and the host source/build scripts in a second
artifact. Keep these with binary distributions and preserve each core's license.
The native smoke test builds FCEUmm for the Mac host and uses an original generated
NES homebrew program to exercise real video, audio callbacks, button input, state
save/load, battery files, reset and reload. It does not substitute for iPhone testing.

Remaining work includes more cores, archive handling, BIOS management, additional
input devices, hardware rendering for demanding consoles, save compatibility, and
physical-device performance and stability. Adding a console requires an iOS-capable
core and testing; recognizing a JellyEmu platform tag alone does not make it playable.
