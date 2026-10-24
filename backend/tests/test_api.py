import base64
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app import audio
from app.main import app
from app.models import Tags


@pytest.fixture
def client(monkeypatch):
    # Unit tests never use the host's network proxy or public APIs.
    for variable in ("ALL_PROXY", "all_proxy", "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"):
        monkeypatch.delenv(variable, raising=False)
    monkeypatch.setenv("RESONANCE_TOKEN", "test-token")
    monkeypatch.setenv("MUSIC_USER_AGENT", "ResonanceTests/1.0 (test@example.org)")
    monkeypatch.delenv("ACOUSTID_API_KEY", raising=False)
    with TestClient(app, headers={"Authorization": "Bearer test-token"}) as client:
        yield client


def test_auth(client):
    assert client.get("/health").status_code == 200
    assert client.get("/health", headers={"Authorization": "Bearer wrong"}).status_code == 401


def test_upload_export_delete(client, samples, cover, tmp_path):
    original = samples["mp3"].read_bytes()
    response = client.post("/tracks", files={"file": ("song.mp3", original, "audio/mpeg")})
    assert response.status_code == 200, response.text
    track = response.json()
    assert track["duration"] > 7.8
    response = client.post(f"/tracks/{track['id']}/export", json={
        "tags": {"title": "New name", "lyrics": "A lyric line"}, "cover_action": "replace",
        "cover_base64": base64.b64encode(cover).decode(),
    })
    assert response.status_code == 200, response.text
    exported = tmp_path / "export.mp3"
    exported.write_bytes(response.content)
    assert audio.read(exported)[0].title == "New name"
    assert audio.read(exported)[0].lyrics == "A lyric line"
    assert audio.read(exported)[2]
    assert samples["mp3"].read_bytes() == original
    assert client.delete(f"/tracks/{track['id']}").status_code == 200
    assert client.post(f"/tracks/{track['id']}/identify").status_code == 404


def test_validation(client, samples):
    assert client.post("/tracks", files={"file": ("bad.mp3", b"bogus")}).status_code == 422
    assert client.post("/tracks", files={"file": ("song.exe", b"bogus")}).status_code == 415
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    assert client.post(f"/tracks/{track['id']}/export", json={"tags": {"track_number": "wrong"}}).status_code == 422
    assert client.post(f"/tracks/{track['id']}/export", json={"tags": {}, "cover_action": "replace", "cover_base64": "bad!"}).status_code == 422
    assert client.post(f"/tracks/{uuid4()}/export", json={"tags": {}}).status_code == 404
    assert client.post(f"/tracks/{track['id']}/enrich", json={"recording_id": "../etc/passwd"}).status_code == 422


def test_fingerprint_without_key(client, samples):
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    result = client.post(f"/tracks/{track['id']}/identify")
    assert result.status_code == 200, result.text
    data = result.json()
    assert len(data["signature"]) == 64
    assert data["candidates"] == []
    assert "ACOUSTID_API_KEY" in data["warnings"][0]


def test_mocked_services_end_to_end(client, samples, cover, monkeypatch):
    recording = "ab4d36ac-ed70-4e6b-8528-8012ab81dd42"
    release = "1211553d-7e94-46af-a13c-146f67f534d5"
    credit = [{"name": "Example Artist", "artist": {"id": str(uuid4()), "name": "Example Artist"}}]
    calls = []

    def handler(request):
        calls.append(str(request.url))
        if request.url.host == "api.acoustid.org":
            assert b"fingerprint=" in request.content
            return httpx.Response(200, json={"status": "ok", "results": [{"score": .98, "recordings": [
                {"id": recording, "title": "Example Song", "artists": [{"name": "Example Artist"}],
                 "releases": [{"id": release, "title": "Example Album", "date": {"day": 19, "month": 7, "year": 2017}}]}]}]})
        if request.url.host == "lrclib.net":
            return httpx.Response(200, json={"id": 123, "plainLyrics": "A line", "syncedLyrics": "[00:01] A line", "instrumental": False})
        if request.url.host == "coverartarchive.org":
            return httpx.Response(200, content=cover)
        if request.url.path == "/ws/2/recording/":
            return httpx.Response(200, json={"recordings": [{"id": recording, "title": "Example Song", "score": 99,
                "artist-credit": credit, "releases": [{"id": release, "title": "Example Album"}]}]})
        if request.url.path == f"/ws/2/recording/{recording}":
            return httpx.Response(200, json={"id": recording, "title": "Example Song", "artist-credit": credit})
        if request.url.path == f"/ws/2/release/{release}":
            return httpx.Response(200, json={"id": release, "title": "Example Album", "date": "2020-01-01", "artist-credit": credit,
                "media": [{"position": 1, "track-count": 2, "tracks": [{"position": 2, "recording": {"id": recording}}]}]})
        return httpx.Response(404)

    service = app.state.providers
    service.key = "free-key"
    service.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    response = client.post(f"/tracks/{track['id']}/identify")
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["candidates"][0]["score"] == .98
    assert result["candidates"][0]["date"] == "2017-07-19"
    assert client.get("/search", params={"q": "Example Song"}).json()["candidates"][0]["source"] == "metadata"
    result = client.post(f"/tracks/{track['id']}/enrich", json={"recording_id": recording, "release_id": release,
        "current_tags": {"genre": "Keep me"}})
    assert result.status_code == 200, result.text
    data = result.json()
    assert data["tags"]["title"] == "Example Song"
    assert data["tags"]["album"] == "Example Album"
    assert data["tags"]["track_number"] == "2/2"
    assert data["tags"]["genre"] == "Keep me"
    assert data["tags"]["lyrics"] == "A line"
    assert data["cover_base64"]
    assert data["warnings"] == []
    assert any("lrclib.net" in url for url in calls)
    assert any("coverartarchive.org" in url for url in calls)
