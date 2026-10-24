# Native audio dependencies

These complete source archives are built into Android's `libresonance_audio.so`
and Windows' `resonance_desktop.exe` helper.
Their original license and copyright files are inside each archive. Runtime
recognition uses Android's own media decoders, not a desktop executable.

| Archive | Upstream revision | License |
|---|---|---|
| taglib.tar.gz | taglib/taglib v2.1.1, `7d86716194777e0294453bfdc9dd170bd033e1f4` | LGPL-2.1 / MPL-1.1 |
| chromaprint.tar.gz | acoustid/chromaprint v1.5.1, `5c3be6803856f25b11d1d704bac56e733b4fc997` | LGPL-2.1-or-later |
| utfcpp.tar.gz | nemtrif/utfcpp v4.0.6, `b26a5f718f4f370af1852a0d5c6ae8fa031ba7d0` | BSL-1.0 |

Chromaprint's source archive also includes Kiss FFT (BSD) and its original
notices. CMake verifies every archive using the SHA-256 in CMakeLists.txt. Include
these source archives and this project's source with distributed builds to make
the corresponding native code available. This repository's GPL-3.0-or-later
license remains applicable to Resonance; dependencies keep their own licenses.

## Windows decoder

Windows builds bundle Gyan's FFmpeg 9.0.2 essentials decoder, fetched at build
time from `https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.2-essentials_build.zip`.
The pinned archive SHA-256 is
`60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba`.
The build preserves the archive's non-executable documentation/license files
and records its version, source link and checksum under `tools/licenses/`.
Only `ffmpeg.exe` is used; this is a GPLv3 build. It decodes audio/cover images;
TagLib writes the output without re-encoding the audio stream. Android does not
bundle or use this executable.

Build information: https://www.gyan.dev/ffmpeg/builds/ and
https://github.com/GyanD/codexffmpeg/releases/tag/9.0.2 .
Upstream FFmpeg source revision: https://github.com/FFmpeg/FFmpeg/tree/946fcce07b .
Binary distributors must preserve the included notices and meet the bundled
dependencies' source/relinking obligations. The FFmpeg binary/source archive is
not part of this source-only ZIP; the preparation script downloads its verified
binary archive on the Windows build machine.
