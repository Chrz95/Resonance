from uuid import uuid4
import time

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models import AvailabilityRequest
from app.providers import Providers


@pytest.fixture
def service(monkeypatch):
    for name in ("ALL_PROXY", "all_proxy", "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("RESONANCE_TOKEN", "test-token")
    monkeypatch.setenv("MUSIC_USER_AGENT", "ResonanceTests/1.2 (test@example.org)")
    with TestClient(app, headers={"Authorization": "Bearer test-token"}) as client:
        yield client, app.state.providers


@pytest.mark.parametrize(("lyric_payload", "lyric_status", "cover_status", "expected_lyrics", "expected_cover"), [
    ({"plainLyrics": "Some lyrics"}, 200, 200, True, True),
    ({"syncedLyrics": "[00:01] Timed lyrics"}, 200, 404, True, False),
    ({"plainLyrics": "  ", "syncedLyrics": None}, 200, 200, False, True),
    ({"instrumental": True}, 200, 404, False, False),
    ({}, 404, 404, False, False),
    ({}, 503, 200, None, True),
    ({"plainLyrics": "Text"}, 200, 503, True, None),
])
def test_availability_api(service, samples, lyric_payload, lyric_status, cover_status, expected_lyrics, expected_cover):
    client, providers = service
    release = str(uuid4())
    calls = []

    def handler(request):
        calls.append(request)
        if request.url.host == "lrclib.net":
            assert request.url.params["duration"] == "199"
            assert request.url.params["album_name"] == "Chosen release"
            return httpx.Response(lyric_status, json=lyric_payload)
        assert request.method == "HEAD"  # Do not download 24 full covers.
        assert request.url.path == f"/release/{release}/front-500"
        return httpx.Response(cover_status, headers={"Content-Type": "image/jpeg"})

    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    response = client.post(f"/tracks/{track['id']}/availability", json={
        "title": "Song", "artist": "Artist", "album": "Chosen release", "release_id": release, "duration": 199,
    })
    assert response.status_code == 200, response.text
    result = response.json()
    assert result["has_lyrics"] is expected_lyrics
    assert result["has_cover"] is expected_cover
    assert result["instrumental"] is bool(lyric_payload.get("instrumental"))
    assert len(calls) == 2


def test_availability_requires_release_for_cover_and_title_artist_for_lyrics(service, samples):
    client, providers = service
    def handler(request):
        pytest.fail("No remote query should be made without candidate identity.")
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    result = client.post(f"/tracks/{track['id']}/availability", json={}).json()
    assert result["has_lyrics"] is None
    assert result["has_cover"] is False


def test_availability_cached_and_release_specific(service, samples):
    client, providers = service
    present, absent = str(uuid4()), str(uuid4())
    calls = []
    def handler(request):
        calls.append(request)
        if request.url.host == "lrclib.net":
            return httpx.Response(200, json={"plainLyrics": "Text"})
        return httpx.Response(200 if present in request.url.path else 404, headers={"Content-Type": "image/jpeg"})
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    route = f"/tracks/{track['id']}/availability"
    body = {"title": "Song", "artist": "Artist", "release_id": present}
    assert client.post(route, json=body).json()["has_cover"] is True
    assert client.post(route, json=body).json()["has_cover"] is True
    assert len(calls) == 2
    assert client.post(route, json={**body, "release_id": absent}).json()["has_cover"] is False
    assert len(calls) == 3


def test_availability_errors_are_unknown_and_other_side_is_still_checked(service, samples):
    client, providers = service
    def handler(request):
        if request.url.host == "lrclib.net":
            raise httpx.ConnectError("offline", request=request)
        return httpx.Response(200, headers={"Content-Type": "text/html"})
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    response = client.post(f"/tracks/{track['id']}/availability", json={"title": "Song", "artist": "Artist", "release_id": str(uuid4())})
    assert response.status_code == 200
    assert response.json()["has_lyrics"] is None
    assert response.json()["has_cover"] is None
    assert len(response.json()["warnings"]) == 2


def test_cover_redirects_are_followed_and_rate_limit_remains_unknown(service, samples):
    client, providers = service
    present, limited = str(uuid4()), str(uuid4())
    def handler(request):
        if request.url.host == "lrclib.net":
            return httpx.Response(404)
        if request.url.host == "archive.org":
            assert request.method == "HEAD"
            return httpx.Response(200, headers={"Content-Type": "image/png"})
        if present in request.url.path:
            return httpx.Response(307, headers={"Location": "https://archive.org/cover.png"})
        return httpx.Response(429, headers={"Retry-After": "120"})
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler), follow_redirects=True)
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    route = f"/tracks/{track['id']}/availability"
    body = {"title": "Song", "artist": "Artist", "release_id": present}
    assert client.post(route, json=body).json()["has_cover"] is True
    assert client.post(route, json={**body, "release_id": limited}).json()["has_cover"] is None
    assert providers.next_request["coverartarchive.org"] > time.monotonic() + 110


def test_availability_validation_and_auth(service, samples):
    client, _ = service
    track = client.post("/tracks", files={"file": ("song.flac", samples["flac"].read_bytes())}).json()
    route = f"/tracks/{track['id']}/availability"
    assert client.post(route, json={"release_id": "../arbitrary-url"}).status_code == 422
    assert client.post(route, json={}, headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.post(f"/tracks/{uuid4()}/availability", json={}).status_code == 404
