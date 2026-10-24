import time
from uuid import uuid4

import httpx
import pytest

from app.models import Tags
from app.providers import ProviderError, Providers, candidates, normalize_date


@pytest.mark.parametrize(("raw", "expected"), [
    ({"day": 19, "month": 7, "year": 2017}, "2017-07-19"),
    ({"year": 2017}, "2017"),
    ({"year": 2017, "month": 7}, "2017-07"),
    ({"year": 2017, "month": 0, "day": 0}, "2017"),
    ({"year": 2017, "month": 2, "day": 29}, "2017-02"),
    ({"year": 2024, "month": 2, "day": 29}, "2024-02-29"),
    ({"year": "2017", "month": "7", "day": "19"}, "2017-07-19"),
    ({"year": True}, ""),
    ({"year": 10000}, ""),
    ({"month": 7, "day": 19}, ""),
    ({}, ""), (None, ""), ([], ""), (2017, ""),
    ("2017-07-19", "2017-07-19"), ("2017-07", "2017-07"), ("2017", "2017"),
])
def test_provider_date_formats(raw, expected):
    assert normalize_date(raw) == expected


def test_acoustid_candidates_accept_structured_and_null_dates():
    result = candidates([{
        "id": "ab4d36ac-ed70-4e6b-8528-8012ab81dd42", "title": "Song",
        "artists": [{"name": "Artist"}], "releases": [
            {"id": str(uuid4()), "date": {"day": 19, "month": 7, "year": 2017}},
            {"id": str(uuid4()), "date": {"year": 2017}},
            {"id": str(uuid4()), "date": None},
        ],
    }], "fingerprint", .98)
    assert [c.date for c in result] == ["2017-07-19", "2017", ""]


@pytest.fixture
def provider(monkeypatch):
    for name in ("ALL_PROXY", "all_proxy", "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("MUSIC_USER_AGENT", "ResonanceTests/1.0 (test@example.org)")
    return Providers()


@pytest.mark.asyncio
async def test_missing_lyrics_and_art_keep_existing_content(provider):
    recording, release = str(uuid4()), str(uuid4())

    def handler(request):
        if request.url.path == f"/ws/2/recording/{recording}":
            return httpx.Response(200, json={"id": recording, "title": "Found title", "artist-credit": [{"name": "Artist"}]})
        if request.url.path == f"/ws/2/release/{release}":
            return httpx.Response(200, json={"id": release, "title": "Album", "media": [
                {"position": 1, "tracks": [{"position": 1, "recording": {"id": recording}}]}]})
        return httpx.Response(404)

    await provider.client.aclose()
    provider.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        result = await provider.enrich(recording, release, Tags(lyrics="Keep these lyrics", synced_lyrics="[00:00] Keep these lyrics"), 200)
        assert result["tags"].lyrics == "Keep these lyrics"
        assert result["tags"].synced_lyrics == "[00:00] Keep these lyrics"
        assert result["cover_base64"] is None
        assert len(result["warnings"]) == 2
    finally:
        await provider.close()


@pytest.mark.asyncio
async def test_rate_limit_respects_retry_after(provider):
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(429, headers={"Retry-After": "120"})

    await provider.client.aclose()
    provider.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        with pytest.raises(ProviderError, match="120 seconds"):
            await provider.request_json("https://lrclib.net/api/get")
        assert provider.next_request["lrclib.net"] > time.monotonic() + 110
        with pytest.raises(ProviderError, match="cooldown"):
            await provider.request_json("https://lrclib.net/api/get")
        assert len(calls) == 1
    finally:
        await provider.close()


@pytest.mark.asyncio
async def test_lookup_cache_avoids_duplicate_requests(provider):
    calls = []

    def handler(request):
        calls.append(request)
        return httpx.Response(200, json={"recordings": []})

    await provider.client.aclose()
    provider.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    try:
        assert await provider.search("Example Artist") == []
        assert await provider.search("Example Artist") == []
        assert len(calls) == 1
    finally:
        await provider.close()


@pytest.mark.asyncio
async def test_no_musicbrainz_calls_without_contact_user_agent(provider):
    provider.user_agent = ""
    try:
        with pytest.raises(ProviderError, match="MUSIC_USER_AGENT"):
            await provider.search("Example Artist")
    finally:
        await provider.close()
