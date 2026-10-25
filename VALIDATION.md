# Validation record — Resonance 1.6.0

Updated 25 October 2026.

This is the complete merged source. The delivered 1.6 batch overlay was applied successfully to the attached 1.5.0+7 archive after its real-source preflight passed. No overlay installer is needed to use this package.

Checks executed on the merged project:

- **93 tests passed**: 65 backend cases and 28 tools/native-helper cases, using Python 3.12 and the newly built native helper on Linux. The test adapter emitted a Starlette deprecation notice; there were no failures or skipped tests in the final run.
- Twelve download/bootstrap regression tests cover an expired TLS certificate followed by a verified mirror, certificate/hostname verification settings, failures on both mirrors, wrong checksums, local ZIP installation, invalid local ZIPs, valid and invalid caches, explicit CA loading, rollback of an installation failure, CLI option parsing/forwarding, preserving Dart sources when generating the runner, and concise bootstrap errors. HTTP responses are simulated; this is not a reproduction on the user's Windows certificate store or Python 3.15.
- Built `resonance_desktop` and `resonance_native_test` with CMake/GCC from the supplied pinned source archives.
- Native tagging and helper protocol checks passed for MP3, FLAC, M4A, Ogg Vorbis and Opus: Unicode, metadata, plain/timed lyrics, artwork replace/keep/remove and clearing. Original bytes and decoded PCM hashes were preserved. Native Chromaprint results matched host FFmpeg for the same PCM.
- All **33 Dart application/test files** in the merged project passed the WebAssembly formatter syntax check. Fifteen new Flutter cases cover queue order/deduplication, failure isolation, pause/cancel/skip/retry, overlap/limit rejection, interruption, persistence, preservation of edits and checkbox-scoped controls.
- The pinned checksum and official mirror relationship were checked against the publisher's public metadata. The 109 MB Windows archive was not downloaded/executed here. The downloader tests use fixture archives and mocked HTTPS responses.

Not executed:

- Dart/Flutter runtime tests or analyzer. A direct Dart smoke attempt still aborts with `Failed to retrieve stack bounds` before the isolate starts; the formatter check is not a type check.
- Native Windows/Android app compilation, Windows save/credential dialogs, Windows Python 3.15 bootstrap execution, device lifecycle recovery or device rendering of batch controls. The source includes CI for these environments, but no remote workflow was triggered.
- Live fingerprint recognition against AcoustID with an application key.

The bootstrap certificate fix uses verified alternate sources and a checksum-validated local-archive option. It does not disable TLS verification or modify the machine's certificate store. A machine clock or network certificate issue affecting both mirrors can still require the documented local ZIP or trusted-CA option.

Earlier validation records follow for context; their version-specific limitations describe those preparation runs.

---

# Validation record — Resonance 1.5.0

Updated 25 October 2026.

Standalone Windows update:

- Built the new portable `resonance_desktop` helper with GCC/CMake on Linux using the supplied pinned TagLib/Chromaprint archives.
- Combined backend, tool-preparation and desktop-helper suite: **79 passed** (63 backend, 3 close-hook installer, 6 decoder/build-rule preparation, 7 desktop helper).
- The new helper round-tripped Unicode/quotes/newlines, tags, plain/timed lyrics and artwork replace/keep/remove in MP3, FLAC, M4A, Ogg Vorbis and Opus. Original bytes and decoded audio hashes remained unchanged. Its fingerprint matched the host FFmpeg Chromaprint output.
- Re-ran the existing shared native-core audio checks successfully for all five formats and the exact fingerprint comparison. The Windows artwork normalization command also converted a PNG into a correctly sized JPEG using the host FFmpeg.
- Verified decoder extraction with fixture archives: checksum failure preserves installed tools, unsafe paths are rejected, only the required executable is selected and upstream notices are retained. The pinned release URL/checksum were checked against Gyan's published release metadata; the 109 MB Windows decoder was not downloaded/executed here.
- Added 8 Flutter tests for Windows local startup/import/export, preserving sources, save cancellation, capped fingerprint decoding, protected settings, missing tools, expired cache and remembering processing mode. All 27 Dart application/test files parsed/formatted successfully; these Flutter tests were **not executed** because of the sandbox Dart VM limitation.
- Added native Windows CI checks after the full app build, exercising the bundled helper/decoder against generated audio. Remote CI was not triggered. The Windows-specific Unicode entry point, MSVC linking, installer copies, credential storage, save dialogs and full Windows/Android app execution remain unverified here. No EXE/APK was compiled in this environment.

Earlier validation records below describe the feature versions tested at the time.

Persistent sessions and recovery update:

- Executed the combined backend and bootstrap regression suite: **66 passed** (63 backend + 3 Windows runner installer tests).
- Patched the downloaded Flutter 3.35.5 Windows runner template successfully; verified that the checkpoint intercepts close before plugin message dispatch and that rerunning the installer is idempotent.
- Added 17 Flutter test cases for complete draft restore, immutable queued snapshots, corrupt-primary backup recovery, preserved files on unrecoverable manifests, missing-source relinking with checksums, missing artwork, safe cleanup of pending imports/backup assets, workspace isolation, close/write draining, shared re-imports, backend/native expiration retry, the one-retry limit, provider 404 handling, changed audio, local deletion and search delegation. These tests were parsed/formatted but **not executed** due to the Dart VM limitation described below.
- All 23 Dart application/test files passed WebAssembly formatter parsing. Updated Android Kotlin syntax was parsed with Tree-sitter; no Kotlin compiler/device verification was performed.
- The Windows native close handshake, OS filesystem locking, platform application-support paths, lifecycle autosave and end-to-end app relaunch recovery still require native CI/device verification. No EXE/APK was compiled in this environment.

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
