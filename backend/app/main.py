import asyncio
import base64
import binascii
import contextlib
import hmac
import os
import shutil
import tempfile
import time
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, File, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from . import audio
from .models import AlternativeCoverRequest, AlternativesRequest, AvailabilityRequest, EnrichRequest, ExportRequest, Tags
from .alternatives import download_cover, find_alternatives
from .providers import ProviderError, Providers

MAX_BYTES = 120 * 1024 * 1024
MAX_STORAGE = 2 * 1024 * 1024 * 1024
TTL = 3600


@dataclass
class Track:
    id: str
    path: Path
    filename: str
    tags: Tags
    duration: float
    size: int
    cover: bytes | None
    touched: float = field(default_factory=time.monotonic)
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)


async def authenticated(authorization: str | None = Header(default=None)):
    token = os.getenv("RESONANCE_TOKEN", "")
    if not token:
        raise HTTPException(503, "Set RESONANCE_TOKEN on the server before connecting.")
    if not authorization or not hmac.compare_digest(authorization, f"Bearer {token}"):
        raise HTTPException(401, "Incorrect server access token.")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # TemporaryDirectory is removed on graceful shutdown; no audio is retained in a database.
    with tempfile.TemporaryDirectory(prefix="resonance-") as directory:
        app.state.root = Path(directory)
        (app.state.root / "exports").mkdir()
        app.state.tracks = {}
        app.state.upload_lock = asyncio.Lock()
        app.state.providers = Providers()

        async def sweep():
            while True:
                await asyncio.sleep(60)
                for id, track in list(app.state.tracks.items()):
                    if not track.lock.locked() and time.monotonic() - track.touched > TTL:
                        app.state.tracks.pop(id, None)
                        shutil.rmtree(track.path.parent, ignore_errors=True)
                for output in (app.state.root / "exports").iterdir():
                    try:
                        if time.time() - output.stat().st_mtime > TTL:
                            output.unlink(missing_ok=True)
                    except FileNotFoundError:
                        continue  # A completed download may already have removed it.

        cleanup = asyncio.create_task(sweep())
        yield
        cleanup.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await cleanup
        await app.state.providers.close()


app = FastAPI(title="Resonance", version="1.3.0", lifespan=lifespan,
              dependencies=[Depends(authenticated)])


@app.exception_handler(ProviderError)
async def provider_error(request, exc):
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=502, content={"detail": str(exc)})


@app.middleware("http")
async def check_content_length(request, call_next):
    # Native clients send Content-Length. Refuse unbounded/chunked uploads before multipart spooling.
    if request.url.path == "/tracks" and request.method == "POST":
        # Reject unauthorized uploads before the multipart parser spools audio.
        try:
            await authenticated(request.headers.get("authorization"))
        except HTTPException as exc:
            from fastapi.responses import JSONResponse
            return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
        try:
            size = int(request.headers.get("content-length", "0"))
        except ValueError:
            size = 0
        if not 0 < size <= MAX_BYTES + 1024 * 1024:
            from fastapi.responses import JSONResponse
            return JSONResponse(status_code=413, content={"detail": "Upload must have a Content-Length and be at most 120 MiB."})
    return await call_next(request)


def track_for(id: UUID) -> Track:
    track = app.state.tracks.get(str(id))
    if not track:
        raise HTTPException(404, "This session expired. Import the audio file again.")
    track.touched = time.monotonic()
    return track


@app.get("/health")
async def health():
    return {"status": "ok", "version": "1.3.0", "candidate_availability": True, "alternative_sources": True,
            "fingerprint_tool": bool(shutil.which("fpcalc") or shutil.which("ffmpeg")),
            "acoustid_configured": bool(app.state.providers.key),
            "musicbrainz_configured": bool(app.state.providers.user_agent),
            "max_upload_bytes": MAX_BYTES, "session_ttl_seconds": TTL}


@app.post("/tracks")
async def upload(file: UploadFile = File()):
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in audio.SUPPORTED:
        raise HTTPException(415, "Use MP3, FLAC, M4A, Ogg Vorbis or Opus.")
    async with app.state.upload_lock:
        if len(app.state.tracks) >= 50 or sum(t.size for t in app.state.tracks.values()) >= MAX_STORAGE:
            raise HTTPException(507, "Temporary storage is full. Remove an imported file or wait for sessions to expire.")
        id = str(uuid4())
        folder = app.state.root / id
        folder.mkdir()
        path = folder / ("original" + suffix)
        try:
            size = 0
            with path.open("wb") as target:
                while chunk := await file.read(1024 * 1024):
                    size += len(chunk)
                    if size > MAX_BYTES:
                        raise HTTPException(413, "Audio files must be at most 120 MiB.")
                    target.write(chunk)
            tags, duration, cover = await asyncio.to_thread(audio.read, path)
            # Preview images are bounded independently from embedded originals.
            if cover:
                try:
                    cover = audio.normalize_cover(cover)[0]
                except ValueError:
                    cover = None
            track = Track(id, path, (file.filename or "track").replace("\\", "/").split("/")[-1], tags, duration, size, cover)
            app.state.tracks[id] = track
        except HTTPException:
            shutil.rmtree(folder, ignore_errors=True)
            raise
        except Exception as exc:
            shutil.rmtree(folder, ignore_errors=True)
            raise HTTPException(422, "Could not parse this file. It may be corrupt, protected, or an unsupported audio container.") from exc
        finally:
            await file.close()
    return {"id": id, "filename": track.filename, "tags": tags, "duration": duration,
            "size": size, "cover_base64": base64.b64encode(cover).decode() if cover else None}


@app.post("/tracks/{id}/identify")
async def identify(id: UUID):
    track = track_for(id)
    async with track.lock:
        return await app.state.providers.identify(track.path, track.duration)


@app.get("/search")
async def search(q: str = Query(min_length=2, max_length=500)):
    return {"candidates": await app.state.providers.search(q)}


@app.post("/tracks/{id}/enrich")
async def enrich(id: UUID, body: EnrichRequest):
    track = track_for(id)
    async with track.lock:
        return await app.state.providers.enrich(str(body.recording_id), str(body.release_id) if body.release_id else None,
                                                body.current_tags or track.tags, track.duration, body.lyrics, body.cover)


@app.post("/tracks/{id}/availability")
async def availability(id: UUID, body: AvailabilityRequest):
    track = track_for(id)
    # Read-only remote checks do not block export or editing of the track.
    return await app.state.providers.availability(body, track.duration)


@app.post("/tracks/{id}/alternatives")
async def alternatives(id: UUID, body: AlternativesRequest):
    track_for(id)
    return await find_alternatives(app.state.providers, body)


@app.post("/tracks/{id}/alternative-cover")
async def alternative_cover(id: UUID, body: AlternativeCoverRequest):
    track_for(id)
    return await download_cover(app.state.providers, body.collection_id)


@app.post("/tracks/{id}/lyrics")
async def lyrics(id: UUID, tags: Tags):
    track = track_for(id)
    async with track.lock:
        result = await app.state.providers.lyrics(tags, track.duration)
        if result is None:
            raise HTTPException(404, "No lyrics match this title, artist and duration. Existing lyrics were kept.")
        return {"lyrics": result.get("plainLyrics") or "", "synced_lyrics": result.get("syncedLyrics") or "",
                "instrumental": result.get("instrumental", False), "source": f"https://lrclib.net/api/get/{result['id']}"}


@app.post("/tracks/{id}/export")
async def export(id: UUID, body: ExportRequest):
    track = track_for(id)
    async with track.lock:
        cover = None
        if body.cover_action == "replace":
            try:
                cover = base64.b64decode(body.cover_base64 or "", validate=True)
            except (ValueError, binascii.Error) as exc:
                raise HTTPException(422, "Invalid cover image encoding.") from exc
        # Keep downloads outside the session folder so removing a session does not
        # unlink a file while its response is still being streamed.
        output = app.state.root / "exports" / (str(uuid4()) + track.path.suffix)
        try:
            await asyncio.to_thread(audio.write_copy, track.path, output, body.tags, body.cover_action, cover)
        except Exception as exc:
            output.unlink(missing_ok=True)
            raise HTTPException(422, str(exc) if isinstance(exc, ValueError) else "Could not write tags to this audio container.") from exc
        # A separate output per request permits simultaneous downloads without corruption.
        filename = Path(track.filename).stem + " - tagged" + track.path.suffix
        return FileResponse(output, media_type="application/octet-stream", filename=filename,
                            background=BackgroundTask(output.unlink, missing_ok=True))


@app.delete("/tracks/{id}")
async def delete(id: UUID):
    track = track_for(id)
    async with track.lock:
        app.state.tracks.pop(str(id), None)
        shutil.rmtree(track.path.parent, ignore_errors=True)
    return {"deleted": True}
