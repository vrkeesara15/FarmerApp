"""Photo evidence helpers (FA-015, VA-E08): perceptual hash and EXIF fallback.

* ``phash(data)`` — the 64-bit DCT perceptual hash (``imagehash.phash``) as 16 hex
  characters, the value stored on ``visit_photo.phash`` for VA-E08 duplicate detection
  (near-duplicates have a small Hamming distance; identical bytes hash the same). ``None``
  when the bytes are not an image Pillow can decode (the row is still stored: a corrupt
  file is evidence too).
* ``read_exif(data)`` — best-effort ``DateTimeOriginal`` (+ ``OffsetTimeOriginal``) and GPS
  from the JPEG's EXIF, used only when the device did not send ``exif_time`` /
  ``exif_point`` (the in-app camera writes both into the upload payload, NF-004). EXIF
  times without an offset are taken as IST (the pilot's single time zone; assumption).
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, timezone
from fractions import Fraction
from typing import Any

import imagehash
from PIL import Image, UnidentifiedImageError

from farmerapp.logging import get_logger

log = get_logger("farmerapp.visits.photos")

IST = timezone(timedelta(hours=5, minutes=30))

_EXIF_IFD = 0x8769
_GPS_IFD = 0x8825
_DATETIME_ORIGINAL = 0x9003
_OFFSET_TIME_ORIGINAL = 0x9011
_GPS_LAT_REF, _GPS_LAT, _GPS_LON_REF, _GPS_LON = 1, 2, 3, 4


@dataclass(frozen=True)
class ExifData:
    time: datetime | None
    lat: float | None
    lon: float | None


def phash(data: bytes) -> str | None:
    """Perceptual hash of an image, or ``None`` when Pillow cannot decode it."""
    try:
        with Image.open(io.BytesIO(data)) as image:
            return str(imagehash.phash(image))
    except (UnidentifiedImageError, OSError, ValueError):
        log.warning("visit_photo_undecodable", size=len(data))
        return None


def _parse_offset(raw: object) -> timezone:
    text = str(raw).strip()
    if len(text) == 6 and text[0] in "+-" and text[3] == ":":
        sign = 1 if text[0] == "+" else -1
        hours, minutes = int(text[1:3]), int(text[4:6])
        return timezone(sign * timedelta(hours=hours, minutes=minutes))
    return IST


def _parse_datetime(raw: object, offset: object | None) -> datetime | None:
    try:
        naive = datetime.strptime(str(raw).strip(), "%Y:%m:%d %H:%M:%S")
    except ValueError:
        return None
    tz = _parse_offset(offset) if offset is not None else IST
    return naive.replace(tzinfo=tz).astimezone(UTC)


def _dms(values: Any, ref: object) -> float | None:
    try:
        degrees, minutes, seconds = (float(Fraction(v)) for v in values)
    except (TypeError, ValueError, ZeroDivisionError):
        return None
    value = degrees + minutes / 60 + seconds / 3600
    return -value if str(ref).upper() in ("S", "W") else value


def read_exif(data: bytes) -> ExifData:
    """EXIF capture time (UTC) and GPS of a JPEG; ``None`` fields when absent."""
    try:
        with Image.open(io.BytesIO(data)) as image:
            exif = image.getexif()
            exif_ifd = exif.get_ifd(_EXIF_IFD)
            gps_ifd = exif.get_ifd(_GPS_IFD)
    except (UnidentifiedImageError, OSError, ValueError):
        return ExifData(time=None, lat=None, lon=None)
    time: datetime | None = None
    raw_time = exif_ifd.get(_DATETIME_ORIGINAL)
    if raw_time is not None:
        time = _parse_datetime(raw_time, exif_ifd.get(_OFFSET_TIME_ORIGINAL))
    lat = lon = None
    if gps_ifd.get(_GPS_LAT) is not None and gps_ifd.get(_GPS_LON) is not None:
        lat = _dms(gps_ifd[_GPS_LAT], gps_ifd.get(_GPS_LAT_REF, "N"))
        lon = _dms(gps_ifd[_GPS_LON], gps_ifd.get(_GPS_LON_REF, "E"))
        if lat is None or lon is None:
            lat = lon = None
    return ExifData(time=time, lat=lat, lon=lon)


__all__ = ["IST", "ExifData", "phash", "read_exif"]
