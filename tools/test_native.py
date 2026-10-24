#!/usr/bin/env python3
"""Exercise the Android C++ engine on host-generated audio, without a phone."""
import argparse
import hashlib
import shutil
import subprocess
import tempfile
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from app.audio import read as desktop_read, write_copy


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    binary = parser.parse_args().binary.resolve()

    def run(*args):
        return subprocess.check_output([str(binary), *map(str, args)], text=True).strip()

    def pcm(path):
        return subprocess.check_output(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-map", "0:a:0", "-f", "s16le", "-"])

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        image = root / "cover.jpg"
        Image.new("RGB", (64, 64), (120, 80, 220)).save(image)
        for extension, codec in {"mp3": "libmp3lame", "flac": "flac", "m4a": "aac", "ogg": "libvorbis", "opus": "libopus"}.items():
            original = root / ("original." + extension)
            subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=8", "-c:a", codec, str(original)], check=True)
            encoded = original.read_bytes()
            before = hashlib.sha256(pcm(original)).digest()
            output = root / ("edited." + extension)
            shutil.copyfile(original, output)
            run("write", output, image)
            desktop_tags, _, desktop_cover = desktop_read(output)
            assert desktop_tags.lyrics == "Manually typed lyrics"
            assert desktop_tags.synced_lyrics == "[00:01.00] Timed lyrics", extension + " desktop cannot read Android lyrics"
            assert desktop_cover
            desktop = root / ("desktop." + extension)
            write_copy(output, desktop, desktop_tags, "keep", None)
            assert "synced_lyrics=[00:01.00] Timed lyrics" in run("read", desktop), extension + " Android cannot read desktop lyrics"
            run("keep", output)
            assert "title=Manually edited title" in run("read", output)
            assert hashlib.sha256(pcm(output)).digest() == before, extension + " changed audio"
            run("clear", output)
            assert original.read_bytes() == encoded, extension + " changed original"
            assert hashlib.sha256(pcm(output)).digest() == before, extension + " clearing changed audio"
            print(extension + ": all tags, Unicode, lyrics, artwork replace/keep/remove and audio preservation passed")
        raw = root / "pcm.raw"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=12", "-ar", "44100", "-ac", "1", "-f", "s16le", str(raw)], check=True)
        fingerprint = run("fingerprint", raw)
        expected = subprocess.check_output(["ffmpeg", "-nostdin", "-v", "error", "-f", "s16le", "-ar", "44100", "-ac", "1", "-i", str(raw), "-f", "chromaprint", "-fp_format", "base64", "-"], text=True).strip()
        assert len(fingerprint) > 8
        assert fingerprint == expected, "Native fingerprint differs from FFmpeg/Chromaprint"
        print("Native Chromaprint fingerprint matches FFmpeg's result for the same PCM.")


if __name__ == "__main__":
    main()
