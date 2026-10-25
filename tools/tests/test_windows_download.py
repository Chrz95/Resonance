"""TLS failures are handled by verified mirror fallback, never by bypassing TLS."""
import hashlib
import importlib.util
import io
from pathlib import Path
import ssl
import urllib.error
import zipfile

import pytest


spec = importlib.util.spec_from_file_location('download_tools', Path(__file__).resolve().parents[1] / 'windows_tools.py')
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


@pytest.fixture
def payload(monkeypatch):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as z:
        z.writestr('ffmpeg/bin/ffmpeg.exe', b'fixture executable')
        z.writestr('ffmpeg/LICENSE', 'fixture license')
    content = stream.getvalue()
    monkeypatch.setattr(tools, 'SHA256', hashlib.sha256(content).hexdigest())
    return content


def test_expired_certificate_falls_back_with_verification_enabled(tmp_path, monkeypatch, payload):
    calls = []

    def open_url(request, *, timeout, context):
        calls.append(request.full_url)
        assert context.verify_mode == ssl.CERT_REQUIRED
        assert context.check_hostname is True
        assert timeout == 60
        if len(calls) == 1:
            raise urllib.error.URLError(ssl.SSLCertVerificationError(1, 'certificate has expired'))
        return io.BytesIO(payload)

    monkeypatch.setattr(tools.urllib.request, 'urlopen', open_url)
    archive = tmp_path / tools.ARCHIVE
    tools.download_archive(archive)
    assert calls == list(tools.DOWNLOAD_URLS)
    assert archive.read_bytes() == payload
    assert not archive.with_suffix('.part').exists()


def test_all_sources_fail_with_actionable_message_and_no_partial_cache(tmp_path, monkeypatch):
    def expired(*args, **kwargs):
        raise urllib.error.URLError(ssl.SSLCertVerificationError(1, 'certificate has expired'))

    monkeypatch.setattr(tools.urllib.request, 'urlopen', expired)
    archive = tmp_path / tools.ARCHIVE
    with pytest.raises(tools.DownloadError) as caught:
        tools.download_archive(archive)
    message = str(caught.value)
    assert 'date/time' in message and '--ffmpeg-archive' in message and '--ca-bundle' in message
    assert 'certificate has expired' in message
    assert not archive.exists() and not archive.with_suffix('.part').exists()


def test_wrong_checksum_on_first_source_is_never_cached(tmp_path, monkeypatch, payload):
    calls = []

    def response(request, **kwargs):
        calls.append(request.full_url)
        return io.BytesIO(b'invalid response' if len(calls) == 1 else payload)

    monkeypatch.setattr(tools.urllib.request, 'urlopen', response)
    archive = tmp_path / tools.ARCHIVE
    tools.download_archive(archive)
    assert len(calls) == 2
    assert archive.read_bytes() == payload


def test_local_archive_does_not_access_network_and_installs_verified_bytes(tmp_path, monkeypatch, payload):
    archive = tmp_path / 'offline.zip'
    archive.write_bytes(payload)
    monkeypatch.setattr(tools.urllib.request, 'urlopen', lambda *a, **k: pytest.fail('Offline archive accessed the network'))
    client = tmp_path / 'client'
    tools.prepare_windows_tools(client, local_archive=archive)
    assert (client / 'windows_tools/ffmpeg/ffmpeg.exe').read_bytes() == b'fixture executable'
    assert archive.read_bytes() == payload


def test_invalid_local_archive_preserves_installed_tools(tmp_path, monkeypatch, payload):
    archive = tmp_path / 'wrong.zip'
    archive.write_bytes(b'wrong')
    destination = tmp_path / 'client/windows_tools/ffmpeg/ffmpeg.exe'
    destination.parent.mkdir(parents=True)
    destination.write_bytes(b'previous executable')
    monkeypatch.setattr(tools.urllib.request, 'urlopen', lambda *a, **k: pytest.fail('Invalid local archive accessed the network'))
    with pytest.raises(tools.DownloadError, match='Required SHA-256'):
        tools.prepare_windows_tools(tmp_path / 'client', local_archive=archive)
    assert destination.read_bytes() == b'previous executable'


def test_verified_cache_is_reused_without_https(tmp_path, monkeypatch, payload):
    client = tmp_path / 'client'
    cache = client / 'windows_tools/cache' / tools.ARCHIVE
    cache.parent.mkdir(parents=True)
    cache.write_bytes(payload)
    monkeypatch.setattr(tools.urllib.request, 'urlopen', lambda *a, **k: pytest.fail('Verified cache accessed the network'))
    tools.prepare_windows_tools(client)
    assert (client / 'windows_tools/ffmpeg/ffmpeg.exe').exists()


def test_invalid_cache_download_failure_keeps_previous_installation(tmp_path, monkeypatch, payload):
    client = tmp_path / 'client'
    cache = client / 'windows_tools/cache' / tools.ARCHIVE
    cache.parent.mkdir(parents=True)
    cache.write_bytes(b'interrupted old download')
    installed = client / 'windows_tools/ffmpeg/ffmpeg.exe'
    installed.parent.mkdir(parents=True)
    installed.write_bytes(b'previous')
    monkeypatch.setattr(tools.urllib.request, 'urlopen', lambda *a, **k: (_ for _ in ()).throw(urllib.error.URLError('unavailable')))
    with pytest.raises(tools.DownloadError):
        tools.prepare_windows_tools(client)
    assert installed.read_bytes() == b'previous'
    assert not cache.exists()


def test_additional_ca_is_loaded_without_disabling_standard_verification(tmp_path, monkeypatch, payload):
    class Context:
        verify_mode = ssl.CERT_REQUIRED
        check_hostname = True
        loaded = None

        def load_verify_locations(self, *, cafile):
            self.loaded = cafile

    context = Context()
    monkeypatch.setattr(tools.ssl, 'create_default_context', lambda: context)
    monkeypatch.setattr(tools.urllib.request, 'urlopen', lambda *a, **k: io.BytesIO(payload))
    pem = tmp_path / 'organization.pem'
    tools.download_archive(tmp_path / tools.ARCHIVE, ca_bundle=pem)
    assert context.loaded == str(pem)
    assert context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname


def test_install_failure_restores_previous_directory(tmp_path, monkeypatch, payload):
    archive = tmp_path / 'archive.zip'
    archive.write_bytes(payload)
    destination = tmp_path / 'ffmpeg'
    destination.mkdir()
    (destination / 'ffmpeg.exe').write_bytes(b'old')
    original = Path.replace

    def fail_stage(path, target):
        if path.name == 'tools':
            raise OSError('simulated installation failure')
        return original(path, target)

    monkeypatch.setattr(Path, 'replace', fail_stage)
    with pytest.raises(OSError, match='simulated'):
        tools.extract_tools(archive, destination, expected_digest=tools.SHA256)
    assert (destination / 'ffmpeg.exe').read_bytes() == b'old'


def test_bootstrap_options_are_parsed_without_running_flutter(monkeypatch):
    directory = str(Path(__file__).resolve().parents[1])
    monkeypatch.syspath_prepend(directory)
    spec = importlib.util.spec_from_file_location('bootstrap_options', Path(directory) / 'bootstrap_client.py')
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    args = bootstrap.parse_args(['--ffmpeg-archive', 'C:/downloads/file.zip', '--ca-bundle', 'C:/certs/proxy.pem'])
    assert args.ffmpeg_archive == Path('C:/downloads/file.zip')
    assert args.ca_bundle == Path('C:/certs/proxy.pem')


@pytest.fixture
def bootstrap_flow(tmp_path, monkeypatch):
    import shutil
    from types import SimpleNamespace
    directory = Path(__file__).resolve().parents[1]
    monkeypatch.syspath_prepend(str(directory))
    spec = importlib.util.spec_from_file_location('bootstrap_flow', directory / 'bootstrap_client.py')
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    client = tmp_path / 'client'
    (client / 'lib').mkdir(parents=True)
    (client / 'pubspec.yaml').write_text('version: 1.6.0+8\n', encoding='utf-8')
    (client / 'lib/main.dart').write_text('// Original 音楽 source', encoding='utf-8')
    shutil.copytree(directory.parent / 'client/platform_config', client / 'platform_config')
    monkeypatch.setattr(bootstrap, '__file__', str(tmp_path / 'tools/bootstrap_client.py'))
    monkeypatch.setattr(bootstrap, 'sys', SimpleNamespace(platform='win32'))
    monkeypatch.setattr(bootstrap.shutil, 'which', lambda _: 'flutter-fixture')
    monkeypatch.setattr(bootstrap, 'install_windows_session', lambda _: None)
    monkeypatch.setattr(bootstrap, 'install_windows_audio', lambda _: None)
    commands = []

    def run(command, **kwargs):
        commands.append(command)
        if 'create' in command:
            (client / 'android/app/src/main').mkdir(parents=True)
            (client / 'android/app/build.gradle.kts').write_text('// Generated Gradle\n')
            (client / 'lib/main.dart').write_text('// Generated counter')
            (client / 'pubspec.yaml').write_text('version: generated')

    monkeypatch.setattr(bootstrap.subprocess, 'run', run)
    return bootstrap, client, commands


def test_bootstrap_forwards_offline_and_ca_options_and_preserves_sources(bootstrap_flow, monkeypatch):
    bootstrap, client, commands = bootstrap_flow
    received = []
    monkeypatch.setattr(bootstrap, 'prepare_windows_tools', lambda path, **kwargs: received.append((path, kwargs)))
    bootstrap.main(['--ffmpeg-archive', 'download.zip', '--ca-bundle', 'organization.pem'])
    assert received == [(client, {'local_archive': Path('download.zip'), 'ca_bundle': Path('organization.pem')})]
    assert (client / 'lib/main.dart').read_text(encoding='utf-8') == '// Original 音楽 source'
    assert (client / 'pubspec.yaml').read_text() == 'version: 1.6.0+8\n'
    assert commands[-1][1:] == ['pub', 'get']


def test_bootstrap_download_error_is_concise_and_does_not_continue(bootstrap_flow, monkeypatch):
    bootstrap, client, commands = bootstrap_flow

    def unavailable(*args, **kwargs):
        raise bootstrap.DownloadError('certificate has expired; use --ffmpeg-archive')

    monkeypatch.setattr(bootstrap, 'prepare_windows_tools', unavailable)
    with pytest.raises(SystemExit, match='Windows audio setup failed') as caught:
        bootstrap.main([])
    assert '--ffmpeg-archive' in str(caught.value)
    assert not any(command[1:] == ['pub', 'get'] for command in commands)
    assert (client / 'lib/main.dart').read_text(encoding='utf-8') == '// Original 音楽 source'
