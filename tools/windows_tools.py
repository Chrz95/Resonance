"""Prepare the checksum-pinned FFmpeg decoder for the Windows build bundle."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import shutil
import tempfile
import urllib.request
import zipfile

VERSION = "9.0.2"
ARCHIVE = f"ffmpeg-{VERSION}-essentials_build.zip"
URL = f"https://www.gyan.dev/ffmpeg/builds/packages/{ARCHIVE}"
SHA256 = "60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba"


def extract_tools(archive: Path, destination: Path, expected_digest=SHA256):
    with archive.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != expected_digest:
        raise RuntimeError("FFmpeg checksum mismatch. No tools were installed.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        stage = Path(temporary) / "tools"
        stage.mkdir()
        found = False
        with zipfile.ZipFile(archive) as source:
            if sum(item.file_size for item in source.infolist()) > 2 * 1024**3:
                raise RuntimeError("FFmpeg archive is too large.")
            for item in source.infolist():
                path = PurePosixPath(item.filename)
                if path.is_absolute() or ".." in path.parts or "\\" in item.filename:
                    raise RuntimeError("Invalid FFmpeg archive path.")
                if item.is_dir() or len(path.parts) < 2:
                    continue
                relative = PurePosixPath(*path.parts[1:])
                if str(relative) == "bin/ffmpeg.exe":
                    target = stage / "ffmpeg.exe"
                    found = True
                elif relative.suffix.lower() not in {".exe", ".dll"}:
                    target = stage / "licenses" / Path(*relative.parts)
                else:
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with source.open(item) as stream, target.open("wb") as output:
                    shutil.copyfileobj(stream, output)
        if not found:
            raise RuntimeError("FFmpeg archive has no decoder executable.")
        (stage / "licenses").mkdir(exist_ok=True)
        (stage / "licenses" / "RESONANCE_FFMPEG.json").write_text(json.dumps({
            "version": VERSION, "url": URL, "archive_sha256": expected_digest,
            "build_project": "https://github.com/GyanD/codexffmpeg",
            "upstream_source": "https://github.com/FFmpeg/FFmpeg/tree/946fcce07b",
            "license": "GPL-3.0-or-later (Gyan essentials build)",
        }, indent=2))
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(stage, destination)


def prepare_windows_tools(client: Path):
    cache = client / "windows_tools" / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / ARCHIVE
    if not archive.exists():
        partial = archive.with_suffix(".part")
        request = urllib.request.Request(URL, headers={"User-Agent": "Resonance-build/1.5"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response, partial.open("wb") as output:
                shutil.copyfileobj(response, output)
            partial.replace(archive)
        finally:
            partial.unlink(missing_ok=True)
    extract_tools(archive, client / "windows_tools" / "ffmpeg")
    print(f"Prepared FFmpeg {VERSION} for the standalone Windows bundle.")
