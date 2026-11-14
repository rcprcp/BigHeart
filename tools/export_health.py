#!/usr/bin/env python3
"""Export historical heart rate and SpO2 samples from Garmin FIT files.

Reads a Garmin Connect account-data export (zip), a directory of FIT files, or a
single FIT file, and writes one CSV per local day:

    timestamp_utc,timestamp_local,hr_bpm,spo2_pct
    2026-11-13T22:05:00Z,2026-11-13T17:05:00-05:00,64,96

Heart rate comes from ``monitoring`` messages, including samples that only
carry the low 16 bits of the timestamp. SpO2 comes from ``spo2_data`` and
``hsa_spo2_data`` messages; array readings are placed at
``timestamp + index * processing_interval``.

Examples:
    python3 tools/export_health.py ~/Downloads/garmin_export.zip -o health_export
    python3 tools/export_health.py ~/Downloads/GARMIN/Monitor --inspect
    python3 tools/export_health.py export.zip --tz Europe/Berlin

Requires ``garmin-fit-sdk`` (see tools/requirements.txt).
"""

from __future__ import annotations

import argparse
import csv
import sys
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Iterator
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

FIT_EPOCH = datetime(1989, 12, 31, tzinfo=timezone.utc)
UINT32 = 1 << 32
TIMESTAMP_16_HALF = 1 << 15
TIMESTAMP_16_MOD = 1 << 16
HEADER = ["timestamp_utc", "timestamp_local", "hr_bpm", "spo2_pct"]
DEFAULT_TEMPLATE = "HR_SpO2_{date}_{time}.csv"
# Message keys in the decoded output are the profile's plural "messages_key".
MESG_KEYS = {
    "monitoring": "monitoring_mesgs",
    "spo2_data": "spo2_data_mesgs",
    "hsa_spo2_data": "hsa_spo2_data_mesgs",
}


@dataclass
class Samples:
    """Raw samples using seconds since the FIT epoch (UTC)."""

    hr: list[tuple[int, int]] = field(default_factory=list)
    spo2: list[tuple[int, int]] = field(default_factory=list)
    message_counts: Counter = field(default_factory=Counter)

    def extend(self, other: "Samples") -> None:
        self.hr.extend(other.hr)
        self.spo2.extend(other.spo2)
        self.message_counts.update(other.message_counts)


def iter_fit_files(path: Path) -> Iterator[tuple[str, bytes]]:
    """Yield ``(display_name, data)`` for every FIT file below ``path``."""
    path = path.expanduser()
    if not path.exists():
        raise SystemExit(f"Input not found: {path}")

    if path.is_dir():
        for fit_path in sorted(path.rglob("*")):
            if fit_path.is_file() and fit_path.suffix.lower() == ".fit":
                yield str(fit_path.relative_to(path)), fit_path.read_bytes()
        return

    suffix = path.suffix.lower()
    if suffix == ".zip":
        with zipfile.ZipFile(path) as archive:
            for info in archive.infolist():
                if info.is_dir() or not info.filename.lower().endswith(".fit"):
                    continue
                yield info.filename, archive.read(info)
        return

    if suffix == ".fit":
        yield path.name, path.read_bytes()
        return

    raise SystemExit(
        f"Unsupported input: {path}. Pass a Garmin export .zip, a directory "
        "containing .fit files, or a single .fit file."
    )


def reconstruct_timestamp16(last_full_ts: int | None, timestamp16: int) -> int | None:
    """Rebuild a full FIT timestamp from its low 16 bits.

    FIT monitoring messages usually carry only ``timestamp_16``. The high bits
    come from the most recent full timestamp, choosing the candidate within
    +/- 32768 seconds (the 16-bit ambiguity window).
    """
    if last_full_ts is None:
        return None
    candidate = (last_full_ts & ~0xFFFF) | (timestamp16 & 0xFFFF)
    if candidate < last_full_ts - TIMESTAMP_16_HALF:
        candidate += TIMESTAMP_16_MOD
    elif candidate > last_full_ts + TIMESTAMP_16_HALF:
        candidate -= TIMESTAMP_16_MOD
    return candidate % UINT32


def _valid_hr(value: object) -> bool:
    return isinstance(value, int) and 1 <= value <= 255


def _valid_spo2(value: object) -> bool:
    return isinstance(value, int) and 1 <= value <= 100


def _as_values(value: object) -> list:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def extract_samples(messages: dict) -> Samples:
    """Collect HR and SpO2 samples from decoded FIT messages."""
    samples = Samples()

    for key in messages:
        samples.message_counts[key] = len(messages[key] or [])

    last_full_ts: int | None = None
    for message in messages.get(MESG_KEYS["monitoring"]) or []:
        ts = message.get("timestamp")
        if isinstance(ts, int) and ts > 0:
            last_full_ts = ts
        else:
            ts16 = message.get("timestamp_16")
            if isinstance(ts16, int):
                ts = reconstruct_timestamp16(last_full_ts, ts16)
                if ts is not None:
                    last_full_ts = ts
            else:
                ts = None

        heart_rate = message.get("heart_rate")
        if ts is None or ts <= 0 or not _valid_hr(heart_rate):
            continue
        samples.hr.append((ts, heart_rate))

    for message in messages.get(MESG_KEYS["spo2_data"]) or []:
        ts = message.get("timestamp")
        reading = message.get("reading_spo2")
        if isinstance(ts, int) and ts > 0 and _valid_spo2(reading):
            samples.spo2.append((ts, reading))

    for message in messages.get(MESG_KEYS["hsa_spo2_data"]) or []:
        ts = message.get("timestamp")
        if not isinstance(ts, int) or ts <= 0:
            continue
        interval = message.get("processing_interval") or 0
        if not isinstance(interval, int) or interval < 0:
            interval = 0
        for index, reading in enumerate(_as_values(message.get("reading_spo2"))):
            if _valid_spo2(reading):
                samples.spo2.append((ts + index * interval, reading))

    return samples


def decode_fit(data: bytes) -> tuple[dict, list]:
    """Decode one FIT file, returning the messages and any decoder errors."""
    try:
        from garmin_fit_sdk import Decoder, Stream
    except ImportError as exc:  # pragma: no cover - depends on the environment
        raise SystemExit(
            "garmin-fit-sdk is required. Install it with:\n"
            "    python3 -m pip install -r tools/requirements.txt"
        ) from exc

    stream = Stream.from_byte_array(bytearray(data))
    decoder = Decoder(stream)
    return decoder.read(
        apply_scale_and_offset=True,
        # Keep timestamps as raw FIT seconds so timestamp_16 reconstruction and
        # merging stay integer-exact.
        convert_datetimes_to_dates=False,
        convert_types_to_strings=False,
        expand_sub_fields=True,
        expand_components=True,
        merge_heart_rates=False,
    )


def merge_samples(samples: Samples) -> dict[int, dict[str, int]]:
    """Combine HR and SpO2 samples by timestamp, keeping one row per second."""
    merged: dict[int, dict[str, int]] = {}
    for ts, value in samples.hr:
        merged.setdefault(ts, {})["hr"] = value
    for ts, value in samples.spo2:
        merged.setdefault(ts, {})["spo2"] = value
    return dict(sorted(merged.items()))


def utc_datetime(ts: int) -> datetime:
    return FIT_EPOCH + timedelta(seconds=ts)


def local_datetime(ts: int, tz: timezone | ZoneInfo | None) -> datetime:
    utc = utc_datetime(ts)
    # ``astimezone(None)`` uses the platform's local rules for that instant,
    # which keeps historical daylight-saving transitions correct.
    return utc.astimezone(tz) if tz is not None else utc.astimezone()


def format_utc(ts: int) -> str:
    return utc_datetime(ts).strftime("%Y-%m-%dT%H:%M:%SZ")


def format_local(ts: int, tz: timezone | ZoneInfo | None) -> str:
    return local_datetime(ts, tz).isoformat(timespec="seconds")


def render_filename(template: str, day: date, first_ts: int, tz: timezone | ZoneInfo | None) -> str:
    first_local = local_datetime(first_ts, tz)
    return template.format(date=day.isoformat(), time=first_local.strftime("%H%M%S"))


def _parse_utc(value: str) -> int | None:
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None
    return int((parsed - FIT_EPOCH).total_seconds())


def read_existing_rows(path: Path) -> dict[int, dict[str, str]]:
    """Read a CSV written by this tool so a rerun can merge into it."""
    rows: dict[int, dict[str, str]] = {}
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            if not reader.fieldnames or not set(HEADER).issubset(reader.fieldnames):
                return rows
            for row in reader:
                ts = _parse_utc(row.get("timestamp_utc", ""))
                if ts is None:
                    continue
                rows[ts] = {"hr": row.get("hr_bpm", ""), "spo2": row.get("spo2_pct", "")}
    except (OSError, csv.Error, UnicodeDecodeError):
        return rows
    return rows


def write_day_file(
    path: Path,
    rows: dict[int, dict],
    tz: timezone | ZoneInfo | None,
    existing: dict[int, dict[str, str]] | None = None,
) -> int:
    """Write one day of rows, optionally merging previously written rows."""
    merged: dict[int, dict[str, str]] = {}
    for ts, values in (existing or {}).items():
        merged[ts] = dict(values)
    for ts, values in rows.items():
        merged[ts] = {
            "hr": "" if values.get("hr") is None else str(values["hr"]),
            "spo2": "" if values.get("spo2") is None else str(values["spo2"]),
        }

    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(HEADER)
        for ts in sorted(merged):
            values = merged[ts]
            writer.writerow(
                [
                    format_utc(ts),
                    format_local(ts, tz),
                    values.get("hr", ""),
                    values.get("spo2", ""),
                ]
            )
    return len(merged)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="export_health.py",
        description=(
            "Export heart rate and SpO2 history from Garmin FIT files to one "
            "CSV per local day."
        ),
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Garmin Connect export .zip, a directory of FIT files, or one .fit file",
    )
    parser.add_argument(
        "-o",
        "--outdir",
        type=Path,
        default=Path("health_export"),
        help="output directory (default: health_export)",
    )
    parser.add_argument(
        "--template",
        default=DEFAULT_TEMPLATE,
        help=f"output filename template (default: {DEFAULT_TEMPLATE})",
    )
    parser.add_argument(
        "--tz",
        metavar="ZONE",
        help="IANA timezone for local timestamps and daily rollover "
        "(default: this computer's local timezone)",
    )
    parser.add_argument(
        "--merge",
        action="store_true",
        help="merge into existing CSVs for the same day instead of overwriting",
    )
    parser.add_argument(
        "--inspect",
        action="store_true",
        help="only report the FIT message types and samples found; write no files",
    )
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if "{date}" not in args.template:
        parser.error("--template must contain {date} so files roll over daily")
    try:
        args.template.format(date="2000-01-01", time="000000")
    except (KeyError, IndexError, ValueError) as exc:
        parser.error(f"invalid --template: {exc}")

    tz: timezone | ZoneInfo | None
    if args.tz:
        try:
            tz = ZoneInfo(args.tz)
        except (ZoneInfoNotFoundError, ValueError):
            parser.error(f"unknown timezone: {args.tz}")
    else:
        tz = None

    total = Samples()
    file_count = 0
    failed: list[tuple[str, str]] = []

    for name, data in iter_fit_files(args.input):
        file_count += 1
        try:
            messages, errors = decode_fit(data)
        except Exception as exc:  # corrupt/unsupported file
            failed.append((name, str(exc)))
            continue

        if errors:
            failed.append((name, str(errors[0])))

        samples = extract_samples(messages)
        total.extend(samples)
        if not samples.hr and not samples.spo2:
            print(f"warning: no HR or SpO2 samples in {name}", file=sys.stderr)

    if file_count == 0:
        print("No .fit files found in the input.", file=sys.stderr)
        return 1

    if failed:
        print(f"{len(failed)} file(s) reported decode errors:", file=sys.stderr)
        for name, error in failed:
            print(f"  {name}: {error}", file=sys.stderr)

    if args.inspect:
        print(f"Read {file_count} FIT file(s)")
        print("Message types found:")
        if total.message_counts:
            for key, count in sorted(total.message_counts.items()):
                print(f"  {key:<28} {count:>8}")
        else:
            print("  (none)")
        print(f"HR samples:   {len(total.hr):,}")
        print(f"SpO2 samples: {len(total.spo2):,}")
        if total.hr:
            print(f"HR range:     {format_utc(min(t for t, _ in total.hr))} .. "
                  f"{format_utc(max(t for t, _ in total.hr))}")
        if total.spo2:
            print(f"SpO2 range:   {format_utc(min(t for t, _ in total.spo2))} .. "
                  f"{format_utc(max(t for t, _ in total.spo2))}")
        return 0 if (total.hr or total.spo2) else 1

    if not total.hr and not total.spo2:
        print(
            "No heart rate or SpO2 samples found. Run with --inspect to see "
            "which FIT messages the files contain.",
            file=sys.stderr,
        )
        return 1

    merged = merge_samples(total)
    by_day: dict[date, dict[int, dict]] = defaultdict(dict)
    for ts, values in merged.items():
        by_day[local_datetime(ts, tz).date()][ts] = values

    args.outdir.mkdir(parents=True, exist_ok=True)
    written: list[tuple[Path, int]] = []
    for day in sorted(by_day):
        day_rows = by_day[day]
        first_ts = min(day_rows)
        name = render_filename(args.template, day, first_ts, tz)
        path = args.outdir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        existing = None
        if args.merge:
            existing = read_existing_rows(path)
            # Also pick up an earlier name for the same day, in case a previous
            # run saw a different first sample time.
            day_glob = args.template.format(date=day.isoformat(), time="*")
            for other in args.outdir.glob(day_glob):
                if other != path:
                    for ts, values in read_existing_rows(other).items():
                        existing.setdefault(ts, values)
        written.append((path, write_day_file(path, day_rows, tz, existing)))

    print(
        f"Read {file_count} FIT file(s): {len(total.hr):,} HR samples, "
        f"{len(total.spo2):,} SpO2 samples"
    )
    print(f"Wrote {len(written)} file(s) to {args.outdir}:")
    for path, count in written:
        print(f"  {path.name}  {count:,} rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
