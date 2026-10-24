# Validation record — Resonance 1.3.0

Updated 25 October 2026.

Executed on Linux with Python 3.12 and FFmpeg with the Chromaprint muxer:

- Backend suite: **63 tests passed**.
- Real audio fixtures generated in MP3, FLAC, M4A, Ogg Vorbis and Opus.
- All five formats: metadata, Unicode, plain/timed lyrics and cover embedding round-trip; artwork keep/remove; clear tags; unchanged source bytes and decoded PCM hash.
- Real local Chromaprint extraction through FFmpeg without an AcoustID key.
- API import/export/delete, authentication and invalid-input handling.
- AcoustID, MusicBrainz, LRCLIB and artwork response parsing through mocked HTTP services.
- Missing lyrics/artwork preserve existing content; lookup caching avoids duplicate requests; Retry-After throttles subsequent requests; missing MusicBrainz identification prevents a request.
- All Dart files were parsed and formatted successfully with the Dart formatter compiled to WebAssembly.

Additional checks executed for standalone Android and manual editing:

- Built the exact native TagLib 2.1.1 + Chromaprint 1.5.1 engine on Linux from the supplied source archives with CMake and GCC.
- Native engine passed manual-tag, Unicode (including emoji), plain/timed lyric and cover replacement round-trips for MP3, FLAC, M4A, Ogg Vorbis and Opus.
- Native artwork keep/remove and tag clearing passed for all five formats.
- Decoded audio PCM hashes stayed identical after editing and clearing; original fixture files stayed unchanged.
- Android-native exports were read by the Windows Python tag reader, and Windows exports were read by the native engine, including timed lyrics.
- The native Chromaprint fingerprint exactly matched FFmpeg's Chromaprint output for the same generated PCM.
- The JNI bridge passed C++ syntax/type checking against OpenJDK JNI headers.
- All four Kotlin source/test files and the native Gradle Kotlin script passed Tree-sitter syntax parsing. This is not a Kotlin compiler or Android API type check.
- Python backend regression suite: 16 passed after adding Android timed-lyric tag compatibility.

These are **host tests of the Android engine**, not proof that the APK has been built or exercised on a device.

AcoustID date hotfix:

- The identify API integration fixture now includes the reported `{"day":19,"month":7,"year":2017}` release date and verifies HTTP 200 with `date: "2017-07-19"`.
- Added date cases for full, year-only and year/month values; missing/null dates; zero/invalid components; leap days; and existing MusicBrainz date strings.
- Backend suite after the fix: 34 passed. The corresponding Android normalization and regression-test sources were parsed/formatted; Flutter tests remain unexecuted for the environment limitation below.

The test runner emitted a Starlette deprecation notice for its HTTPX test adapter. All tests passed.

Candidate availability update:

- Added 12 backend tests covering plain/timed lyrics, empty and instrumental lyrics, missing content, independent service errors, release-specific artwork, HEAD requests and redirects, cached checks, Retry-After cooldowns, and endpoint authentication/validation.
- Full backend regression suite: **46 passed**.
- Added Flutter widget/controller/direct-client tests for all badge states, background updates, stale response suppression, caching and Android availability checks. These sources passed parsing/formatting; Flutter tests and native app builds were not executed here.
- Availability integration used mocked service responses; live library coverage and on-device badge rendering were not verified.

Remembered connection, drop import and alternative-source update:

- Backend regression suite: **63 passed**, including 17 new cases for alternate artwork/lyric provider responses, artist filtering, duplicate album removal, album priority, Unicode/path escaping, partial provider failure, artwork normalization and size fallback, authentication and request validation, and rejection of untrusted image hosts/redirects.
- Added Flutter tests for OS-protected connection save/restore/forget, invalid saved configurations, dropped-file validation, alternate-source filtering/download behavior, and explicit preview/download choices.
- All Dart sources and tests passed parsing/formatting. The new Flutter tests, OS credential-store integration, native desktop drag events, real provider coverage and device save dialogs were not executed in this environment.
- Android’s new `normalizeCover` bridge reuses the existing bitmap normalization code. Kotlin syntax was checked; APK compilation and device behavior remain unverified.

Not executed in the preparation environment:

- Flutter analyzer/widget tests and native Windows/Android compilation: a Flutter 3.35.5 SDK was downloaded, but its Dart VM could not initialize in the execution sandbox (stack-bound discovery failed). Native Windows/Android toolchains were not available. The WebAssembly formatter check does not perform type analysis or replace Flutter tests.
- Device-level picker/save dialogs or real-device UI rendering.
- Android Kotlin compilation, on-device JNI loading, MediaCodec decoding and Storage Access Framework save dialogs. The package includes emulator instrumentation tests for JNI/local tag edits/fingerprints across all five formats and a CI job to run them, but those tests were not executed here.
- Flutter's new mocked standalone-engine tests (offline local calls, direct HTTPS lookups, lookup caching, native save dispatch and cooldown handling); the source parsed but the Dart VM limitation prevented execution.
- Live identification of a copyrighted song, authenticated AcoustID matching or public metadata/lyrics/art lookups. No application API key was provided. Service integrations were exercised with fixture responses.
- Container image build: Docker was not installed.

The included CI workflow and build instructions provide the native checks and artifacts when run in a suitable environment. Source availability is not evidence that those native builds have passed. Do not treat this package as a signed, store-ready binary release.
