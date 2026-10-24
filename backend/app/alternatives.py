"""Free alternate sources, with user review and fixed, trusted image hosts."""
import asyncio
import base64
import re
import unicodedata
from urllib.parse import quote, urlparse

import httpx

from .audio import normalize_cover
from .models import AlternativesRequest
from .providers import ProviderError


def normalized(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', str(value)).casefold() if c.isalnum())


def artwork_url(value):
    if not isinstance(value, str):
        return None
    parsed = urlparse(value)
    try:
        valid = parsed.scheme == 'https' and parsed.hostname and (parsed.hostname == 'mzstatic.com' or parsed.hostname.endswith('.mzstatic.com')) and parsed.port in (None, 443) and not parsed.username and not parsed.password
    except ValueError:
        return None
    return value if valid else None


async def find_alternatives(providers, candidate: AlternativesRequest):
    options, warnings = [], []
    if candidate.kind == 'cover':
        data = await providers.request_json('https://itunes.apple.com/search', params={
            'term': f'{candidate.artist} {candidate.title}', 'media': 'music', 'entity': 'song', 'limit': 20,
        })
        if not isinstance(data, dict) or not isinstance(data.get('results'), list):
            raise ProviderError('iTunes returned an invalid search response.')
        seen = set()
        for item in data.get('results', []):
            if not isinstance(item, dict) or normalized(item.get('artistName', '')) != normalized(candidate.artist):
                continue
            image = artwork_url(item.get('artworkUrl100'))
            id = item.get('collectionId')
            if not image or type(id) is not int or id <= 0 or id in seen:
                continue
            seen.add(id)
            options.append({'collection_id': id, 'source': 'iTunes', 'title': item.get('trackName', ''),
                            'artist': item.get('artistName', ''), 'album': item.get('collectionName', ''),
                            'preview_url': image, 'source_url': f'https://music.apple.com/album/{id}'})
        options.sort(key=lambda o: (normalized(o['album']) != normalized(candidate.album), normalized(o['title']) != normalized(candidate.title)))
        return {'options': options[:8], 'warnings': warnings}

    async def ovh():
        url = f'https://api.lyrics.ovh/v1/{quote(candidate.artist, safe="")}/{quote(candidate.title, safe="")}'
        try:
            data = await providers.request_json(url, missing_ok=True)
            text = data.get('lyrics') if isinstance(data, dict) else None
            if isinstance(text, str) and text.strip() and len(text) <= 200000:
                return [{'source': 'lyrics.ovh', 'title': candidate.title, 'artist': candidate.artist,
                         'album': candidate.album, 'lyrics': text, 'synced_lyrics': '', 'source_url': url}], None
            return [], None
        except ProviderError as exc:
            return [], str(exc)

    async def lrclib():
        try:
            data = await providers.request_json('https://lrclib.net/api/search', params={
                'track_name': candidate.title, 'artist_name': candidate.artist,
            })
            result = []
            for item in data if isinstance(data, list) else []:
                if not isinstance(item, dict) or normalized(item.get('artistName', '')) != normalized(candidate.artist) or normalized(item.get('trackName', '')) != normalized(candidate.title):
                    continue
                plain, timed = item.get('plainLyrics') or '', item.get('syncedLyrics') or ''
                if not isinstance(plain, str) or not isinstance(timed, str) or not (plain.strip() or timed.strip()) or max(len(plain), len(timed)) > 200000 or type(item.get('id')) is not int:
                    continue
                result.append({'source': 'LRCLIB search', 'title': item['trackName'], 'artist': item['artistName'],
                               'album': item.get('albumName') or '', 'lyrics': plain, 'synced_lyrics': timed,
                               'source_url': f'https://lrclib.net/api/get/{item["id"]}'})
            result.sort(key=lambda o: normalized(o['album']) != normalized(candidate.album))
            return result[:8], None
        except ProviderError as exc:
            return [], str(exc)

    for items, warning in await asyncio.gather(ovh(), lrclib()):
        options.extend(items)
        if warning:
            warnings.append(warning)
    return {'options': options, 'warnings': warnings}


async def download_cover(providers, collection_id: int):
    data = await providers.request_json('https://itunes.apple.com/lookup', params={'id': collection_id})
    if not isinstance(data, dict) or not isinstance(data.get('results'), list):
        raise ProviderError('iTunes returned an invalid album response.')
    image = next((artwork_url(item.get('artworkUrl100')) for item in data.get('results', [])
                  if isinstance(item, dict) and item.get('collectionId') == collection_id and artwork_url(item.get('artworkUrl100'))), None)
    if image is None:
        raise ProviderError('No artwork was supplied for that iTunes album.')
    large = re.sub(r'/100x100bb', '/600x600bb', image)
    for url in dict.fromkeys([large, image]):
        # Do not follow image redirects to an untrusted host or local service.
        try:
            async with providers.client.stream('GET', url, follow_redirects=False) as response:
                if response.status_code == 404:
                    continue
                response.raise_for_status()
                if not response.headers.get('content-type', '').lower().startswith('image/'):
                    raise ProviderError('The artwork source did not return an image.')
                raw = bytearray()
                async for chunk in response.aiter_bytes():
                    raw.extend(chunk)
                    if len(raw) > 5 * 1024 * 1024:
                        raise ProviderError('Cover exceeds 5 MiB.')
            jpeg = normalize_cover(bytes(raw))[0]
            return {'cover_base64': base64.b64encode(jpeg).decode(), 'source': 'iTunes',
                    'source_url': f'https://music.apple.com/album/{collection_id}'}
        except (httpx.HTTPError, ValueError) as exc:
            raise ProviderError('Could not download this artwork. Try a different result.') from exc
    raise ProviderError('The selected artwork is no longer available.')
