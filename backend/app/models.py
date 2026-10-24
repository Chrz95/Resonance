from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class Tags(BaseModel):
    model_config = ConfigDict(extra="forbid", str_max_length=2000)
    title: str = ""
    artist: str = ""
    album: str = ""
    album_artist: str = ""
    date: str = ""
    genre: str = ""
    track_number: str = Field(default="", pattern=r"^(\d{1,5}(/\d{1,5})?)?$")
    disc_number: str = Field(default="", pattern=r"^(\d{1,5}(/\d{1,5})?)?$")
    recording_id: str = ""
    release_id: str = ""
    lyrics: str = Field(default="", max_length=200000)
    synced_lyrics: str = Field(default="", max_length=200000)


class Candidate(BaseModel):
    recording_id: str
    release_id: str = ""
    title: str
    artist: str
    album: str = ""
    date: str = ""
    country: str = ""
    duration: float | None = None
    score: float = 0
    source: Literal["fingerprint", "metadata"]


class EnrichRequest(BaseModel):
    recording_id: UUID
    release_id: UUID | None = None
    lyrics: bool = True
    cover: bool = True
    current_tags: Tags | None = None


class AvailabilityRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_max_length=2000)
    title: str = ""
    artist: str = ""
    album: str = ""
    release_id: UUID | None = None
    duration: float | None = Field(default=None, gt=0, le=86400)


class AlternativesRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_max_length=2000)
    kind: Literal["cover", "lyrics"]
    title: str = Field(min_length=1)
    artist: str = Field(min_length=1)
    album: str = ""


class AlternativeCoverRequest(BaseModel):
    collection_id: int = Field(gt=0)


class ExportRequest(BaseModel):
    tags: Tags
    cover_action: Literal["keep", "replace", "remove"] = "keep"
    cover_base64: str | None = Field(default=None, max_length=8_000_000)
