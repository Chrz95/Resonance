import asyncio
import base64
import hashlib
import json
import math
import os
import re
import shutil
import time
from datetime import date as CalendarDate
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.parse import urlparse, quote

import httpx

from .audio import normalize_cover
from .models import AlternativesRequest, AvailabilityRequest, Candidate, Tags


class ProviderError(Exception):
    pass


def retry_after_seconds(value: str | None) -> float:
    if value is None:
        return 60
    try:
        seconds = float(value)
    except ValueError:
        try:
            seconds = parsedate_to_datetime(value).timestamp() - time.time()
        except (ValueError, TypeError, OverflowError):
            return 60
    return max(1, seconds) if math.isfinite(seconds) else 60


def credit(items: list) -> str:
    return "".join((a.get("name") or a.get("artist", {}).get("name", "")) + a.get("joinphrase", "")
                   for a in items if isinstance(a, dict))


def normalize_date(value: object) -> str:
    """MusicBrainz uses text; AcoustID releases use year/month/day objects.

    Keep partial dates at their known precision, without inventing missing parts.
    Invalid optional parts fall back to the last valid precision.
    """
    if isinstance(value, str):
        return value
    if not isinstance(value, dict):
        return ""

    def part(key):
        item = value.get(key)
        if type(item) is int:
            return item
        if isinstance(item, str) and len(item) <= 4 and item.isascii() and item.isdigit():
            return int(item)
        return 0

    year, month, day = part("year"), part("month"), part("day")
    if not 1 <= year <= 9999:
        return ""
    result = f"{year:04d}"
    if not 1 <= month <= 12:
        return result
    result += f"-{month:02d}"
    try:
        CalendarDate(year, month, day)
    except ValueError:
        return result
    return f"{result}-{day:02d}"


def candidates(recordings: list, source: str, score: float | None = None) -> list[Candidate]:
    result = []
    for rec in recordings:
        artist = credit(rec.get("artist-credit", [])) or ", ".join(a.get("name", "") for a in rec.get("artists", []))
        releases = rec.get("releases") or [{}]
        for release in releases[:4]:
            milliseconds = rec.get("length")
            duration = milliseconds / 1000 if isinstance(milliseconds, (int, float)) else rec.get("duration")
            if not isinstance(duration, (int, float)) or duration <= 0:
                duration = None
            result.append(Candidate(
                recording_id=rec["id"], release_id=release.get("id", ""), title=rec.get("title", "Unknown"),
                artist=artist, album=release.get("title", ""), date=normalize_date(release.get("date")),
                country=release.get("country", ""), duration=duration,
                score=score if score is not None else float(rec.get("score", 0)) / 100, source=source,
            ))
    return result


class Providers:
    def __init__(self):
        self.key = os.getenv("ACOUSTID_API_KEY", "")
        self.user_agent = os.getenv("MUSIC_USER_AGENT", "")
        self.client = httpx.AsyncClient(timeout=30, follow_redirects=True, headers={
            "User-Agent": self.user_agent or "Resonance/1.0 (self-hosted; configure MUSIC_USER_AGENT)",
        })
        self.locks: dict[str, asyncio.Lock] = {}
        self.next_request: dict[str, float] = {}
        self.cache: dict[str, tuple[float, object]] = {}
        self.decode_slots = asyncio.Semaphore(2)
        self.cover_checks: dict[str, tuple[float, bool]] = {}

    async def close(self):
        await self.client.aclose()

    async def request_json(self, url: str, *, params=None, data=None, missing_ok=False):
        host = urlparse(url).hostname or ""
        cache_key = url + json.dumps(params or {}, sort_keys=True)
        if data is None and cache_key in self.cache:
            when, value = self.cache[cache_key]
            if time.monotonic() - when < 900:
                return value
        if host == "musicbrainz.org" and not self.user_agent:
            raise ProviderError("Set MUSIC_USER_AGENT with your contact email or project URL before using MusicBrainz.")
        lock = self.locks.setdefault(host, asyncio.Lock())
        async with lock:
            delay = self.next_request.get(host, 0) - time.monotonic()
            if delay > 30:
                raise ProviderError(f"{host} requested a cooldown. Try again later.")
            if delay > 0:
                await asyncio.sleep(delay)
            self.next_request[host] = time.monotonic() + (1.1 if host == "musicbrainz.org" else 3.1 if host == "itunes.apple.com" else 0.4)
            try:
                response = await self.client.request("POST" if data is not None else "GET", url, params=params, data=data)
                if response.status_code == 404 and missing_ok:
                    return None
                if response.status_code in (429, 503):
                    retry = response.headers.get("Retry-After", "5")
                    try:
                        seconds = float(retry)
                    except ValueError:
                        try:
                            seconds = parsedate_to_datetime(retry).timestamp() - time.time()
                        except (ValueError, TypeError):
                            seconds = 5
                    self.next_request[host] = time.monotonic() + max(1, seconds)
                    raise ProviderError(f"{host} is busy. Retry after {max(1, int(seconds))} seconds.")
                response.raise_for_status()
                value = response.json()
            except (httpx.HTTPError, ValueError) as exc:
                raise ProviderError(f"{host} could not complete the lookup. Check your connection and service configuration.") from exc
        if data is None:
            if len(self.cache) >= 300:
                self.cache.pop(next(iter(self.cache)))
            self.cache[cache_key] = (time.monotonic(), value)
        return value

    async def fingerprint(self, path: Path) -> str:
        async with self.decode_slots:
            if shutil.which("fpcalc"):
                args = ["fpcalc", "-json", "-length", "120", str(path)]
            elif shutil.which("ffmpeg"):
                args = ["ffmpeg", "-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe",
                        "-i", str(path), "-t", "120", "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "11025",
                        "-f", "chromaprint", "-fp_format", "base64", "pipe:1"]
            else:
                raise ProviderError("Install Chromaprint fpcalc or FFmpeg with Chromaprint support on the server.")
            proc = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            try:
                stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=90)
            except (TimeoutError, asyncio.CancelledError):
                if proc.returncode is None:
                    proc.kill()
                await proc.wait()
                raise ProviderError("Audio fingerprint calculation timed out.")
            if proc.returncode and not (args[0] == "fpcalc" and stdout.strip()):
                raise ProviderError("Could not decode this audio. Check the file and Chromaprint installation.")
            try:
                value = json.loads(stdout)["fingerprint"] if args[0] == "fpcalc" else stdout.decode().strip()
            except (ValueError, KeyError) as exc:
                raise ProviderError("Fingerprint tool returned invalid output.") from exc
            if len(value) < 8 or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
                raise ProviderError("Audio is too short or could not produce a fingerprint.")
            return value

    async def identify(self, path: Path, duration: float):
        fp = await self.fingerprint(path)
        signature = hashlib.sha256(fp.encode()).hexdigest()
        if not self.key:
            return {"signature": signature, "lookup_performed": False, "candidates": [], "warnings": [
                "Fingerprint extracted. Set the free ACOUSTID_API_KEY on the server to match it, or use metadata search."]}
        data = await self.request_json("https://api.acoustid.org/v2/lookup", data={
            "client": self.key, "duration": str(round(duration)), "fingerprint": fp,
            "meta": "recordings releases", "format": "json",
        })
        if data.get("status") != "ok":
            raise ProviderError("AcoustID rejected the lookup. Check that ACOUSTID_API_KEY is a valid application key.")
        result, seen = [], set()
        for item in sorted(data.get("results", []), key=lambda a: a.get("score", 0), reverse=True):
            for candidate in candidates(item.get("recordings", []), "fingerprint", item.get("score", 0)):
                key = (candidate.recording_id, candidate.release_id)
                if key not in seen:
                    result.append(candidate)
                    seen.add(key)
        return {"signature": signature, "lookup_performed": True, "candidates": result[:24], "warnings": [] if result else [
            "No fingerprint match found. Try searching by title and artist."]}

    async def search(self, query: str):
        data = await self.request_json("https://musicbrainz.org/ws/2/recording/", params={
            "query": query, "fmt": "json", "limit": 8,
        })
        return candidates(data.get("recordings", []), "metadata")[:24]

    async def lyrics(self, tags: Tags, duration: float):
        if not tags.title or not tags.artist:
            raise ProviderError("Enter a title and artist before fetching lyrics.")
        params = {"track_name": tags.title, "artist_name": tags.artist, "album_name": tags.album}
        if 1 <= duration <= 3600:
            params["duration"] = round(duration)
        return await self.request_json("https://lrclib.net/api/get", params=params, missing_ok=True)

    async def _throttle_cover(self):
        host = "coverartarchive.org"
        delay = self.next_request.get(host, 0) - time.monotonic()
        if delay > 30:
            raise ProviderError("Artwork service requested a cooldown. Try again later.")
        if delay > 0:
            await asyncio.sleep(delay)
        self.next_request[host] = time.monotonic() + 0.4

    async def cover(self, release_id: str) -> bytes | None:
        # Only a server-built URL is accepted; clients cannot supply arbitrary URLs.
        url = f"https://coverartarchive.org/release/{release_id}/front-500"
        async with self.locks.setdefault("coverartarchive.org", asyncio.Lock()):
            await self._throttle_cover()
            try:
                async with self.client.stream("GET", url) as response:
                    if response.status_code == 404:
                        return None
                    if response.status_code in (429, 503):
                        self.next_request["coverartarchive.org"] = time.monotonic() + retry_after_seconds(response.headers.get("Retry-After"))
                    response.raise_for_status()
                    data = bytearray()
                    async for chunk in response.aiter_bytes():
                        data.extend(chunk)
                        if len(data) > 5 * 1024 * 1024:
                            raise ProviderError("Cover image exceeds 5 MiB.")
                return normalize_cover(bytes(data))[0]
            except (httpx.HTTPError, ValueError) as exc:
                raise ProviderError("Cover Art Archive could not supply an image for this release.") from exc

    async def cover_available(self, release_id: str) -> bool:
        """Verify this release's front thumbnail without downloading every image."""
        cached = self.cover_checks.get(release_id)
        if cached and time.monotonic() - cached[0] < 900:
            return cached[1]
        host = "coverartarchive.org"
        url = f"https://{host}/release/{release_id}/front-500"
        async with self.locks.setdefault(host, asyncio.Lock()):
            # Recheck after waiting for another request for the same release.
            cached = self.cover_checks.get(release_id)
            if cached and time.monotonic() - cached[0] < 900:
                return cached[1]
            await self._throttle_cover()
            try:
                response = await self.client.head(url)
                if response.status_code in (429, 503):
                    self.next_request[host] = time.monotonic() + retry_after_seconds(response.headers.get("Retry-After"))
                    raise ProviderError("Artwork service is busy; availability is unknown.")
                if response.status_code == 404:
                    available = False
                else:
                    response.raise_for_status()
                    if not response.headers.get("content-type", "").lower().startswith("image/"):
                        raise ProviderError("Artwork service did not confirm an image; availability is unknown.")
                    available = True
            except httpx.HTTPError as exc:
                raise ProviderError("Could not check artwork availability.") from exc
        if len(self.cover_checks) >= 300:
            self.cover_checks.pop(next(iter(self.cover_checks)))
        self.cover_checks[release_id] = (time.monotonic(), available)
        return available

    async def availability(self, candidate: AvailabilityRequest, duration: float):
        result = {"has_lyrics": None, "has_cover": None, "instrumental": False, "warnings": []}
        if candidate.title and candidate.artist:
            try:
                item = await self.lyrics(Tags(title=candidate.title, artist=candidate.artist,
                                             album=candidate.album), candidate.duration or duration)
                result["has_lyrics"] = bool(item and ((item.get("plainLyrics") or "").strip() or
                                                      (item.get("syncedLyrics") or "").strip()))
                result["instrumental"] = bool(item and item.get("instrumental"))
            except (ProviderError, httpx.HTTPError, TimeoutError) as exc:
                result["warnings"].append(str(exc))
        else:
            result["warnings"].append("A title and artist are needed to check lyrics.")
        if candidate.release_id:
            try:
                result["has_cover"] = await self.cover_available(str(candidate.release_id))
            except (ProviderError, httpx.HTTPError, TimeoutError) as exc:
                result["warnings"].append(str(exc))
        else:
            result["has_cover"] = False
        return result

    async def enrich(self, recording_id: str, release_id: str | None, current: Tags, duration: float,
                     want_lyrics=True, want_cover=True):
        rec = await self.request_json(f"https://musicbrainz.org/ws/2/recording/{recording_id}", params={
            "inc": "artist-credits+releases+genres", "fmt": "json",
        })
        tags = current.model_copy(deep=True)
        tags.title = rec.get("title") or tags.title
        tags.artist = credit(rec.get("artist-credit", [])) or tags.artist
        tags.recording_id = recording_id
        tags.release_id = ""
        genres = sorted(rec.get("genres", []), key=lambda g: g.get("count", 0), reverse=True)
        if genres:
            tags.genre = genres[0]["name"]
        warnings = []
        cover = None
        sources = [f"https://musicbrainz.org/recording/{recording_id}"]
        # A recording can belong to many releases; never silently choose an album.
        if release_id:
            release = await self.request_json(f"https://musicbrainz.org/ws/2/release/{release_id}", params={
                "inc": "recordings+artist-credits", "fmt": "json",
            })
            position = None
            for medium in release.get("media", []):
                for track in medium.get("tracks", []):
                    if track.get("recording", {}).get("id") == recording_id:
                        position = (medium, track)
                        break
                if position:
                    break
            if not position:
                raise ProviderError("This recording is not on the selected release. Choose another match.")
            medium, track = position
            tags.release_id = release_id
            tags.album = release.get("title", "")
            tags.album_artist = credit(release.get("artist-credit", []))
            tags.date = normalize_date(release.get("date"))
            tags.track_number = f"{track['position']}/{medium.get('track-count') or len(medium.get('tracks', []))}"
            tags.disc_number = f"{medium['position']}/{len(release.get('media', []))}"
            sources.append(f"https://musicbrainz.org/release/{release_id}")
        if want_lyrics:
            try:
                lyrics = await self.lyrics(tags, duration)
                if lyrics:
                    sources.append(f"https://lrclib.net/api/get/{lyrics['id']}")
                    tags.lyrics = lyrics.get("plainLyrics") or ""
                    tags.synced_lyrics = lyrics.get("syncedLyrics") or ""
                    if lyrics.get("instrumental"):
                        warnings.append("LRCLIB marks this track as instrumental.")
                else:
                    warnings.append("No matching lyrics found; existing lyrics were kept.")
            except ProviderError as exc:
                warnings.append(str(exc))
        if not release_id:
            warnings.append("No release selected. Existing album tags were kept; choose a release candidate to fetch album artwork.")
        if want_cover and release_id:
            try:
                cover = await self.cover(release_id)
                if cover:
                    sources.append(f"https://coverartarchive.org/release/{release_id}/front-500")
                if not cover:
                    warnings.append("No front cover for this release; existing artwork was kept.")
            except ProviderError as exc:
                warnings.append(str(exc))
        return {"tags": tags, "cover_base64": base64.b64encode(cover).decode() if cover else None,
                "warnings": warnings, "sources": sources}
