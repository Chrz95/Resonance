import hashlib
import subprocess

import pytest

from app import audio
from app.models import Tags


def pcm_hash(path):
    # Decode only audio. This catches accidental transcoding or damage from tag edits.
    return hashlib.sha256(subprocess.check_output(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path),
        "-map", "0:a:0", "-f", "s16le", "-"])).hexdigest()


@pytest.mark.parametrize("ext", ["mp3", "flac", "m4a", "ogg", "opus"])
def test_round_trip_and_unchanged_audio(ext, samples, cover, tmp_path):
    original = samples[ext]
    original_bytes = original.read_bytes()
    output = tmp_path / f"tagged.{ext}"
    tags = Tags(title="Δοκιμή — 音楽", artist="An Artist", album="An Album", album_artist="Various Artists",
                date="2024-03-02", genre="Electronic", track_number="2/10", disc_number="1/2",
                recording_id="ab4d36ac-ed70-4e6b-8528-8012ab81dd42", release_id="1211553d-7e94-46af-a13c-146f67f534d5",
                lyrics="First line\nSecond line\n", synced_lyrics="[00:01.00] First line\n[00:02.00] Second line")
    audio.write_copy(original, output, tags, "replace", cover)
    read, duration, embedded = audio.read(output)
    assert read == tags
    assert 7.8 < duration < 8.2
    assert embedded and embedded.startswith(b"\xff\xd8")
    assert original.read_bytes() == original_bytes
    assert pcm_hash(original) == pcm_hash(output)
    second = tmp_path / f"kept.{ext}"
    audio.write_copy(output, second, tags.model_copy(update={"title": "Changed"}), "keep", None)
    assert audio.read(second)[2] == embedded
    removed = tmp_path / f"removed.{ext}"
    audio.write_copy(second, removed, Tags(), "remove", None)
    assert audio.read(removed)[0] == Tags()
    assert audio.read(removed)[2] is None


def test_rejects_bad_cover(samples, tmp_path):
    with pytest.raises(ValueError, match="valid image"):
        audio.write_copy(samples["mp3"], tmp_path / "out.mp3", Tags(), "replace", b"not an image")


def test_rejects_mismatched_container(samples, tmp_path):
    path = tmp_path / "fake.flac"
    path.write_bytes(samples["mp3"].read_bytes())
    with pytest.raises(ValueError, match="container"):
        audio.read(path)
