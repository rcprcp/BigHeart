#!/usr/bin/env python3
"""Tests for tools/export_health.py.

Run from the project root:
    python3 -m unittest tools.test_export_health -v

The end-to-end tests need garmin-fit-sdk and are skipped when it is missing.
"""

from __future__ import annotations

import csv
import importlib.util
import io
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import export_health as eh  # noqa: E402

HAVE_SDK = importlib.util.find_spec("garmin_fit_sdk") is not None


def fit_ts(value: datetime) -> int:
    return int((value - eh.FIT_EPOCH).total_seconds())


class ReconstructTimestamp16Test(unittest.TestCase):
    def test_needs_a_full_timestamp(self):
        self.assertIsNone(eh.reconstruct_timestamp16(None, 1234))

    def test_keeps_high_bits_for_a_nearby_sample(self):
        last = 1_000_000_000
        self.assertEqual(
            eh.reconstruct_timestamp16(last, (last + 60) & 0xFFFF),
            last + 60,
        )

    def test_wraps_forward_across_16_bits(self):
        last = 0x0000FFF0
        self.assertEqual(eh.reconstruct_timestamp16(last, 0x0010), last + 0x20)

    def test_wraps_backward_across_16_bits(self):
        last = 0x00010010
        self.assertEqual(eh.reconstruct_timestamp16(last, 0xFFF0), last - 0x20)


class ExtractSamplesTest(unittest.TestCase):
    def test_monitoring_full_and_16_bit_timestamps(self):
        messages = {
            "monitoring_mesgs": [
                {"timestamp": 1_000_000_000, "heart_rate": 70},
                {"timestamp_16": (1_000_000_060) & 0xFFFF, "heart_rate": 71},
            ]
        }
        samples = eh.extract_samples(messages)
        self.assertEqual(samples.hr, [(1_000_000_000, 70), (1_000_000_060, 71)])
        self.assertEqual(samples.spo2, [])

    def test_16_bit_timestamp_without_previous_full_is_skipped(self):
        messages = {
            "monitoring_mesgs": [{"timestamp_16": 1234, "heart_rate": 70}]
        }
        self.assertEqual(eh.extract_samples(messages).hr, [])

    def test_invalid_values_are_dropped(self):
        messages = {
            "monitoring_mesgs": [
                {"timestamp": 1000, "heart_rate": 0},
                {"timestamp": 1001, "heart_rate": 300},
                {"timestamp": 1002, "heart_rate": 65},
            ],
            "spo2_data_mesgs": [
                {"timestamp": 1000, "reading_spo2": 0},
                {"timestamp": 1001, "reading_spo2": 101},
                {"timestamp": 1002, "reading_spo2": 97},
            ],
        }
        samples = eh.extract_samples(messages)
        self.assertEqual(samples.hr, [(1002, 65)])
        self.assertEqual(samples.spo2, [(1002, 97)])

    def test_hsa_spo2_array_is_expanded_by_processing_interval(self):
        messages = {
            "hsa_spo2_data_mesgs": [
                {
                    "timestamp": 5000,
                    "processing_interval": 10,
                    "reading_spo2": [95, None, 96],
                }
            ]
        }
        samples = eh.extract_samples(messages)
        self.assertEqual(samples.spo2, [(5000, 95), (5020, 96)])

    def test_hsa_spo2_without_interval_uses_same_timestamp(self):
        messages = {
            "hsa_spo2_data_mesgs": [
                {"timestamp": 5000, "reading_spo2": [95, 96]}
            ]
        }
        self.assertEqual(
            eh.extract_samples(messages).spo2, [(5000, 95), (5000, 96)]
        )

    def test_counts_messages(self):
        messages = {
            "monitoring_mesgs": [{"timestamp": 1, "heart_rate": 60}],
            "spo2_data_mesgs": [],
            "record_mesgs": [{}, {}],
        }
        counts = eh.extract_samples(messages).message_counts
        self.assertEqual(counts["monitoring_mesgs"], 1)
        self.assertEqual(counts["record_mesgs"], 2)


class MergeSamplesTest(unittest.TestCase):
    def test_combines_hr_and_spo2_at_the_same_timestamp(self):
        samples = eh.Samples(hr=[(100, 60), (200, 61)], spo2=[(200, 96), (300, 97)])
        merged = eh.merge_samples(samples)
        self.assertEqual(
            merged,
            {100: {"hr": 60}, 200: {"hr": 61, "spo2": 96}, 300: {"spo2": 97}},
        )

    def test_duplicate_hr_keeps_the_last_value(self):
        samples = eh.Samples(hr=[(100, 60), (100, 62)])
        self.assertEqual(eh.merge_samples(samples), {100: {"hr": 62}})


class LocalTimeTest(unittest.TestCase):
    def test_rollover_uses_the_local_date(self):
        tz = timezone(timedelta(hours=-5))
        utc = datetime(2026, 11, 14, 3, 0, tzinfo=timezone.utc)
        local = eh.local_datetime(fit_ts(utc), tz)
        self.assertEqual(local.date().isoformat(), "2026-11-13")
        self.assertEqual(local.strftime("%H:%M:%S"), "22:00:00")

    def test_filename_template(self):
        tz = timezone(timedelta(hours=-5))
        ts = fit_ts(datetime(2026, 11, 13, 22, 5, 0, tzinfo=timezone.utc))
        name = eh.render_filename(
            eh.DEFAULT_TEMPLATE, datetime(2026, 11, 13).date(), ts, tz
        )
        self.assertEqual(name, "HR_SpO2_2026-11-13_170500.csv")

    def test_custom_template(self):
        ts = fit_ts(datetime(2026, 11, 13, 22, 5, 0, tzinfo=timezone.utc))
        name = eh.render_filename(
            "{date}-health.csv", datetime(2026, 11, 13).date(), ts, timezone.utc
        )
        self.assertEqual(name, "2026-11-13-health.csv")

    def test_template_must_contain_date(self):
        with self.assertRaises(SystemExit) as raised:
            eh.main(["missing.fit", "--template", "{time}.csv"])
        self.assertEqual(raised.exception.code, 2)


class WriteDayFileTest(unittest.TestCase):
    def test_writes_header_and_empty_missing_columns(self):
        tz = timezone.utc
        ts = fit_ts(datetime(2026, 11, 13, 12, 0, 0, tzinfo=timezone.utc))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "day.csv"
            rows = {ts: {"hr": 64}, ts + 60: {"spo2": 96}}
            count = eh.write_day_file(path, rows, tz)
            self.assertEqual(count, 2)
            lines = path.read_text().splitlines()
            self.assertEqual(lines[0], ",".join(eh.HEADER))
            self.assertEqual(lines[1], "2026-11-13T12:00:00Z,2026-11-13T12:00:00+00:00,64,")
            self.assertEqual(lines[2], "2026-11-13T12:01:00Z,2026-11-13T12:01:00+00:00,,96")

    def test_merge_keeps_existing_rows_and_prefers_new_values(self):
        tz = timezone.utc
        ts = fit_ts(datetime(2026, 11, 13, 12, 0, 0, tzinfo=timezone.utc))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "day.csv"
            eh.write_day_file(path, {ts: {"hr": 60}, ts + 60: {"spo2": 95}}, tz)
            existing = eh.read_existing_rows(path)
            count = eh.write_day_file(
                path, {ts: {"hr": 65}}, tz, existing=existing
            )
            self.assertEqual(count, 2)
            with path.open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(rows[0]["hr_bpm"], "65")
            self.assertEqual(rows[1]["spo2_pct"], "95")


class IterFitFilesTest(unittest.TestCase):
    def test_single_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.fit"
            path.write_bytes(b"data")
            self.assertEqual(list(eh.iter_fit_files(path)), [("a.fit", b"data")])

    def test_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "sub").mkdir()
            (root / "sub" / "b.fit").write_bytes(b"b")
            (root / "notes.txt").write_text("ignore me")
            self.assertEqual(list(eh.iter_fit_files(root)), [("sub/b.fit", b"b")])

    def test_zip_ignores_non_fit_entries(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "export.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("DI_CONNECT/2026_WELLNESS.fit", b"fit bytes")
                archive.writestr("readme.txt", "ignore me")
            self.assertEqual(
                list(eh.iter_fit_files(path)),
                [("DI_CONNECT/2026_WELLNESS.fit", b"fit bytes")],
            )


@unittest.skipUnless(HAVE_SDK, "garmin-fit-sdk is not installed")
class EndToEndTest(unittest.TestCase):
    def _write_fit(self, path: Path) -> tuple[int, int]:
        from garmin_fit_sdk import Encoder

        start = fit_ts(datetime(2026, 11, 13, 22, 5, 0, tzinfo=timezone.utc))
        encoder = Encoder()
        encoder.write_mesg(
            {
                "mesg_num": 0,
                "type": 4,
                "manufacturer": 1,
                "product": 1,
                "serial_number": 1,
                "time_created": start,
            }
        )
        encoder.write_mesg(
            {"mesg_num": 55, "timestamp": start, "heart_rate": 70}
        )
        encoder.write_mesg(
            {"mesg_num": 55, "timestamp_16": (start + 60) & 0xFFFF, "heart_rate": 71}
        )
        encoder.write_mesg(
            {
                "mesg_num": 269,
                "timestamp": start + 120,
                "reading_spo2": 96,
                "reading_confidence": 90,
            }
        )
        encoder.write_mesg(
            {
                "mesg_num": 305,
                "timestamp": start + 180,
                "processing_interval": 10,
                "reading_spo2": [95, 97],
                "confidence": [80, 80],
            }
        )
        path.write_bytes(encoder.close())
        return start, start + 120

    def test_decode_and_extract(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sample.fit"
            start, _ = self._write_fit(path)
            messages, errors = eh.decode_fit(path.read_bytes())
            self.assertEqual(errors, [])
            samples = eh.extract_samples(messages)
            self.assertEqual(
                samples.hr, [(start, 70), (start + 60, 71)]
            )
            self.assertEqual(
                samples.spo2,
                [(start + 120, 96), (start + 180, 95), (start + 190, 97)],
            )

    def test_main_writes_a_daily_csv(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sample.fit"
            start, _ = self._write_fit(path)
            outdir = Path(tmp) / "out"
            with redirect_stdout(io.StringIO()):
                rc = eh.main([str(path), "-o", str(outdir), "--tz", "UTC"])
            self.assertEqual(rc, 0)
            files = sorted(outdir.glob("*.csv"))
            self.assertEqual(len(files), 1)
            self.assertEqual(files[0].name, "HR_SpO2_2026-11-13_220500.csv")
            with files[0].open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 5)
            self.assertEqual(rows[0]["hr_bpm"], "70")
            self.assertEqual(rows[-1]["spo2_pct"], "97")

    def test_inspect_writes_no_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sample.fit"
            self._write_fit(path)
            outdir = Path(tmp) / "out"
            output = io.StringIO()
            with redirect_stdout(output):
                rc = eh.main([str(path), "-o", str(outdir), "--inspect"])
            self.assertEqual(rc, 0)
            self.assertFalse(outdir.exists())
            self.assertIn("monitoring_mesgs", output.getvalue())
            self.assertIn("HR samples:   2", output.getvalue())


if __name__ == "__main__":
    unittest.main()
