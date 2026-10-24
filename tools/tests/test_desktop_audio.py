"""Run against a host-built helper; CI also runs the same test on Windows."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from PIL import Image
import pytest


FIELDS = ["title", "artist", "album", "album_artist", "date", "genre", "track_number",
          "disc_number", "recording_id", "release_id", "lyrics", "synced_lyrics"]


@pytest.fixture
def helper():
    binary = os.environ.get("RESONANCE_DESKTOP_BINARY")
    if not binary:
        pytest.skip("Set RESONANCE_DESKTOP_BINARY to a built native helper")
    return str(Path(binary).resolve())


def run(helper, *args):
    return subprocess.check_output([helper, *map(str, args)]).decode("utf-8").strip()


def pcm(path):
    return subprocess.check_output(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-map", "0:a:0", "-f", "s16le", "-"])


@pytest.mark.parametrize("extension,codec", [("mp3", "libmp3lame"), ("flac", "flac"), ("m4a", "aac"), ("ogg", "libvorbis"), ("opus", "libopus")])
def test_desktop_tag_roundtrip_and_source_preservation(helper, tmp_path, extension, codec):
    original = tmp_path / f'Δοκιμή 音楽 🎵 source.{extension}'
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-c:a", codec, str(original)], check=True)
    source_bytes = original.read_bytes()
    audio_hash = hashlib.sha256(pcm(original)).digest()
    output = tmp_path / f"edited.{extension}"
    shutil.copyfile(original, output)
    tags = {key: "" for key in FIELDS}
    tags.update(title='Quoted "title" — 音楽 🎵', artist="Artist", album="Album", date="2017-07-19",
                track_number="2/10", lyrics="First line\nSecond line\twith tab", synced_lyrics="[00:01.00] A lyric")
    directory = tmp_path / "tags"
    directory.mkdir()
    for key, value in tags.items():
        (directory / key).write_text(value, encoding="utf-8", newline="")
    cover = tmp_path / "cover.jpg"
    Image.new("RGB", (32, 32), (10, 100, 200)).save(cover)
    assert run(helper, "write", output, directory, "replace", cover) == "ok"
    extracted = tmp_path / "embedded.img"
    result = json.loads(run(helper, "read", output, extracted))
    assert result["tags"] == tags
    assert result["duration"] > 3
    assert extracted.read_bytes() == cover.read_bytes()
    assert hashlib.sha256(pcm(output)).digest() == audio_hash
    run(helper, "write", output, directory, "keep", "unused")
    assert json.loads(run(helper, "read", output, extracted))["tags"] == tags
    for key in FIELDS:
        (directory / key).write_text("")
    run(helper, "write", output, directory, "remove", "unused")
    extracted.unlink()
    assert all(value == "" for value in json.loads(run(helper, "read", output, extracted))["tags"].values())
    assert not extracted.exists()
    assert original.read_bytes() == source_bytes
    assert hashlib.sha256(pcm(output)).digest() == audio_hash


def test_desktop_fingerprint_matches_ffmpeg(helper, tmp_path):
    path = tmp_path / "pcm.raw"
    subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=12", "-ar", "44100", "-ac", "1", "-f", "s16le", str(path)], check=True)
    fingerprint = run(helper, "fingerprint", path)
    assert len(fingerprint) > 8
    # Gyan essentials decodes all supported formats but omits the optional
    # Chromaprint muxer. The native helper contains its own Chromaprint library.
    muxers = subprocess.check_output(["ffmpeg", "-hide_banner", "-muxers"], text=True)
    if "chromaprint" in muxers:
        expected = subprocess.check_output(["ffmpeg", "-nostdin", "-v", "error", "-f", "s16le", "-ar", "44100", "-ac", "1", "-i", str(path), "-f", "chromaprint", "-fp_format", "base64", "-"], text=True).strip()
        assert fingerprint == expected
    assert run(helper, "version") == "resonance-desktop/1"


def test_short_fingerprint_is_reported_as_failure(helper, tmp_path):
    path = tmp_path / "short.pcm"
    path.write_bytes(b"\0\0")
    response = subprocess.run([helper, "fingerprint", str(path)], capture_output=True)
    assert response.returncode != 0
    assert b"Not enough decodable audio" in response.stderr
