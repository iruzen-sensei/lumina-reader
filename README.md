# Lumina Reader

A premium, offline-first **all-in-one reading & streaming app** for Android — manga, novels, e-books (EPUB / PDF / CBZ / CBR) and anime — built as a fork-inspired project of Mangayomi (Apache 2.0), with anime features inspired by Aniyomi.

> **Status: engineering remediation complete — verified against the real
> toolchain.** This tree went through a full professional remediation pass
> (see `PROJECT_DOCUMENTATION.md`): the mock-data skeleton was replaced by a
> real Isar-backed data layer, all seed/fake content was removed, and a native
> MangaDex source delivers real content out of the box.
>
> **Quality gates (all green, Flutter 3.47 / Dart 3.13):**
> - `flutter pub get` — resolves cleanly
> - `dart run build_runner build --delete-conflicting-outputs` — 587 outputs, zero errors
> - `flutter analyze` — **No issues found** (0 errors / 0 warnings / 0 infos, strict mode)
> - `flutter test` — compile smoke test passes: the entire library graph
>   compiles under the real Dart kernel compiler, not just the analyzer
> - `scripts/audit.py` — 0 blockers
>
> **Vendored forks** (`third_party/`, excluded from host analysis, each
> documented in `pubspec.yaml`):
> - `pdfrx_engine` 0.4.5 — two `!` null-safety fixes (`pdf_file_cache.dart`);
>   upstream fails to kernel-compile under Dart 3.13
> - `epubx` 4.0.0 — `Uint8List` adapter for `image` 4.x (forced by media_kit)
>
> `dependency_overrides` also pins `html: 0.15.6` (0.15.7 removed an API
> flutter_html needs) and `image: ^4.0.17` (epubx/media_kit conflict).

## What works in this build

| Area | Status |
|------|--------|
| Library (manga / novels / books) | ✅ Isar-persisted, reactive (watch streams) |
| Browse — MangaDex | ✅ Real API v5: popular, latest, global search |
| Manga reader | ✅ 3 modes (paged / continuous / webtoon), real page URLs, progress persisted |
| Detail screens | ✅ Real chapter lists, favorite toggles persisted |
| EPUB / PDF readers | ✅ Real implementations (epubx / pdfrx), file import → library → reader |
| History | ✅ Persisted, resume deep-links use real chapter ids |
| Notes (7-color highlights) | ✅ Isar-persisted, spec-aligned color semantics |
| Stats (heatmap, streaks, goals) | ✅ Derived from real reading sessions |
| Settings | ✅ All UI settings persisted to the single-row Settings collection |
| Downloads | ◐ Queue state persisted; transfer engine components present (`isolate_pool`, `m_downloader`) but not yet wired to the queue — next milestone |
| Anime player | ◐ media_kit player works; **no anime sources yet**, so streams resolve empty (honest empty state) |
| Updates feed | ◐ `LibraryUpdater` implemented (30-min checker) but not auto-started |
| Cloud sync / trackers | ◐ Services compile (Firestore, MAL/AniList/Kitsu/Shikimori) but are not wired to UI |
| JS/Dart interpreter extensions | 🅿️ Compile; routing parked as experimental — native sources are the supported path |

## Architecture

```
screens (modules/) → providers (providers.dart) → repositories (data/)
                                                      ↘ Isar (models/)
   extension content: ExtensionCoordinator → getExtensionService()
                        ├─ native: MangaDexSource (pure Dart, API v5)
                        └─ experimental: QuickJS / d4rt interpreters
```

- **Single source of truth**: the Isar collections in `lib/models/*.dart`.
- **Presentation DTOs**: `lib/models/models.dart` + `mappers.dart` (the only
  file allowed to touch both model systems).
- **Audit gate**: `python3 tool/audit.py` — run in CI before every build;
  fails the build on schema-registration gaps, import-order errors, duplicate
  symbols, phantom APIs, mock-data regressions.

## Building

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Isar + Riverpod + JSON codegen
flutter analyze                                            # must be clean
flutter build apk --release
```

Requirements: Flutter stable (3.35+), Java 17, Android SDK 35. Signing: set
`KEY_ALIAS` / `KEYSTORE_PATH` / `KEY_PASSWORD` / `KEYSTORE_PASSWORD` env vars
(or edit `android/app/build.gradle.kts`).

## License

Apache License 2.0 — inherited from Mangayomi
(https://github.com/kodjodevf/mangayomi). See `LICENSE` and `NOTICE`.
