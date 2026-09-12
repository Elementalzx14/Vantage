# Vantage iOS port

## Current milestone

This branch adds an unsigned iOS **library-browsing preview**. It is not yet a
playable emulator. The intended final scope is the user's entire JellyEmu library;
console coverage must be assessed against the actual library and iPhone.

The app has an iOS project, app links (`vantage://launch?itemId=...`), a local-network
permission description, and local-network HTTP allowance. Use HTTPS for remote
servers. Server login, Keychain persistence, network access and layouts still need
verification on a signed physical iPhone build.

Server addresses and credentials are entered by each user in the installed app.
They must never be embedded in source, workflows, tests, screenshots or commits.
Compatibility planning can use console names without publishing a user's library.

Playback and core management show a clear preview message on iOS. Game launch
returns before ROM download. iOS no longer identifies as Linux or downloads
Android/desktop cores. The native Android and Windows projects and their release
workflow are unchanged.

## Build from Windows

The development SDK is Flutter **3.38.5**, with Dart 3.10.4. Dependencies remain
locked to the upstream `pubspec.lock`. The declared older minimum Flutter version
in upstream `pubspec.yaml` is not sufficient for the locked dependencies.

1. Work in this repository on `ios-port`.
2. Use `tool/flutter-local.ps1` for the project-local Flutter SDK on this PC.
   Example: `./tool/flutter-local.ps1 test --no-pub`.
3. Commit and push to your fork's `ios-port` branch. The iOS workflow starts on
   changes to app, iOS, tests, dependencies or build files.
4. Open the fork's Actions page and select **Build unsigned iOS preview**.
5. When the run passes, download `Vantage-iOS-unsigned-<run number>` and extract
   the outer GitHub artifact ZIP. Inside is `Vantage-unsigned.ipa` and its SHA-256.
6. Upload the **IPA**, not the outer ZIP, to Signulous. Sign it for your registered
   iPhone and install using Signulous's instructions.

The workflow runs on `macos-15`, executes analysis and tests, then builds release
device code with `flutter build ios --release --no-codesign`. Packaging checks the
arm64 executable and Flutter frameworks, creates `Payload/Runner.app`, validates
the ZIP and uploads the artifact for 14 days. No Apple or Signulous credentials
are required for this unsigned build. Signing and device installation are separate
steps; a successful compile does not prove either one works.

For a manual macOS build:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
flutter build ios --release --no-codesign --no-pub
bash tool/package_unsigned_ios.sh
```

The Windows SDK is stored in this task's `work/flutter`, and its package cache in
`work/pub-cache`. The wrapper uses these without changing system PATH. Windows
desktop plugin setup requires symlink support (usually Windows Developer Mode).
The iOS build itself runs on GitHub's Mac. Local tests can use `--no-pub` after
dependency resolution even if Windows plugin symlink creation fails.

## Remaining emulator work

- Inventory the library's actual console tags and identify the iPhone/iOS version.
- Implement an iOS native backend for Vantage's emulator method channel, video
  surface, audio, input, lifecycle pause/resume, SRAM and save states.
- Build and bundle appropriate arm64 iOS cores with their licenses. The existing
  Android `.so` and Windows `.dll` binaries cannot run on iOS. Dynamically downloaded
  desktop cores are not a viable replacement for signed iOS code.
- Validate touch controls and controllers. Existing on-screen controls contain
  Android key codes and require an explicit iOS input mapping.
- Evaluate demanding systems separately, including graphics APIs and JIT needs.
  Do not claim all games work merely because the IPA installs.
- Test each supported core using legally supplied games or homebrew, then test
  server downloads, launch links, save synchronization, rotation and app suspension
  on the actual signed iPhone build.

## References

- [Flutter iOS builds](https://docs.flutter.dev/deployment/ios)
- [GitHub artifact downloads](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)
- [Signulous custom app signing](https://www.signulous.com/)
