# Resonance

**Recognize your music. Complete its tags. Make it yours.**

A Flutter music tagger for **Windows and Android**. Identify songs from their audio fingerprints, find metadata, lyrics and album artwork, then review and save a tagged copy—all in one interface.

Android runs independently on your phone. Windows runs locally on your PC. Neither needs a companion app or a hosted backend for everyday use.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q1J229F1AG)

[Features](#what-you-can-do) · [Getting started](#getting-started) · [Build Android](#build-android) · [Build Windows](#build-standalone-windows) · [Privacy](#privacy-and-free-services)

> **Current source version: 1.6.1.** This package contains source and build scripts, not a prebuilt or signed EXE/APK. See [VALIDATION.md](VALIDATION.md) for completed checks and remaining Windows/Android device validation.

## What you can do

### Identify songs and choose the right release

Generate a Chromaprint audio fingerprint locally and look up matches through AcoustID, or search MusicBrainz using existing song information. Review candidate recordings and release editions before applying a match.

Each candidate displays **lyrics** and **cover** availability badges. See which matches have content available, which checks are still running, and which sources could not be reached. Hover or long-press a badge for details. Badges describe online availability, rather than content already embedded in your file.

### Edit every detail yourself

Recognition is optional. Open a song and edit its title, artist, album, album artist, release date, genre, track/disc numbers and MusicBrainz IDs directly.

- **Lyrics:** type or paste plain or timed lyrics, import UTF-8 `.txt` or `.lrc` files, remove lyrics, or export a timed `.lrc` sidecar.
- **Artwork:** keep the embedded cover, replace it with a local JPEG, PNG or WebP image, or remove it.
- **Export:** save the finished draft as a new tagged audio copy without re-encoding the audio. The original file stays unchanged.

Manual editing and export work offline on Android and in local Windows mode, with no account or API key.

### Find lyrics and covers from other sources

Use **Other lyrics** or **Other covers** on a selected candidate to search alternatives. Preview the song/version, artwork and source before choosing what to use.

Lyrics come from LRCLIB and lyrics.ovh; alternative artwork comes from the iTunes catalog alongside release artwork from Cover Art Archive. Load a result into the editor or download a separate image, `.txt` or `.lrc` file. Results are never silently applied, and missing content leaves your existing draft intact.

### Work through a collection

Import several songs and recognize selected tracks or the whole queue. Batch controls include progress, **pause/resume**, **cancel remaining**, **skip**, and **retry failed or unfinished tracks**. Review and export each song individually; batch recognition does not automatically apply matches or write files.

On Windows, drag supported songs into the app to import and identify them sequentially. A song stays available for manual editing if recognition fails. File-picker imports are available on both platforms and let you start editing without automatic recognition.

### Pick up where you left off

Resonance saves your workspace: working audio, tag edits, plain and timed lyrics, artwork, fingerprints, candidate results, selections and batch status. Autosave runs after edits and at lifecycle checkpoints; **Save session** saves immediately.

Private working copies let you reopen a session even if the original file has moved. Recovery snapshots help restore interrupted sessions, and **Locate original** can reconnect a missing working copy to a byte-identical file. Interrupted batch work can be retried after reopening.

**Save session** preserves work inside Resonance. **Save tagged copy** creates the finished audio file for your music library. Export copies separately before clearing app data or uninstalling.

## Windows and Android, each fully functional

| Capability | Windows | Android |
|---|---|---|
| Local parsing, fingerprinting and tag writing | Yes | Yes |
| Manual tags, lyrics and artwork editing offline | Yes | Yes |
| Online recognition, metadata and content lookup | Yes | Yes |
| Batch recognition and saved workspaces | Yes | Yes |
| Import audio | File picker and drag-and-drop | Native document picker |
| Export tagged copies | Local destination | Android document destination |
| Companion app or backend required | No | No |
| Optional Python backend processing | Available | Not required or used |

Windows uses a bundled TagLib/Chromaprint helper and FFmpeg decoder. Android bundles TagLib and Chromaprint and uses its own media decoder. The finished standalone apps do not need Python or Docker installed.

## Getting started

1. Build the app for your platform using the instructions below.
2. Import songs with the file picker, or drop them into the Windows app.
3. Open **On this PC** or **On device** to configure online lookup, if wanted.
4. Choose **Identify audio**, search by metadata, or select **Edit manually — no match needed**.
5. Review a candidate, fetch lyrics/artwork, and make any edits.
6. Choose **Save tagged copy** and select a destination.

For audio recognition, register a free **AcoustID application key** at <https://acoustid.org/new-application>. Use an application key, not a personal submission key. MusicBrainz lookup requires a contact email or project URL in the application's user-agent settings. Manual editing and export require neither.

Settings are remembered on the device. Android uses private preferences; Windows uses protected credential storage. Developer defaults can also be supplied with `--dart-define=ACOUSTID_API_KEY=...` and `--dart-define=MUSIC_USER_AGENT=...` when building.

## Supported files and practical limits

**MP3, FLAC, M4A, Ogg Vorbis and Opus** support metadata, embedded artwork and lyrics. Timed lyrics use format-specific tags; player compatibility varies, so `.lrc` export is available. Unknown metadata and keep-original artwork are retained.

- Up to **50 songs** per workspace, **120 MiB per song**, and approximately **2 GiB** of saved working audio.
- Replacement cover files up to **5 MiB**; artwork is normalized for embedding.
- Windows 10/11 x64 and Android API 24+ are the supported targets.
- WAV, raw AAC, video containers and DRM-protected audio are unsupported. Android decoding depends on the codecs available on the device.
- Online matching and content availability depend on the song, release and provider. An Internet connection is needed for those lookups.

Recognition decodes up to 120 seconds locally. Online requests are throttled and cached, and service cooldowns are honored. See [BATCH_UPDATE.md](BATCH_UPDATE.md) for batch usage and limitations.

## Optional backend and remembered connections

Windows defaults to local processing. If you prefer the Python service, choose **On this PC → Use optional backend**, enter its URL and `RESONANCE_TOKEN`, and connect. Successful credentials are saved in protected OS storage; the app remembers the mode, reconnects at startup and retries while disconnected.

Use **Use on this PC** to return to local processing or **Forget saved connection** to remove saved credentials. Workspaces are kept separately for local processing and each backend URL. Offline backend drafts remain editable, but processing and export in that mode need the service. Reconnection does not start Docker or install a service.

Android remains fully independent of this optional backend.

## YouTube thumbnails as covers

Choose **YouTube cover** on a candidate entry or in the **Cover** editor—even when editing manually without a match.

1. Adjust the suggested artist/title search and choose **Search on YouTube**. YouTube opens in your browser or installed app.
2. Copy a video's link, return to Resonance and paste it into **YouTube video link**.
3. Choose **Preview thumbnail** to see the video title, channel and full thumbnail.
4. Choose **Use cover** to update the draft, or **Save image** to download a separate JPEG. Use **Save tagged copy** to embed it in your audio copy.

This option needs no YouTube API key or paid service. Search happens on YouTube; results are not scraped or listed inside Resonance. Standard watch links, shortened `youtu.be` links, YouTube Music, Shorts, live and embed links are accepted. The app retrieves public video information and its supplied thumbnail directly from YouTube, on both Windows and Android, including when Windows uses the optional backend. No full video or audio is downloaded.

The preview keeps the thumbnail's full aspect ratio; rectangular images and text are not cropped away. Thumbnails may differ from official album artwork. Private, deleted, restricted or unavailable videos can fail; try another link. Images must be valid, at most 5 MiB and at most 25 megapixels. Downloads use HTTPS, restrict thumbnail addresses to YouTube's image host and reject redirects. Only an explicit **Use cover** action changes the draft, records the source video link and marks the selected candidate's cover badge. Cancel, failed lookups and separate image downloads leave the draft intact. Your existing cover remains available via **Keep original**.

Opening search sends the entered search text to YouTube. Preview requests send the selected video ID to YouTube and download its thumbnail. Use images you have permission to use; thumbnails retain their owners' rights.

To update from 1.6.0, rerun `python tools/bootstrap_client.py` to resolve the added `url_launcher` dependency, then rebuild the Windows app or Android APK. This is a client update; no backend endpoint or new credential is required.

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

## Build standalone Windows

Follow [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup), including Visual Studio’s C++ desktop workload and the **C++ ATL** optional component for secure credential storage. Windows builds require Windows, Flutter stable with Dart 3.8+, and Python 3.12+ for the build scripts.

```sh
python tools/bootstrap_client.py
cd client
flutter analyze --no-fatal-infos
flutter test
flutter build windows --release
```

On Windows, bootstrap downloads Gyan’s FFmpeg 9.0.2 essentials ZIP (about 109 MB), first from the publisher’s GitHub mirror and then from gyan.dev if needed. HTTPS certificate verification and the pinned SHA-256 are required before installation. The portable helper is built from the supplied TagLib/Chromaprint sources by CMake. The decoder is copied into the app’s `tools/` folder with its notices and build provenance. Android builds do not download or include it. The download is a build-time step; the finished Windows app does not download executables at runtime or search PATH for tools.

Distribute the entire `client/build/windows/x64/runner/Release/` folder, including `tools/`, Flutter data and DLLs. End users do not need Python, Docker, FFmpeg installation or a running service. Windows 10/11 x64 is the supported desktop target. This package contains source, not a built EXE.

Launch the app and import music immediately. **On this PC** opens the free AcoustID key and MusicBrainz contact settings. Without a key, manual editing, artwork embedding, lyric editing and export still work offline. Online recognition requires Internet access and the free application key; metadata search requires the contact setting. Decoding and tag writing run as local child processes without a shell or HTTP listener. Only fingerprints and lookup text go to the music services.

## Bootstrap download and certificate errors

The reported `CERTIFICATE_VERIFY_FAILED: certificate has expired` occurs during the FFmpeg download's TLS handshake, before extraction. Bootstrap now tries the publisher's independent HTTPS mirrors, rejects incorrect checksums, cleans partial downloads and reports a concise error if both sources fail. It retains certificate verification. A verified cached archive is reused without a network request; an invalid cache is downloaded again. Previously installed tools are retained if a download or replacement fails.

Retry normally with:

```sh
python tools/bootstrap_client.py
```

If both hosts fail verification, check Windows date/time and certificate trust. You can download the exact pinned [FFmpeg 9.0.2 essentials ZIP](https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip) in a browser, then supply it directly:

```sh
python tools/bootstrap_client.py --ffmpeg-archive "C:/Downloads/ffmpeg-9.0.2-essentials_build.zip"
```

That bypasses only the FFmpeg network download. The archive must still match SHA-256 `60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba`. Flutter/Gradle may still need network access for their own dependencies. For a managed network that uses its own trusted certificate authority, an additional PEM bundle can be supplied without disabling normal certificate/hostname verification:

```sh
python tools/bootstrap_client.py --ca-bundle "C:/Certificates/organization-root.pem"
```

These options affect Windows decoder preparation. Android remains independent of the Windows decoder and backend. All options can be inspected with `python tools/bootstrap_client.py --help`.

## Optional Windows backend service

The optional backend mode uses the same editor and lookup interface, with the Python service doing audio processing. It can reopen workspaces from earlier versions. Use Docker Compose or native Python; local Windows mode does not need either.

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

### Connect to the optional backend

Open **On this PC → Use optional backend**, enter `http://127.0.0.1:8765` and the server token, then import music or reopen the saved backend workspace. The URL, key and selected backend mode are remembered automatically.

## Formats and limits

| Format | Metadata / plain lyrics | Embedded artwork | Timed lyrics |
|---|---|---|---|
| MP3 | ID3v2 / USLT | APIC | Custom text frame |
| FLAC | Vorbis comments / LYRICS | Native picture block | SYNCEDLYRICS |
| M4A | iTunes atoms / ©lyr | covr | Custom iTunes freeform atom |
| Ogg Vorbis | Vorbis comments / LYRICS | METADATA_BLOCK_PICTURE | SYNCEDLYRICS |
| Opus | Vorbis comments / LYRICS | METADATA_BLOCK_PICTURE | SYNCEDLYRICS |

Desktop and Android understand each other’s timed lyric custom-tag variants. Player support for timed tags varies; use `.lrc` export for compatibility. New covers are normalized to JPEG (up to 1200 pixels on local Windows; up to 1600 pixels on Android/backend). Keep-original artwork is preserved. Unknown metadata is retained. Managed fields are represented as a single editable string.

Audio imports are limited to 120 MiB and covers to 5 MiB. Android/backend also reject covers over 25 megapixels; the Windows decoder bounds individual allocations and output dimensions. Up to 50 files and approximately 2 GiB of working audio are allowed per session. Tag each imported track individually. WAV, raw AAC, video containers and DRM audio are unsupported.

Drafts and durable working sources are restored from application-support storage. Temporary processing copies may expire or be removed from cache; they are recreated from the saved sources when needed. The optional backend’s inactive sessions expire after about an hour and clear on shutdown.

## Privacy and free services

In local Windows mode and on Android, full audio stays on the device. Optional backend mode uploads audio only to the configured Python service. AcoustID receives the fingerprint/duration, MusicBrainz receives searches and selected IDs, LRCLIB receives title/artist/album/duration, and Cover Art Archive receives the selected release ID. Android disables cleartext HTTP traffic.

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

Shared native core tests on Linux (requires CMake 3.22+, a C++17 compiler, FFmpeg and the backend Python dependencies):

```sh
cmake -S client/native -B native-build -DCMAKE_BUILD_TYPE=Release
cmake --build native-build --target resonance_native_test resonance_desktop --parallel 4
python tools/test_native.py --binary native-build/resonance_native_test
RESONANCE_DESKTOP_BINARY=./native-build/resonance_desktop python -m pytest tools/tests -q
```

The same C++ tag writer and fingerprint library used in the APK are exercised against generated audio in all five formats, including Unicode, manual tags, lyrics, artwork keep/replace/remove, unchanged decoded audio, Windows/Android tag interoperability and matching Chromaprint results.

Flutter tests also cover protected connection persistence/forgetting, dropped-file validation, alternate-source filtering, download bounds and explicit result selection. Flutter tests cover draft behavior and a mocked standalone Android engine with direct-service requests and native save dispatch. To exercise real JNI and MediaCodec on an emulator/phone, bootstrap and build the debug APK, connect an Android device, then run `./gradlew connectedDebugAndroidTest` from `client/android/` (`gradlew.bat` on Windows). These device tests use generated test audio, no network and no API key.

CI includes the backend suite, decoder preparation checks, host native-core/helper tests, Flutter analysis/tests, Windows and Android builds, Windows bundled-tool audio checks, and an Android emulator instrumentation job. Preparing source files does not run those remote workflows. See [VALIDATION.md](VALIDATION.md) for actual results and remaining device-validation limits.
