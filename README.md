# Resonance 1.3.0

This update remembers the Windows backend URL and key, reconnects automatically, adds desktop drag-and-drop with automatic recognition, and adds **Other covers / Other lyrics** buttons for each candidate. Earlier availability badges and the AcoustID date fix are retained.

To update, replace the project files while keeping `.env`. Rebuild the Windows service with `docker compose up -d --build`. Then run `python tools/bootstrap_client.py`, open `client/`, and rebuild with `flutter build windows --release` or `flutter build apk --debug`. New dependencies require `flutter pub get` (also run by the bootstrap). Updating only the backend does not update the app UI.

A Flutter music tagger for Windows and **standalone Android**. Recognize a song by its audio fingerprint or existing tags, review matches, fetch lyrics and artwork, and save a tagged audio copy. All metadata, lyrics and covers can also be edited manually without identifying the song first.

**Android does not use the Windows application, Python service, a PC address, or a server token.** It bundles TagLib and Chromaprint and uses Android’s own audio decoder and document picker. Audio parsing, manual editing, fingerprint extraction and tag writing run on the phone. Online recognition and lookup need Internet access, not a desktop companion.

Windows continues to use the included local Python service. This source package includes build scripts and CI; it does not include a prebuilt or signed EXE/APK. See [VALIDATION.md](VALIDATION.md) for checks actually executed.

## Remembered connection and automatic reconnect

On Windows, enter your backend URL and `RESONANCE_TOKEN` once in **Connect**. A successful connection saves both together using `flutter_secure_storage` and the operating system’s protected credential storage. On later launches the app checks the saved service automatically. If it is not ready, it retries every 15 seconds without blocking the UI. The backend still needs to be running; this feature does not launch Docker or install a Windows service.

Use **Connect** to change the saved URL/key. **Forget saved connection** deletes the stored entry; the current in-memory connection remains usable until you close the app. Keys are never written to a plain project config file. Android remains standalone and retains its own online-service settings on the phone.

## Drag-and-drop songs

On desktop, drop one or more MP3, FLAC, M4A, Ogg Vorbis or Opus files anywhere in the studio. The drop target highlights while hovering. Supported, readable files are imported and identified sequentially; unsupported files, folders, empty files and files over 120 MiB are rejected with a message. The app uses the restored backend connection, or opens first-time connection setup if needed.

A dropped file is kept in the queue even when recognition fails, so it can still be edited manually. Ordinary file-picker imports remain available for manual editing without automatically starting recognition. Android continues to use its native file picker; Android OS drag-and-drop is not enabled by this implementation.

## Covers and lyrics from other sources

Each candidate has **Other covers** and **Other lyrics** buttons. Clicking either selects/highlights that candidate and searches alternatives using its title, artist and album. Results are shown for review before any draft content is changed.

- **Other covers:** searches the public iTunes Search API, filters by artist, removes duplicate album IDs and prioritizes the candidate’s album. You can preview the album/track/source, choose **Use cover** to load it into the editor, or **Save image** to download a separate JPEG.
- **Other lyrics:** queries lyrics.ovh and LRCLIB’s version search. The app filters LRCLIB results by title and artist, shows the album/version and previews the lyrics. **Use lyrics** replaces the draft’s plain/timed lyric content; **Save lyrics** downloads a `.txt` or `.lrc` file.
- These actions change only the chosen content. Check the metadata editor before saving the audio file. They never silently choose a result or overwrite the original audio.
- If a source is unavailable, other lyric results remain usable and the app shows the source error. Coverage is not guaranteed. Successfully obtained alternatives also contribute to that candidate’s availability badges.

The APIs are accessed directly from Android and through the service on Windows. Cover downloads resolve a selected numeric album ID through iTunes; the service does not accept arbitrary image URLs. Only HTTPS artwork on `mzstatic.com` hosts is accepted, image redirects are not followed, and images are bounded to 5 MiB before normalization. Larger artwork is attempted with a fallback to the supplied thumbnail. The source is recorded when you load content into the editor.

The Windows service adds `POST /tracks/{id}/alternatives` (kind/title/artist/album) and `POST /tracks/{id}/alternative-cover` (collection_id). No additional API key is required for these providers. Artwork and lyric rights remain with their respective owners; access to a public lookup API does not grant redistribution rights.

## Candidate availability badges

Each candidate has two badges, updated sequentially in the background so recognition results and editing remain usable:

| Badge | Meaning |
|---|---|
| Lyrics ✓ | LRCLIB supplied nonempty plain or timed lyrics matching this candidate’s title, artist, album and duration where known. |
| Cover ✓ | Cover Art Archive confirmed a front-cover thumbnail for this specific release. |
| No lyrics / No cover | A completed lookup found no content. A candidate without a selected release cannot supply release artwork. |
| Lyrics … / Cover … | A check is queued or in progress. |
| Lyrics ? / Cover ? | Availability could not be confirmed, for example because the service is offline or rate limited. |

Hover or long-press a badge for details. Instrumental tracks are identified in the lyric tooltip. These badges describe online lookup availability, not the original file’s embedded content. The Fetch lyrics/Fetch cover options still control what gets loaded when you choose Use match; the availability checks are independent of those options. Selecting a candidate and exporting still require review.

Checks use the candidate recording’s duration when known and otherwise the imported file duration. Artwork is checked with a HEAD request following redirects, rather than downloading a complete image for every candidate. Successful JSON lookups and positive/negative artwork checks are reused for 15 minutes. Transient failures stay unknown. Background checks are focused on the selected track; results for changed selections, removed tracks, replaced candidate lists or changed connections are ignored. Android contacts the same public services directly without a PC.

The Windows service exposes `POST /tracks/{id}/availability` with candidate `title`, `artist`, `album`, optional release UUID and optional duration. Its response includes nullable `has_lyrics`/`has_cover`, an `instrumental` flag and warnings. `/health` reports version `1.3.0` and `candidate_availability: true` so the running service can be checked after rebuilding.

## Manual editing

1. Import an MP3, FLAC, M4A, Ogg Vorbis or Opus file.
2. Choose **Edit manually — no match needed**.
3. In **Tags**, change title, artist, album, album artist, release date, genre, track/disc numbers or MusicBrainz IDs.
4. In **Lyrics**, type or paste plain/timed lyrics, or import a UTF-8 `.txt` or `.lrc` file. Blank a field to remove those lyrics. Timed lyrics can also be exported as an `.lrc` sidecar.
5. In **Cover**, choose a local JPEG, PNG or WebP image, remove the embedded artwork, or keep the original.
6. Choose **Save tagged copy** and select the destination. Original audio packets are not re-encoded. Reset restores the imported values.

On Android all these steps work **offline**, with no API key, account or service setup. Imported files are private working copies. Export writes the current draft into a fresh copy. Android’s Storage Access Framework streams the output to your selected document URI, avoiding large method-channel audio buffers. Storage and microphone permissions are not requested.

## Standalone Android: recognition and lookup

The top **On device** button opens online-service settings:

- **AcoustID application key:** register a free application at <https://acoustid.org/new-application> for audio matching. This is an application key, not a personal submission key. Leave it blank to use manual editing or metadata search; fingerprint extraction still works locally.
- **MusicBrainz contact email or project URL:** used in the required application user-agent string. It costs nothing and needs no API account.

These settings are saved in the Android app’s private preferences. You can also supply developer defaults using `--dart-define=ACOUSTID_API_KEY=...` and `--dart-define=MUSIC_USER_AGENT=...` when building. Application keys identify the application; they are not user-account passwords.

Choose **Identify audio** to decode up to 120 seconds on the phone, generate a Chromaprint fingerprint and send only that fingerprint and duration to AcoustID. Or search MusicBrainz directly by name. Choose a recording/release candidate to fetch its tags, lyrics and cover. Review everything before saving. A recording can belong to several release editions; the user chooses the release.

Direct HTTPS clients contact AcoustID, MusicBrainz, LRCLIB and Cover Art Archive. MusicBrainz requests are serialized at least 1.1 seconds apart; other lookups are throttled, JSON results are cached for 15 minutes, and Retry-After cooldowns are honored. Unavailable lyrics/artwork keep existing content and display a notice. Recognition coverage is not guaranteed.

## Build Android

Install Flutter stable with Dart 3.8+ and Python 3.12+. Follow [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup), including the Android SDK and JDK 17. In Android Studio’s SDK Tools, install **CMake 3.22.1** and the NDK version requested by your Flutter SDK. Gradle may install a missing NDK after Android SDK licenses are accepted.

From the project root:

```sh
python tools/bootstrap_client.py
cd client
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

Install `client/build/app/outputs/flutter-apk/app-debug.apk` on your phone. Start the app and import audio immediately; no PC process needs to be running. Build dependencies are resolved while compiling, but the native audio libraries’ complete pinned source archives are already supplied under `client/native/vendor/`.

The bootstrap generates SDK platform runners, preserves Dart sources, installs the Kotlin/JNI integration, configures CMake, installs instrumentation tests, and resolves Flutter packages. It is safe to rerun. Use `flutter run -d DEVICE_ID` for development. Android API 24+ is required. Common mono/stereo audio is fingerprinted using the codecs available on the device. DRM-protected audio is unsupported.

For store release, configure your own signing keystore using [Flutter’s Android release instructions](https://docs.flutter.dev/deployment/android) and build an app bundle. Source archives and dependency license notices must accompany distributions as applicable; see `client/native/THIRD_PARTY.md`.

## Windows: start the included service

Windows uses the same manual editor and lookup interface, with the Python service doing audio processing. Use Docker Compose or native Python.

### Docker Compose

1. Copy `.env.example` to `.env`.
2. Generate a token with `python -c "import secrets; print(secrets.token_urlsafe(32))"` and set `RESONANCE_TOKEN`.
3. Set `MUSIC_USER_AGENT` with your real contact email or project URL, such as `Resonance/1.1 (mailto:you@yourdomain.com)`.
4. Optionally set your free `ACOUSTID_API_KEY`.
5. Run `docker compose up --build -d`.

Docker Engine is open source and can run under Windows WSL2. Docker Desktop is an alternative subject to its own terms. Stop the service with `docker compose down`. No paid cloud host is needed.

### Native Python on Windows

Install Python 3.12+ and [Chromaprint fpcalc](https://acoustid.org/chromaprint); put `fpcalc.exe` on PATH. Alternatively use FFmpeg with the `chromaprint` muxer.

From PowerShell in the project root:

```powershell
py -m venv .venv
.\.venv\Scripts\python -m pip install -r backend\requirements.txt
$env:RESONANCE_TOKEN = "your-generated-token"
$env:MUSIC_USER_AGENT = "Resonance/1.1 (mailto:you@yourdomain.com)"
$env:ACOUSTID_API_KEY = "your-free-application-key"
Set-Location backend
..\.venv\Scripts\python -m uvicorn app.main:app --host 127.0.0.1 --port 8765 --workers 1
```

For Linux development, install `ffmpeg libchromaprint-tools python3-venv`, create a virtual environment, install `backend/requirements.txt`, set those environment variables and run uvicorn from `backend/`. Native Python reads environment variables; `.env` is only read by Docker Compose. Run one service worker because sessions and throttles are held in memory.

### Build Windows

Follow [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup), including Visual Studio’s C++ desktop workload and the **C++ ATL** optional component required by secure credential storage. Windows builds require Windows.

```sh
python tools/bootstrap_client.py
cd client
flutter build windows --release
```

Distribute the entire `client/build/windows/x64/runner/Release/` folder. Open the app, choose **Connect**, enter `http://127.0.0.1:8765` and the server token, then import music. The URL and key are saved in protected OS storage and restored automatically on later launches.

## Formats and limits

| Format | Metadata / plain lyrics | Embedded artwork | Timed lyrics |
|---|---|---|---|
| MP3 | ID3v2 / USLT | APIC | Custom text frame |
| FLAC | Vorbis comments / LYRICS | Native picture block | SYNCEDLYRICS |
| M4A | iTunes atoms / ©lyr | covr | Custom iTunes freeform atom |
| Ogg Vorbis | Vorbis comments / LYRICS | METADATA_BLOCK_PICTURE | SYNCEDLYRICS |
| Opus | Vorbis comments / LYRICS | METADATA_BLOCK_PICTURE | SYNCEDLYRICS |

Desktop and Android understand each other’s timed lyric custom-tag variants. Player support for timed tags varies; use `.lrc` export for compatibility. New covers are normalized to JPEG up to 1600 pixels on the longest side. Keep-original artwork is preserved. Unknown metadata is retained. Managed fields are represented as a single editable string.

Audio imports are limited to 120 MiB and covers to 5 MiB / 25 megapixels. Up to 50 files and approximately 2 GiB of working audio are allowed per session. Tag each imported track individually. WAV, raw AAC, video containers and DRM audio are unsupported.

Android session drafts are held while the app runs, with working audio in the app cache; stale cache entries older than a day are removed at startup. Export before closing the app; this version does not restore draft sessions after process termination. The Windows service’s inactive sessions expire after about an hour and clear on shutdown.

## Privacy and free services

On Android, full audio never leaves the phone. Windows uploads audio only to your configured Python service. AcoustID receives the fingerprint/duration, MusicBrainz receives searches and selected IDs, LRCLIB receives title/artist/album/duration, and Cover Art Archive receives the selected release ID. Android disables cleartext HTTP traffic.

- [AcoustID](https://acoustid.org/webservice): free noncommercial recognition with a free application key; maximum 3 requests/second.
- [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API): free noncommercial public metadata; no key, meaningful user agent, maximum one request/second.
- [LRCLIB](https://lrclib.net/docs): public lyrics lookup without a required key. Some songs/versions have no lyrics.
- [lyrics.ovh](https://github.com/NTag/lyrics.ovh): public alternate plain-lyric lookup without an API key.
- [iTunes Search API](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/index.html): alternate album artwork and catalog metadata; requests are spaced at least 3.1 seconds apart and cached.
- [Cover Art Archive](https://musicbrainz.org/doc/Cover_Art_Archive/API): freely accessible artwork. Lyrics/images retain their respective rights.
- Android bundles open-source TagLib 2.1.1, Chromaprint 1.5.1 and its Kiss FFT backend. Native code uses Android media APIs and does not require FFmpeg, Python or a separate executable on the phone.
- The desktop service uses FastAPI, HTTPX, Mutagen and Pillow. Resonance is GPL-3.0-or-later; third-party libraries retain their own licenses.

## Validation and tests

Backend tests:

```sh
python -m pip install -r backend/requirements-dev.txt
cd backend
python -m pytest tests -q
```

Native Android core tests on Linux (requires CMake 3.22+, a C++17 compiler, FFmpeg and the backend Python dependencies):

```sh
cmake -S client/native -B native-build -DCMAKE_BUILD_TYPE=Release
cmake --build native-build --target resonance_native_test --parallel 4
python tools/test_native.py --binary native-build/resonance_native_test
```

The same C++ tag writer and fingerprint library used in the APK are exercised against generated audio in all five formats, including Unicode, manual tags, lyrics, artwork keep/replace/remove, unchanged decoded audio, Windows/Android tag interoperability and matching Chromaprint results.

Flutter tests also cover protected connection persistence/forgetting, dropped-file validation, alternate-source filtering, download bounds and explicit result selection. Flutter tests cover draft behavior and a mocked standalone Android engine with direct-service requests and native save dispatch. To exercise real JNI and MediaCodec on an emulator/phone, bootstrap and build the debug APK, connect an Android device, then run `./gradlew connectedDebugAndroidTest` from `client/android/` (`gradlew.bat` on Windows). These device tests use generated test audio, no network and no API key.

CI includes the backend suite, host native-core tests, Flutter analysis/tests, Windows and Android builds, and an Android emulator instrumentation job. Preparing source files does not run those remote workflows. See [VALIDATION.md](VALIDATION.md) for actual results and remaining device-validation limits.
