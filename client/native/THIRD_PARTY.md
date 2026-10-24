# Native audio dependencies

These complete source archives are built into Android's `libresonance_audio.so`.
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
