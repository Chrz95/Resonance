import base64
from uuid import uuid4

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.alternatives import artwork_url


@pytest.fixture
def setup(monkeypatch, samples):
    for name in ('ALL_PROXY', 'all_proxy', 'HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY', 'http_proxy'):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv('RESONANCE_TOKEN', 'test-token')
    monkeypatch.setenv('MUSIC_USER_AGENT', 'ResonanceTests/1.3 (test@example.org)')
    with TestClient(app, headers={'Authorization': 'Bearer test-token'}) as client:
        track = client.post('/tracks', files={'file': ('song.flac', samples['flac'].read_bytes())}).json()
        yield client, app.state.providers, f'/tracks/{track["id"]}'


@pytest.mark.parametrize('url', [
    'http://is1-ssl.mzstatic.com/cover.jpg', 'https://localhost/cover.jpg',
    'https://evil-mzstatic.com/cover.jpg', 'https://mzstatic.com.evil.test/cover.jpg',
    'https://user:pass@is1-ssl.mzstatic.com/cover.jpg', 'https://is1-ssl.mzstatic.com:8888/image.jpg',
    None, {'url': 'https://is1-ssl.mzstatic.com/image.jpg'},
])
def test_untrusted_artwork_urls_rejected(url):
    assert artwork_url(url) is None


def test_covers_filtered_deduplicated_and_preferred_album_first(setup):
    client, providers, route = setup
    def handler(request):
        assert request.url.host == 'itunes.apple.com'
        assert request.url.params['entity'] == 'song'
        def result(id, artist='Artist', album='Other album', image='https://is1-ssl.mzstatic.com/100x100bb.jpg'):
            return {'collectionId': id, 'artistName': artist, 'collectionName': album, 'trackName': 'Song', 'artworkUrl100': image}
        return httpx.Response(200, json={'results': [result(1), result(1), result(2, album='Chosen album'),
            result(3, artist='Wrong artist'), result(4, image='http://127.0.0.1/private') ]})
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    result = client.post(route + '/alternatives', json={'kind': 'cover', 'title': 'Song', 'artist': 'Artist', 'album': 'Chosen album'})
    assert result.status_code == 200, result.text
    options = result.json()['options']
    assert [o['collection_id'] for o in options] == [2, 1]


def test_alternate_lyrics_survive_one_provider_failure_and_filter_versions(setup):
    client, providers, route = setup
    def handler(request):
        if request.url.host == 'api.lyrics.ovh':
            return httpx.Response(503)
        return httpx.Response(200, json=[
            {'id': 1, 'artistName': 'Artist', 'trackName': 'Song', 'albumName': 'Chosen album', 'syncedLyrics': '[00:01] Text'},
            {'id': 2, 'artistName': 'Another artist', 'trackName': 'Song', 'plainLyrics': 'Wrong'},
            {'id': 3, 'artistName': 'Artist', 'trackName': 'Different song', 'plainLyrics': 'Wrong'},
            {'id': 4, 'artistName': 'Artist', 'trackName': 'Song', 'instrumental': True},
        ])
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    result = client.post(route + '/alternatives', json={'kind': 'lyrics', 'title': 'Song', 'artist': 'Artist', 'album': 'Chosen album'})
    assert result.status_code == 200, result.text
    assert len(result.json()['options']) == 1
    assert result.json()['options'][0]['synced_lyrics'] == '[00:01] Text'
    assert len(result.json()['warnings']) == 1


def test_lyrics_ovh_preserves_unicode_and_path_components(setup):
    client, providers, route = setup
    def handler(request):
        if request.url.host == 'lrclib.net': return httpx.Response(200, json=[])
        assert b'AC%2FDC' in request.url.raw_path
        return httpx.Response(200, json={'lyrics': 'Manual \u0395\u03bb\u03bb\u03b7\u03bd\u03b9\u03ba\u03ac\nSecond line'})
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    result = client.post(route + '/alternatives', json={'kind': 'lyrics', 'title': 'Song', 'artist': 'AC/DC'})
    assert result.status_code == 200
    assert result.json()['options'][0]['source'] == 'lyrics.ovh'
    assert 'Ελληνικά' in result.json()['options'][0]['lyrics']


def test_alternate_cover_download_uses_album_lookup_fallback_and_normalizes(setup, cover):
    client, providers, route = setup
    requests = []
    def handler(request):
        requests.append(str(request.url))
        if request.url.host == 'itunes.apple.com':
            return httpx.Response(200, json={'results': [{'collectionId': 123, 'artworkUrl100': 'https://is1-ssl.mzstatic.com/100x100bb.jpg'}]})
        if '600x600' in request.url.path: return httpx.Response(404)
        return httpx.Response(200, content=cover, headers={'content-type': 'image/png'})
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    result = client.post(route + '/alternative-cover', json={'collection_id': 123})
    assert result.status_code == 200, result.text
    assert base64.b64decode(result.json()['cover_base64']).startswith(b'\xff\xd8')
    assert len(requests) == 3


def test_cover_redirect_cannot_reach_local_services(setup):
    client, providers, route = setup
    requests = []
    def handler(request):
        requests.append(request.url.host)
        if request.url.host == 'itunes.apple.com':
            return httpx.Response(200, json={'results': [{'collectionId': 1, 'artworkUrl100': 'https://is1-ssl.mzstatic.com/100x100bb.jpg'}]})
        assert request.url.host == 'is1-ssl.mzstatic.com'
        return httpx.Response(307, headers={'Location': 'http://127.0.0.1/private'})
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(handler), follow_redirects=True)
    result = client.post(route + '/alternative-cover', json={'collection_id': 1})
    assert result.status_code == 502
    assert requests == ['itunes.apple.com', 'is1-ssl.mzstatic.com']


@pytest.mark.parametrize('payload', [None, [], {'results': None}])
def test_invalid_search_response_is_handled(setup, payload):
    client, providers, route = setup
    providers.client = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json=payload)))
    result = client.post(route + '/alternatives', json={'kind': 'cover', 'artist': 'Artist', 'title': 'Song'})
    assert result.status_code == 502


def test_alternatives_auth_and_request_validation(setup):
    client, _, route = setup
    assert client.post(route + '/alternative-cover', json={'collection_id': 0}).status_code == 422
    assert client.post(route + '/alternatives', json={'kind': 'arbitrary', 'artist': 'Artist', 'title': 'Song'}).status_code == 422
    assert client.post(route + '/alternatives', json={'kind': 'cover', 'artist': 'Artist', 'title': 'Song'}, headers={'Authorization': 'Bearer wrong'}).status_code == 401
    assert client.post(f'/tracks/{uuid4()}/alternative-cover', json={'collection_id': 1}).status_code == 404
