"""Prepare the checksum-pinned FFmpeg decoder for the Windows build bundle."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import shutil
import ssl
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

VERSION = "9.0.2"
ARCHIVE = f"ffmpeg-{VERSION}-essentials_build.zip"
URL = f"https://www.gyan.dev/ffmpeg/builds/packages/{ARCHIVE}"
GITHUB_URL = f"https://github.com/GyanD/codexffmpeg/releases/download/{VERSION}/{ARCHIVE}"
DOWNLOAD_URLS = (GITHUB_URL, URL)
SHA256 = "60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba"


class DownloadError(RuntimeError):
    """Actionable build-time download failure; never disables TLS verification."""


def archive_digest(path: Path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download_archive(archive: Path, *, ca_bundle: Path | None = None):
    context = ssl.create_default_context()
    if ca_bundle is not None:
        try:
            # Add an explicitly supplied organizational CA to normal OS trust.
            context.load_verify_locations(cafile=str(ca_bundle))
        except (OSError, ssl.SSLError) as exc:
            raise DownloadError(f"Cannot load --ca-bundle {ca_bundle}: {exc}") from exc
    errors = []
    for url in DOWNLOAD_URLS:
        partial = archive.with_suffix(".part")
        request = urllib.request.Request(url, headers={"User-Agent": "Resonance-build/1.6"})
        print(f"Downloading pinned FFmpeg {VERSION} from {urllib.parse.urlsplit(url).hostname}…")
        try:
            with urllib.request.urlopen(request, timeout=60, context=context) as response, partial.open("wb") as output:
                total = 0
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > 300 * 1024 * 1024:
                        raise DownloadError("FFmpeg download exceeded the expected size limit.")
                    output.write(chunk)
            if archive_digest(partial) != SHA256:
                raise DownloadError("FFmpeg checksum mismatch; downloaded bytes were rejected.")
            # A failed or interrupted transfer never becomes a reusable cache entry.
            partial.replace(archive)
            return
        except (OSError, urllib.error.URLError, DownloadError) as exc:
            errors.append(f"{urllib.parse.urlsplit(url).hostname}: {exc}")
            print("Download failed; trying the next verified HTTPS source.")
        finally:
            partial.unlink(missing_ok=True)
    raise DownloadError(
        "Could not download the pinned FFmpeg archive from either HTTPS source.\n"
        + "\n".join(errors)
        + "\nIf certificate verification failed, check the Windows date/time and certificate trust. "
          "For an organization proxy, use --ca-bundle with its trusted PEM certificate. "
          "You can also download the exact archive in a browser from\n"
        + GITHUB_URL
        + "\nand rerun: python tools/bootstrap_client.py --ffmpeg-archive \"PATH_TO_ZIP\". "
          "Its SHA-256 will still be verified. TLS verification has not been disabled."
    )


def extract_tools(archive: Path, destination: Path, expected_digest=SHA256):
    digest = archive_digest(archive)
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
            "download_sources": list(DOWNLOAD_URLS),
            "build_project": "https://github.com/GyanD/codexffmpeg",
            "upstream_source": "https://github.com/FFmpeg/FFmpeg/tree/946fcce07b",
            "license": "GPL-3.0-or-later (Gyan essentials build)",
        }, indent=2))
        previous = Path(temporary) / "previous"
        if destination.exists():
            destination.replace(previous)
        try:
            stage.replace(destination)
        except BaseException:
            if previous.exists():
                previous.replace(destination)
            raise


def prepare_windows_tools(client: Path, *, local_archive: Path | None = None, ca_bundle: Path | None = None):
    cache = client / "windows_tools" / "cache"
    cache.mkdir(parents=True, exist_ok=True)
    archive = local_archive if local_archive is not None else cache / ARCHIVE
    if local_archive is not None:
        if not archive.is_file() or archive_digest(archive) != SHA256:
            raise DownloadError(f"--ffmpeg-archive must be the unmodified {ARCHIVE}. Required SHA-256: {SHA256}. No tools were installed.")
    else:
        if archive.exists() and archive_digest(archive) != SHA256:
            print("Cached FFmpeg archive is incomplete or has changed; downloading it again.")
            archive.unlink()
        if not archive.exists():
            download_archive(archive, ca_bundle=ca_bundle)
    extract_tools(archive, client / "windows_tools" / "ffmpeg", expected_digest=SHA256)
    print(f"Prepared FFmpeg {VERSION} for the standalone Windows bundle.")
