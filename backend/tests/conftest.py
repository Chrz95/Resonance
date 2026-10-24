import io
import subprocess
from pathlib import Path

import pytest
from PIL import Image


@pytest.fixture(scope="session")
def samples(tmp_path_factory):
    folder = tmp_path_factory.mktemp("audio")
    result = {}
    codecs = {"mp3": "libmp3lame", "flac": "flac", "m4a": "aac", "ogg": "libvorbis", "opus": "libopus"}
    for ext, codec in codecs.items():
        path = folder / f"sample.{ext}"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=8",
                        "-c:a", codec, str(path)], check=True)
        result[ext] = path
    return result


@pytest.fixture
def cover():
    out = io.BytesIO()
    Image.new("RGB", (64, 64), (120, 80, 220)).save(out, format="PNG")
    return out.getvalue()
