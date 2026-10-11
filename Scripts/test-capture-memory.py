#!/usr/bin/env python3
"""Verify resource evidence isolation without sampling or driving native applications."""

import contextlib
import datetime
import importlib.util
import io
import json
import pathlib
import tempfile
import types
import unittest

SPEC = importlib.util.spec_from_file_location(
    "capture_memory", pathlib.Path(__file__).with_name("capture-memory.py"))
MEMORY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MEMORY)


class CaptureMemoryTests(unittest.TestCase):
    def test_reparented_helpers_and_external_children_are_counted(self):
        bundle = "/build/Tinycast Dev.app/Contents/"
        snapshot = [
            (10, 1, 100, bundle + "MacOS/Tinycast"),
            (11, 1, 20, bundle + "XPCServices/export"),
            (12, 10, 30, "/usr/bin/encoder"),
            (13, 12, 40, "/usr/bin/child"),
            (14, 11, 50, "/usr/bin/helper-child"),
            (15, 1, 60, "/Applications/Other.app/Contents/MacOS/Other"),
            (16, 1, 70, "/build/Tinycast Dev.app/ContentsElsewhere/other"),
        ]
        self.assertEqual(MEMORY.owned_processes(snapshot, 10, bundle), {10, 11, 12, 13, 14})

    def test_foreign_and_historical_logs_cannot_make_latency_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            rows = [{"pid": 10, "at": 1000 + i, "seconds": i,
                     "stage": "cold-baseline", "mainRSS": 100, "helperRSS": 0,
                     "totalRSS": 100} for i in range(21)]

            def event(pid, at, message, category="CapturePerformance"):
                return {"processID": pid, "timestamp": datetime.datetime.fromtimestamp(
                    at, datetime.timezone.utc).isoformat(), "category": category,
                    "eventMessage": message}

            events = [event(10, 1000 + i, "selection-ready milliseconds=700") for i in range(20)]
            events += [event(11, 1010, "selection-ready milliseconds=1") for _ in range(400)]
            events += [event(10, 999, "scroll-preview-ready milliseconds=1") for _ in range(20)]
            events += [event(10, 1021, "scroll-preview-ready milliseconds=1") for _ in range(20)]
            events += [event(10, 1010, "scroll-preview-ready milliseconds=1", "Other")]
            events += [event(10, 1010, "prefix selection-ready milliseconds=1")]
            events += [event(11, 1010, "workspace-closed"), event(10, 999, "workspace-closed"),
                       event(10, 1015, "workspace-closed"), event(10, 1005, "workspace-closed")]
            samples, log, output = root / "samples.json", root / "log.ndjson", root / "report.json"
            samples.write_text(json.dumps(rows))
            log.write_text("invalid json\n{}\n" + "\n".join(json.dumps(e) for e in events))
            args = types.SimpleNamespace(samples=samples, scenario="ordinary", log=log,
                                         native_closures=True, closure_event="workspace-closed",
                                         output=output)
            with contextlib.redirect_stdout(io.StringIO()):
                MEMORY.report(args)
            report = json.loads(output.read_text())
            selection = report["latency"]["selection-ready"]
            self.assertEqual(selection, {"count": 20, "p95Milliseconds": 700, "passed": False})
            self.assertEqual(report["latency"]["scroll-preview-ready"]["count"], 0)
            self.assertIsNone(report["latency"]["scroll-preview-ready"]["passed"])
            self.assertEqual(report["nativeClosureCount"], 2)
            self.assertEqual([r["nativeCloseTimestamp"] for r in report["recovery"]], [1005, 1015])


if __name__ == "__main__":
    unittest.main()
