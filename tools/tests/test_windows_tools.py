import hashlib
import importlib.util
from pathlib import Path
import zipfile

import pytest


def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parents[1] / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tools = load("windows_tools")
audio = load("windows_audio")


def archive(tmp_path, extra=None):
    file = tmp_path / "ffmpeg.zip"
    with zipfile.ZipFile(file, "w") as output:
        output.writestr("ffmpeg/bin/ffmpeg.exe", b"decoder fixture")
        output.writestr("ffmpeg/bin/ffprobe.exe", b"unneeded")
        output.writestr("ffmpeg/LICENSE", "license fixture")
        output.writestr("ffmpeg/doc/index.html", "documentation")
        if extra:
            output.writestr(extra, b"bad")
    return file, hashlib.sha256(file.read_bytes()).hexdigest()


def test_extracts_only_decoder_and_preserves_notices(tmp_path):
    file, digest = archive(tmp_path)
    destination = tmp_path / "tools"
    tools.extract_tools(file, destination, digest)
    assert (destination / "ffmpeg.exe").read_bytes() == b"decoder fixture"
    assert not (destination / "ffprobe.exe").exists()
    assert (destination / "licenses" / "LICENSE").read_text() == "license fixture"
    assert (destination / "licenses" / "doc" / "index.html").exists()
    assert digest in (destination / "licenses" / "RESONANCE_FFMPEG.json").read_text()


def test_checksum_failure_preserves_installed_tools(tmp_path):
    file, _ = archive(tmp_path)
    destination = tmp_path / "tools"
    destination.mkdir()
    (destination / "ffmpeg.exe").write_bytes(b"previous")
    with pytest.raises(RuntimeError, match="checksum mismatch"):
        tools.extract_tools(file, destination, "0" * 64)
    assert (destination / "ffmpeg.exe").read_bytes() == b"previous"


@pytest.mark.parametrize("path", ["ffmpeg/../../outside", "/absolute/file", "ffmpeg/..\\outside"])
def test_rejects_unsafe_archive_paths(tmp_path, path):
    file, digest = archive(tmp_path, path)
    with pytest.raises(RuntimeError, match="archive path"):
        tools.extract_tools(file, tmp_path / "tools", digest)
    assert not (tmp_path / "outside").exists()


def test_build_rules_include_helper_and_decoder_once(tmp_path):
    windows = tmp_path / "windows"
    windows.mkdir()
    file = windows / "CMakeLists.txt"
    file.write_text("project(runner)\n")
    audio.install_windows_audio(tmp_path)
    initial = file.read_text()
    audio.install_windows_audio(tmp_path)
    assert file.read_text() == initial
    assert "add_dependencies(${BINARY_NAME} resonance_desktop)" in initial
    assert "windows_tools/ffmpeg/" in initial
    assert 'DESTINATION "${CMAKE_INSTALL_PREFIX}/tools"' in initial
