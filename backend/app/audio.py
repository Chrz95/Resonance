"""Container-specific tag mapping. Audio packets are never re-encoded."""

import base64
import io
import shutil
from pathlib import Path

import mutagen
from mutagen.flac import FLAC, Picture
from mutagen.id3 import APIC, TALB, TIT2, TPE1, TPE2, TCON, TDRC, TRCK, TPOS, TXXX, UFID, USLT
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4, MP4Cover, MP4FreeForm
from mutagen.oggopus import OggOpus
from mutagen.oggvorbis import OggVorbis
from PIL import Image, UnidentifiedImageError

from .models import Tags

SUPPORTED = {".mp3": MP3, ".flac": FLAC, ".m4a": MP4, ".ogg": OggVorbis, ".opus": OggOpus}
COMMENT_KEYS = {
    "title": "title", "artist": "artist", "album": "album", "album_artist": "albumartist",
    "date": "date", "genre": "genre", "track_number": "tracknumber", "disc_number": "discnumber",
    "recording_id": "musicbrainz_trackid", "release_id": "musicbrainz_albumid",
    "lyrics": "lyrics", "synced_lyrics": "syncedlyrics",
}
MP4_KEYS = {"title": "\xa9nam", "artist": "\xa9ART", "album": "\xa9alb", "album_artist": "aART",
            "date": "\xa9day", "genre": "\xa9gen", "lyrics": "\xa9lyr"}
ID3_KEYS = {"title": TIT2, "artist": TPE1, "album": TALB, "album_artist": TPE2,
            "date": TDRC, "genre": TCON, "track_number": TRCK, "disc_number": TPOS}
FREEFORM = {"recording_id": "MusicBrainz Track Id", "release_id": "MusicBrainz Album Id",
            "synced_lyrics": "LYRICS_SYNCED"}


def load(path: Path):
    try:
        audio = mutagen.File(path)
    except mutagen.MutagenError as exc:
        raise ValueError("Invalid audio container or file does not match its extension.") from exc
    expected = SUPPORTED.get(path.suffix.lower())
    if expected is None or not isinstance(audio, expected):
        raise ValueError("Invalid audio or container does not match extension. Use MP3, FLAC, M4A, Ogg Vorbis or Opus.")
    if audio.tags is None:
        audio.add_tags()
    return audio


def first(tags, key: str) -> str:
    values = tags.get(key, [])
    return str(values[0]) if values else ""


def discard(tags, key: str):
    # Vorbis comments inherit list.pop rather than dict.pop.
    if key in tags:
        del tags[key]


def read(path: Path) -> tuple[Tags, float, bytes | None]:
    audio = load(path)
    t = audio.tags
    data = {}
    cover = None
    if isinstance(audio, MP3):
        for field, frame in ID3_KEYS.items():
            item = t.get(frame.__name__)
            data[field] = str(item.text[0]) if item and item.text else ""
        lyrics = t.getall("USLT")
        data["lyrics"] = lyrics[0].text if lyrics else ""
        for field, desc in FREEFORM.items():
            item = t.get(f"TXXX:{desc}")
            if field == "synced_lyrics" and item is None:
                item = t.get("TXXX:SYNCEDLYRICS")
            data[field] = str(item.text[0]) if item and item.text else ""
        ufid = t.get("UFID:http://musicbrainz.org")
        if ufid:
            data["recording_id"] = ufid.data.decode("utf-8", errors="replace")
        pictures = t.getall("APIC")
        if pictures:
            cover = next((p for p in pictures if p.type == 3), pictures[0]).data
    elif isinstance(audio, MP4):
        for field, key in MP4_KEYS.items():
            data[field] = first(t, key)
        for field, desc in FREEFORM.items():
            value = t.get(f"----:com.apple.iTunes:{desc}", [])
            if field == "synced_lyrics" and not value:
                value = t.get("----:com.apple.iTunes:SYNCEDLYRICS", [])
            data[field] = bytes(value[0]).decode("utf-8", errors="replace") if value else ""
        for field, key in [("track_number", "trkn"), ("disc_number", "disk")]:
            pair = t.get(key, [(0, 0)])[0]
            data[field] = (f"{pair[0]}/{pair[1]}" if pair[1] else str(pair[0])) if pair[0] else ""
        if t.get("covr"):
            cover = bytes(t["covr"][0])
    else:
        data = {field: first(t, key) for field, key in COMMENT_KEYS.items()}
        # Vorbis also permits separate track/disc totals.
        for field, total_key in [("track_number", "tracktotal"), ("disc_number", "disctotal")]:
            if data[field] and "/" not in data[field] and first(t, total_key):
                data[field] += "/" + first(t, total_key)
        pictures = audio.pictures if isinstance(audio, FLAC) else []
        if pictures:
            cover = next((p for p in pictures if p.type == 3), pictures[0]).data
        elif t.get("metadata_block_picture"):
            try:
                cover = Picture(base64.b64decode(t["metadata_block_picture"][0])).data
            except Exception:
                pass  # A malformed existing image must not prevent tag editing.
    # Tolerate arbitrary existing numeric tags; only write validated values.
    for field in ("track_number", "disc_number"):
        import re
        if not re.fullmatch(r"\d{1,5}(/\d{1,5})?", data.get(field, "")):
            data[field] = ""
    return Tags(**data), float(audio.info.length), cover


def normalize_cover(data: bytes) -> tuple[bytes, str, int, int]:
    if len(data) > 5 * 1024 * 1024:
        raise ValueError("Cover image must be at most 5 MiB.")
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.width * image.height > 25_000_000:
                raise ValueError("Cover resolution is too large.")
            image = image.convert("RGB")
            image.thumbnail((1600, 1600))
            out = io.BytesIO()
            image.save(out, format="JPEG", quality=90)
            return out.getvalue(), "image/jpeg", image.width, image.height
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise ValueError("Cover must be a valid image.") from exc


def write_copy(original: Path, output: Path, tags: Tags, cover_action: str, cover: bytes | None):
    normalized = normalize_cover(cover) if cover_action == "replace" and cover else None
    if cover_action == "replace" and normalized is None:
        raise ValueError("Choose a cover image before replacing it.")
    shutil.copy2(original, output)
    audio = load(output)
    t = audio.tags
    values = tags.model_dump()
    if isinstance(audio, MP3):
        for field, frame in ID3_KEYS.items():
            t.delall(frame.__name__)
            if values[field]:
                t.add(frame(encoding=3, text=[values[field]]))
        t.delall("USLT")
        if tags.lyrics:
            t.add(USLT(encoding=3, lang="und", desc="", text=tags.lyrics))
        for field, desc in FREEFORM.items():
            t.delall(f"TXXX:{desc}")
            if field == "synced_lyrics":
                t.delall("TXXX:SYNCEDLYRICS")
            if values[field]:
                t.add(TXXX(encoding=3, desc=desc, text=[values[field]]))
        t.delall("UFID:http://musicbrainz.org")
        if tags.recording_id:
            t.add(UFID(owner="http://musicbrainz.org", data=tags.recording_id.encode()))
    elif isinstance(audio, MP4):
        for field, key in MP4_KEYS.items():
            discard(t, key)
            if values[field]:
                t[key] = [values[field]]
        for field, desc in FREEFORM.items():
            key = f"----:com.apple.iTunes:{desc}"
            discard(t, key)
            if field == "synced_lyrics":
                discard(t, "----:com.apple.iTunes:SYNCEDLYRICS")
            if values[field]:
                t[key] = [MP4FreeForm(values[field].encode())]
        for field, key in [("track_number", "trkn"), ("disc_number", "disk")]:
            discard(t, key)
            if values[field]:
                parts = [int(s) for s in values[field].split("/")]
                t[key] = [(parts[0], parts[1] if len(parts) > 1 else 0)]
    else:
        for field, key in COMMENT_KEYS.items():
            discard(t, key)
            if values[field]:
                t[key] = [values[field]]
        # Remove stale separate totals after writing combined n/total values.
        for key in ("tracktotal", "totaltracks", "disctotal", "totaldiscs"):
            discard(t, key)
    if cover_action != "keep":
        if isinstance(audio, MP3):
            t.delall("APIC")
            if normalized:
                t.add(APIC(encoding=3, mime=normalized[1], type=3, desc="Cover", data=normalized[0]))
        elif isinstance(audio, MP4):
            discard(t, "covr")
            if normalized:
                t["covr"] = [MP4Cover(normalized[0], imageformat=MP4Cover.FORMAT_JPEG)]
        else:
            if isinstance(audio, FLAC):
                audio.clear_pictures()
            discard(t, "metadata_block_picture")
            discard(t, "coverart")
            discard(t, "coverartmime")
            if normalized:
                picture = Picture()
                picture.type, picture.mime = 3, normalized[1]
                picture.data, picture.width, picture.height = normalized[0], normalized[2], normalized[3]
                picture.depth = 24
                if isinstance(audio, FLAC):
                    audio.add_picture(picture)
                else:
                    t["metadata_block_picture"] = [base64.b64encode(picture.write()).decode()]
    audio.save()
    # Reopen the resulting file before exposing it to a client.
    read(output)
