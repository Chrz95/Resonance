# Explicit Windows executable icon binding — Resonance 1.7.2

Windows branding now patches the SDK-generated Runner.rc icon statement to reference a dedicated resources/resonance.ico under IDI_APP_ICON (101), preserving version metadata. The standard window icon resource ID remains unchanged so the runner loads the same branded resource. CMake copies the committed Resonance ICO during configuration and adds resource dependencies for rebuilds. If Flutter regeneration resets the icon statement, configuration fails with instructions to rerun bootstrap. Both the dedicated ICO and the conventional app_icon.ico contain the brand asset.

Added tools/verify_windows_icon.py and a Windows CI step after flutter build. On Windows it loads the EXE as resource data, requires the single application icon group 101 and compares each embedded RT_ICON image with the committed ICO. It does not run the EXE. This is intended to catch a stale/default executable resource before packaging.

Executed here: **26 Python bootstrap/branding/decoder/close-hook tests passed**. Checks include installer idempotency and source preservation, unchanged RC version text, rejection of changed templates, a real CMake configure in a path containing spaces, replacement of deliberately reset icon files at configuration, rejection of a default RC reference, and icon-group byte comparison accepting the brand and rejecting different artwork. Python sources parsed successfully. Existing Android assets and application Dart code are unchanged apart from the pubspec version increment.

Not executed here: MSVC resource compilation, a Windows Flutter build, the Win32 resource-loading branch against a built EXE, Explorer/taskbar rendering or icon-cache refresh. The new Windows CI step will exercise compiled-resource verification when the workflow is triggered; no remote workflow was triggered here. No prebuilt EXE is supplied. Bootstrap, clean, rebuild and run the documented executable-icon verification on Windows.

---

# Remember original overwrite targets — Resonance 1.7.1

Windows imports and drops now retain the canonical original path separately from the immutable working-copy path. Android audio import now uses ACTION_OPEN_DOCUMENT with multiple selection, captures original document URIs and takes available persistent grants. Normal overwrite reuses the stored target, with the existing explicit confirmation and checksum/backup/rollback checks. URI access is checked before attempting a write. Older drafts or a missing Windows file use a one-time lookup; Android permission loss reports the Locate original for overwrite action. Successful fallback overwrites return and retain their URI/path. Origin references and overwrite checksums survive sessions and Reset.

Android picker copies are bounded per file and in aggregate, and released after durable import; expired leftovers also use existing startup cleanup. The app never treats Android picker cache paths as original song paths. Providers without persistent write access are reported rather than assumed writable. No broad storage permission is added.

Validation for this update: all 40 Dart application/test files parsed with the WebAssembly formatter; modified files formatted. Modified MainActivity and SafeDocumentOverwrite compiled against Android API 28 with Flutter/native-audio test stubs. Added session round-trip/backward-compatibility assertions for original path/URI and a mocked Android engine test covering remembered-URI forwarding, fallback-URI return and temporary export cleanup. These Flutter tests were not executed because Flutter is unavailable and the standalone Dart VM aborts at startup in this environment.

Not verified here: actual Android picker/grant persistence across process/device restarts, cloud/read-only providers, Windows remembered-path writes, Dart type analysis, full platform builds and Flutter test execution. Run bootstrap and fully rebuild; hot reload alone cannot install the new native picker. Test a new import and repeated overwrite without a second picker, session restart, moved original, a legacy draft, revoked URI grant and unchanged-audio export on both platforms. The prior 1.7.0 host recovery and bootstrap test results below remain relevant to unchanged components, not proof of this new native document workflow.

---

# Integrated icon and original-file overwrite — Resonance 1.7.0

The generated Resonance icon is committed as a Flutter image asset, a Windows multi-size ICO, and Android legacy/adaptive resources. Bootstrap installs the committed native resources after Flutter platform generation; no image conversion runs on user machines. The app header uses the same icon.

Overwrite original song is a separate confirmed per-track action. Users choose an existing song and its SHA-256 must match the import or last successful overwrite. Windows stages the exported bytes beside the target, verifies a backup and replacement, and attempts rollback on failure. Android prepares a tagged file through the existing native export pipeline, then uses ACTION_OPEN_DOCUMENT with read/write access and a streaming verified document replacement. Backups are flushed and verified before writing; partial backup preparations are excluded from the recovery list. Failed restoration or interrupted writes retain verified backups under app-private recovery storage, exposed through Overwrite recovery backups. Original working audio and import baselines remain immutable. Last-overwrite checksums persist in sessions. The optional Windows backend still generates the tagged audio; replacement happens in the Windows app. Also fixed desktop backend Save tagged copy to actually write the bytes to the path returned by file_picker.

Executed for this update:

- **23 Python bootstrap/decoder/close-hook/branding tests passed**, including preservation of application sources, icon reinstallation after runner generation, Windows ICO sizes and Android legacy/adaptive dimensions/padding.
- Compiled the exact new SafeDocumentOverwrite Kotlin source with Kotlin 2.1.20 on OpenJDK 17 and ran **7 host JVM scenarios**: successful/repeated replacement, wrong checksum refusal, partial-write rollback, failed rollback with retained backup, unreadable source refusal, read-back verification failure with restoration, and invalid checksum rejection. The same scenario object is included in Android instrumentation tests.
- Compiled modified MainActivity and the transaction helper against Android API 28 with small stubs for Flutter method-channel/engine and existing native-audio interfaces. This checks Kotlin syntax and Android API use; it is not a real Flutter/Gradle build or verification of binding compatibility at runtime.
- **40 Dart application/test files parsed successfully** with the WebAssembly Dart formatter; changed Dart files formatted. This is a syntax check, not Dart type analysis.
- Attempted a standalone Dart 3.8.1 host run of the production desktop overwrite helper; the VM aborted with `Failed to retrieve stack bounds` before starting an isolate, including for pub get. No Dart runtime checks executed. Confirmed the staging call against the official Directory.createTemp contract: create the temporary directory inside the existing destination parent.
- Added Flutter tests for desktop in-place replacement, repeated writes, changed-file refusal, rollback after partial replacement, retained recovery backups, empty output and session checksum/reset compatibility. These tests were not executed here.

Remaining validation: Flutter SDK is unavailable here. Flutter analyzer/tests, actual Windows and Android builds, native file/document pickers, Android provider permissions/cloud behavior, launcher rendering, process-death recovery and real original-song overwrite/export on devices remain unverified. No EXE/APK is included. Provider writes are not guaranteed atomic; users should keep a separate long-term backup. Do not edit a target in another app during overwrite.

After `python tools/bootstrap_client.py`, run from client/: `flutter analyze --no-fatal-infos`, `flutter test`, and the appropriate platform build. The existing CI includes both builds and Android instrumentation when triggered; no remote workflow was triggered here. Device checks should cover all five audio formats, unchanged decoded audio, copy/overwrite/cancel, moved files, changed/read-only documents, repeated saves after restart, recovery backup export, and launcher masks/icon appearance.

---

# Higher-resolution YouTube covers — Resonance 1.6.3

Selected covers try maxresdefault.jpg, sddefault.jpg, hqdefault.jpg, then a distinct validated oEmbed thumbnail URL. Each candidate is bounded to 5 MiB, checked for dimensions and decoded before acceptance. Images below 320×180 (including typical tiny placeholders), over 25 megapixels, corrupt images and failed downloads fall back to the next variant. HTTP 429/503 stop retries; redirects are not followed. Pixel dimensions are displayed. Use/Save share the full-size image bytes; list previews stay compact. Shared image validation now occurs once in the cover loader instead of again in the picker.

Added real JPEG fixtures and service tests for maximum-resolution selection, 404-to-standard fallback, HTTP-200 placeholder/corrupt-image fallback, no usable variant, deduplicated fallback addresses and rate limiting. Widget fixtures isolate selection state from native asynchronous image decoding; decoding is exercised by the service tests. Retains the earlier replaced-search frame correction.

Executed here: all 38 Dart application/test files parsed with the WebAssembly formatter; changed Dart files formatted. Pillow decoded all four fixture JPEGs and confirmed their expected dimensions. Full source ZIP content/integrity checked. These checks do not establish Dart type correctness or runtime behavior.

Flutter SDK is unavailable here. Flutter tests, analyzer, Windows/Android builds and live high-resolution thumbnail retrieval remain unexecuted. No EXE/APK is included. From client/, run `flutter test test/youtube_cover_test.dart test/youtube_search_test.dart`, then `flutter analyze --no-fatal-infos`, `flutter test` and the platform build. Verify both Use and Save with a maximum-resolution video and a video lacking maximum resolution, plus fallback failure with an existing draft cover.

---

# Test timing correction — Resonance 1.6.2

The replaced-search widget test now pumps a frame after editing the query, before tapping Find covers. The edit changes the button's enabled state through setState; tapping without rebuilding still hits the previously disabled widget, so the replacement search never starts. Assertions now verify the initial pending query, the disabled/enabled button transition, both requested queries, the replacement result before completing the old request, and retention of that result afterward.

This is a test-only correction; application behavior and version are unchanged. Syntax parsing was rerun for all 38 Dart files. Flutter is unavailable in this workspace, so the corrected test and full Flutter suite have not been executed here. The provided log reports two failures but includes the traceback for only this test; the other failure has not been diagnosed.

Run from client/: `flutter test test/youtube_search_test.dart`, then `flutter test`.

---

# Automatic YouTube cover suggestions — Resonance 1.6.2

The YouTube cover picker now searches on opening using artist/title (or the audio filename when title is blank), ranks at most eight suggestions from the first search page, and displays thumbnails, channels, durations and matching clues. Users explicitly preview and use/save a result. Query changes cancel previous searches and invalidate selected previews. The link/browser fallback remains available. Direct shared Flutter code serves Windows, Android and optional Windows backend mode.

Validation performed for this update:

- All **38 Dart application/test files parsed successfully** with the WebAssembly Dart formatter; changed Dart files were formatted. This checks syntax, not types.
- Inspected the pinned `youtube_explode_dart` 3.1.0 package source and metadata to verify its search API, video fields, client cleanup and SDK range. Bumped the direct crypto pin to 3.0.7 to satisfy the search package dependency. Dependency resolution itself requires Flutter bootstrap and was not executed here.
- A live public YouTube search returned HTTP 200 with 20 video entries in the structure consumed by the search package. A selected result's oEmbed response returned a title and valid thumbnail host/path. Thumbnail image requests from this execution environment returned non-image responses, so a live image round trip was **not** verified. This HTTP probe did not execute the Dart search library.
- Added ranking/service tests for exact song preference, artist/title/duration clues, version handling, Unicode, nonfinite durations, duplicate/invalid/live filtering, result limits, stable ties, query construction, invalid input, errors and cancellation. Added widget tests for automatic search, preview action gating, selection reset and ignoring superseded search results. The prior manual-link test now disables automatic lookup to stay offline.

Flutter SDK is unavailable here. Flutter tests, dependency resolution, analyzer, Windows/Android builds and device interactions remain **unexecuted**. No EXE/APK is included. Existing CI runs Flutter tests and both builds when triggered; no remote workflow was triggered here. Prior-version results below do not verify this feature.

Run `python tools/bootstrap_client.py`, then from `client/`: `flutter analyze --no-fatal-infos`, `flutter test`, and the appropriate platform build. On both platforms check automatic results, an artist-only/title-only/Unicode song, a blank-title filename fallback, modified queries, rapid retries, failed thumbnail previews, manual link fallback, Use/Save/Cancel, reopened source attribution and exported artwork. Upstream public-search page changes, regional restrictions or blocks may require a package update or link fallback.

---

# YouTube cover update — Resonance 1.6.1

Adds a key-free external YouTube search/link workflow, a bounded oEmbed/thumbnail client, validated preview, explicit Use/Save actions and source attribution. Shared Flutter code serves standalone Windows, Android and optional Windows backend mode. No backend code changed.

Validation for this update is recorded separately from previous versions below. New Flutter tests cover accepted/rejected links, Unicode search encoding, canonical request construction, no credential forwarding, thumbnail host/path restrictions, unavailable videos, invalid metadata, redirect rejection, byte limits and disabled picker actions before a successful preview.

Executed here: all **36 Dart application/test files parsed successfully** with the WebAssembly Dart formatter, and the changed Dart files were formatted. This is a syntax check, not type analysis. The pinned `url_launcher` 6.3.2 package metadata was checked: Dart 3.6+/Flutter 3.27+, compatible with the project's Dart 3.8+ baseline.

Flutter SDK is not installed in this workspace. The new Flutter tests, analyzer, Windows/Android builds and device interactions have not been executed here. Live YouTube preview could not be checked through the available web fetcher. Native browser launching, document saving, image decoding and a successful live thumbnail round trip still require platform verification. No EXE or APK is included. Prior-version results below do not validate the new feature.

Run after bootstrap: `cd client`, `flutter analyze --no-fatal-infos`, `flutter test`, then build and verify on each platform. Check Use/Save/Cancel, reopen a saved workspace, verify exported artwork, and try a private/unavailable link with an existing draft cover.

---

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
