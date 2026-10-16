# AGENTS.md

## Project overview

- Flutter Android app: an in-app Chromium browser (`flutter_inappwebview`) with best-effort video URL detection (network interception + fetch/XHR hook + DOM scan) and one-tap download to the Android Downloads directory (MediaStore via platform channel).
- MVP scope: any http(s) link accepted with auto-open+detect; direct mp4/webm/mov/m4v + unencrypted HLS VOD supported; encrypted/DRM/live explicitly rejected with message; Facebook/YouTube best-effort via sniffed progressive/HLS; no extractor backend; no ffmpeg in MVP. iOS is out of scope.
- Primary users: Android users saving public direct-link videos. Main features: `BrowserPage` (address bar, WebView, video picker bottom-sheet, download FAB/progress), manual "paste URL" fallback, background HEAD enrichment (size), quality/title labels, and `ACTION_SEND` share-intent receiving (cold start + hot resume).

## Tech stack

- Language: Dart (SDK constraint `^3.13.5`; verified `3.13.5`); UI: Flutter (verified `3.47.7`, stable).
- Key packages (`pubspec.yaml`): `flutter_inappwebview ^6.1.5`, `dio ^5.7.0`, `path_provider ^2.1.4`, `permission_handler ^11.3.1`, `receive_sharing_intent ^1.8.0`, `cupertino_icons ^1.0.8`; dev: `flutter_test`, `flutter_lints ^6.0.0`.
- Version-sensitive: `dependency_overrides: path_provider_android: 2.2.15` — do not bump without testing. Android: app `compileSdk 36`, `targetSdk 34`, Java/Kotlin JVM 17 (`android/app/build.gradle.kts`); SDK platform `android-36` must be installed (see build workaround below). HTTPS-only (no cleartext override).
- Package manager: `flutter pub` (pub.dev). No backend/database. Native bridge: Kotlin `MediaStoreHelper.kt` + `MainActivity.kt` (`MethodChannel "com.example.downloader/mediastore"`). No CI config in repo (see TODO).

## Repository structure

- `lib/main.dart` — composition root only: constructs concrete infrastructure, injects abstractions into `VideoDownloaderApp`/`BrowserPage`. `VideoDownloaderApp.detector` must stay typed as `IVideoDetector`, never concrete.
- `lib/domain/` — pure Dart, zero Flutter/infrastructure imports. Entities (`download_request.dart`), pure helpers (`video_url_matcher.dart`), interfaces (`i_video_detector.dart`, `i_file_downloader.dart`, `i_storage_gateway.dart`, `i_receive_share_gateway.dart`), use cases (`detect_video_use_case.dart`, `download_video_use_case.dart`). Agents: prefer working here for business rules.
- `lib/infrastructure/` — implements domain interfaces: `webview_video_sniffer.dart` (detection, `fetchHookJs`/`videoScanJs`, HEAD enrichment), `dio_download_service.dart`, `media_store_gateway.dart`, `webview_cookie_bridge.dart`, `receive_share_gateway.dart`.
- `lib/presentation/` — `browser_page.dart` + `widgets/` (`address_bar.dart`, `animated_download_fab.dart`, `download_progress_bar.dart`, `manual_url_dialog.dart`, `video_picker_tile.dart`). Depends only on domain abstractions.
- `android/app/src/main/` — `AndroidManifest.xml` (INTERNET, `ACTION_SEND` text/plain intent-filter), `kotlin/.../MainActivity.kt`, `MediaStoreHelper.kt`. `test/widget_test.dart` — only test file. Docs: `pr_plan.md`. `setup_android_minimal.ps1` — Windows Android SDK/JDK bootstrap.

## Setup and commands

Prerequisites (Windows, per `setup_android_minimal.ps1`): JDK 17 (`JAVA_HOME=C:\Android\jdk-17`), Android SDK (`ANDROID_HOME`/`ANDROID_SDK_ROOT=C:\Android\Sdk`, platform-tools + build-tools 34 + `platforms;android-34`), Flutter on PATH. Additionally install `platforms;android-36` (required by the build workaround below):

```powershell
flutter pub get
```

Local development (device or emulator must be attached):

```powershell
flutter run
flutter run -v        # verbose
flutter run --release # release signing currently uses debug keys (see build.gradle.kts)
```

Static analysis, format check, tests (all verified working):

```powershell
flutter analyze
dart format --output=none --set-exit-if-changed lib test  # note: currently reports diffs; do not reformat unrelated files without approval
flutter test
flutter test -v                      # verbose per-test output
flutter test test/widget_test.dart   # single file
```

Build:

```powershell
flutter build apk --split-per-abi   # preferred: always use this; emits smaller per-ABI APKs
flutter build apk --release         # single universal APK (larger)
```

Build workaround (do not remove): `receive_sharing_intent` declares `compileSdk 37`, but Google only publishes a broken `37.0` platform package AGP can't resolve, so `android/app/build.gradle.kts` pins that module to `compileSdk 36` (safe: the plugin uses no API above 33) and the app compiles against 36 (`targetSdk` stays 34). `android/gradle.properties` sets `kotlin.incremental=false` because the Kotlin 2.x incremental compiler crashes when the project (e.g. `D:`) and pub-cache (e.g. `C:`) are on different drives. If the build fails after SDK updates, run `flutter clean`, kill stale `GradleDaemon`/`KotlinCompileDaemon` processes, and retry.

Environment variables: none required by the app (no `.env`, no `--dart-define`). Only the Android toolchain vars above (`JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`).

## Coding conventions

- Authoritative configs: `analysis_options.yaml` (`include: package:flutter_lints/flutter.yaml`; excludes `build/`, `android/`, `web/`) and `dart format` defaults. No custom lint overrides — do not add any without approval.
- Architecture (Clean Architecture): dependency rule **Presentation → Domain ← Infrastructure**. Domain defines interfaces; infrastructure implements them; presentation calls use cases/abstractions only. Never import `lib/infrastructure/*` from `lib/domain/*`; never type a widget field with a concrete infrastructure class.
- Imports: package imports across layers (`package:downloader/domain/...`); relative imports within the same directory (e.g. `import 'download_request.dart';` in `lib/domain/`). Keep existing order: dart → flutter → package → relative.
- Style observed: `///` doc comments on all public types/members, `final` fields, `const` constructors where possible, single quotes, trailing commas, `lowerCamelCase` members, `UpperCamelCase` types. Match it.
- Error handling: detection/enrichment is best-effort — infrastructure swallows expected failures with `catch (_) {}` and never throws to the UI; downloads surface errors via `onError` callbacks → `SnackBar` with Retry; temp files cleaned up on failure. Use `unawaited()` for fire-and-forget futures. Do not add `print`/debug logging; no logger package in use.
- Dart/JS boundary: `videoScanJs` quality regex intentionally mirrors `qualityLabelFromUrl` (documented in code). JS emits `{url, title, ql, tSrc}`; `tSrc` provenance (`video-attr`/`anchor` = specific, `doc` = generic) drives title-upgrade rules — keep all three layers (JS → `browser_page.dart` → sniffer) in sync.

## Testing requirements

- Runner: `flutter test` (i.e. `package:flutter_test`). Location: `test/`; current file: `test/widget_test.dart`; naming: `*_test.dart`.
- What to test: `VideoUrlMatcher` pure cases (extension before query, case-insensitive path, blob/data rejection, false-positive blocklist, dedup normalization, filename suggestion), `DownloadRequest` invariants (original URL preserved exactly), sniffer dedup/merge behavior, `DetectVideoUseCase` filtering, `ReceiveShareGateway.extractFirstUrl` (bare URL, `"Title https://..."`, trailing punctuation, no-URL → null), title generic→specific upgrade and no-downgrade.
- Mocks/fakes: construct `WebViewVideoSniffer()` directly (optionally `dio:` injection); no mockito/mocktail in repo — hand-rolled fakes over new test dependencies.
- Gate: `flutter analyze` clean + `flutter test` all-pass before a change is complete. Coverage: no threshold configured (see TODO). New/updated tests are required for every behavior change and bug fix.

## Git and PR workflow

- Branches: `main` + `feature/<short-slug>` (observed: `feature/video-metadata-and-share-intent`). Branch from and target `main` unless told otherwise.
- Commits: Conventional Commits style as observed (`feat: ...`, `fix: ...`). Keep messages imperative, scope to the diff; do not amend pushed commits.
- PRs: title mirrors the head commit summary; description links the task/spec and lists verification (`flutter analyze`, `flutter test`). No PR template, signed commits, or labels observed — follow maintainer direction when opening.
- Required checks: no CI in repo (see TODO) — locally run analyze + tests and paste results into the PR. Stage only intended files (`git status`/`git diff` first); never commit `build/`, `.dart_tool/`, or IDE output.

## Safety and boundaries

- Do not modify without explicit approval: `android/` manifest intent-filters/permissions, Kotlin platform channel (`MainActivity.kt`, `MediaStoreHelper.kt`), `pubspec.yaml`/`pubspec.lock` versions and `dependency_overrides`, `analysis_options.yaml` lint set, `android/app/build.gradle.kts` SDK/Java levels.
- Ask first before: installing/adding any dependency, changing a public API or domain interface signature, altering storage/download paths or WebView security settings (`InAppWebViewSettings`), touching CI/CD, or generating migrations (none currently exist).
- Never commit secrets, credentials, tokens, or private keys. None exist in the repo; keep it that way. Do not add `.env` files or hardcode keys/URLs with auth material.
- Generated/ignored: `build/`, `.dart_tool/`, `.flutter-plugins-dependencies`, `/android/app/{debug,profile,release}`, `coverage/` — never stage these.

## Common tasks

Adding a feature (example: new picker metadata):

1. Add pure logic + interface change in `lib/domain/` first.
2. Implement in `lib/infrastructure/`, consume via use case in `lib/presentation/`.
3. Update `test/widget_test.dart` (or new `test/*_test.dart`) with positive/negative cases.
4. Run `flutter analyze` and `flutter test`; update `AGENTS.md` if architecture/scope changed.

Fixing a bug:

1. Reproduce with a failing test in `test/` before editing.
2. Fix at the correct layer (domain rule vs infrastructure adapter vs presentation wiring).
3. Re-run `flutter test` + `flutter analyze`; confirm the new test passes and nothing regressed.

Adding tests:

```powershell
flutter test test/widget_test.dart
flutter test -v
```

- Group by class/method (`group('VideoUrlMatcher.isVideoUrl', ...)`), one behavior per `test(...)`, use `expect(..., isTrue/isFalse/equals(...))`.

Updating documentation:

- Small scope change → edit the relevant section of `AGENTS.md`. Do not create new top-level docs unless asked; keep README changes minimal (it is still the default Flutter stub).

Refactoring safely:

- Keep public signatures stable; prefer sidecar state (e.g. `_titleIsGeneric`) over entity changes. After each step run `flutter analyze`; finish with full `flutter test`.

Debugging failures:

1. `flutter analyze` for static errors; `flutter test -v` for the failing case.
2. Detection issues: check `shouldInterceptRequest`/`onLoadResource`/`videoHit`/`_runDomScan` wiring in `browser_page.dart`, then `handleUrl` merge rules in the sniffer. Share-intent issues: check manifest intent-filter + `extractFirstUrl` + `incomingUrls` subscription.

## Definition of done

- Code builds successfully.
- Lint, format, type-check, and tests pass.
- Documentation and relevant tests are updated.
- No secrets or unintended files are committed.
- Changes are minimal, focused, and consistent with existing patterns.

## TODO (genuinely unknown — do not guess)

- TODO: No CI/workflows found (no `.github/`); confirm required checks (analyze/test/build APK) and where they run.
- TODO: No coverage threshold or coverage tooling configured; confirm whether one is wanted.
- TODO: `README.md` is the default Flutter stub; confirm whether a real setup/usage section should be written.
- TODO: Release signing uses debug keys (`android/app/build.gradle.kts` TODO); confirm proper signing story before store release.
