#!/usr/bin/env python3
"""Record native Capture RSS and evaluate explicitly marked scenarios without driving UI."""

import argparse
import datetime
import json
import math
import pathlib
import re
import statistics
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
POLICY = ROOT / "docs/plans/capture-evidence/memory-policy-v3.json"


def write(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def processes():
    result = []
    output = subprocess.check_output(["ps", "-axo", "pid=,ppid=,rss=,comm="], text=True)
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) == 4:
            result.append((int(fields[0]), int(fields[1]), int(fields[2]) * 1024, fields[3]))
    return result


def record(args):
    if not 0.02 <= args.interval <= 1:
        raise ValueError("Sampling interval must be between 0.02 and 1 second")
    matches = [p for p in processes() if p[3] == args.executable]
    if len(matches) != 1:
        raise ValueError("Expected exactly one process with the supplied executable path")
    pid = matches[0][0]
    bundle = args.executable.split("/Contents/MacOS/")[0] + "/Contents/"
    rows, started = [], time.monotonic()
    try:
        while time.monotonic() - started < args.seconds:
            stage = args.stage_file.read_text().strip()
            if stage == "stop":
                break
            snapshot = processes()
            main = next((p[2] for p in snapshot if p[0] == pid), None)
            if main is None:
                raise ValueError("Measured app exited; this run is incomplete")
            owned = {pid}
            for _ in range(len(snapshot)):
                children = {p[0] for p in snapshot if p[1] in owned and p[3].startswith(bundle)}
                if children.issubset(owned):
                    break
                owned.update(children)
            helper = sum(p[2] for p in snapshot if p[0] in owned and p[0] != pid)
            rows.append({"at": time.time(), "seconds": time.monotonic() - started,
                         "stage": stage, "pid": pid, "mainRSS": main, "helperRSS": helper,
                         "totalRSS": main + helper})
            if len(rows) % 5 == 0:
                write(args.output, rows)
            time.sleep(args.interval)
    finally:
        write(args.output, rows)
    print(json.dumps({"pid": pid, "samples": len(rows), "output": str(args.output)}))


def report(args):
    policy = json.loads(POLICY.read_text())
    rows = json.loads(args.samples.read_text())
    if not rows or len({r["pid"] for r in rows}) != 1:
        raise ValueError("Expected samples from exactly one app run")
    if any(r["totalRSS"] != r["mainRSS"] + r["helperRSS"] for r in rows):
        raise ValueError("Concurrent total does not match main + helper")
    if any(b["seconds"] <= a["seconds"] for a, b in zip(rows, rows[1:])):
        raise ValueError("Sample times must increase monotonically")
    baseline = [r for r in rows if r["stage"] == "cold-baseline"]
    baseline_seconds = baseline[-1]["seconds"] - baseline[0]["seconds"] if baseline else 0
    cold = (statistics.median(r["totalRSS"] for r in baseline)
            if baseline_seconds >= policy["baselineMinimumSeconds"] else None)
    peak = max(r["totalRSS"] for r in rows)
    result = {"policyVersion": policy["version"], "scenario": args.scenario,
              "samples": len(rows), "mainPeak": max(r["mainRSS"] for r in rows),
              "helperPeak": max(r["helperRSS"] for r in rows), "concurrentPeak": peak,
              "peakPassed": peak <= policy["peakMaximum"][args.scenario], "coldBaseline": cold,
              "baselineSeconds": baseline_seconds,
              "coldPassed": cold <= policy["coldIdleMaximum"] if cold is not None else None,
              "recovery": [], "cyclesPassed": None}
    groups = {}
    for row in rows:
        if row["stage"].endswith("closed"):
            groups.setdefault(row["stage"], []).append(row)
    anchors = {}
    if args.native_closures:
        if not args.log:
            raise ValueError("Native closures require a log stream in ndjson format")
        for line in args.log.read_text().splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if (event.get("processID") == rows[0]["pid"]
                    and event.get("category") == "CapturePerformance"
                    and event.get("eventMessage") == args.closure_event):
                anchor = datetime.datetime.fromisoformat(event["timestamp"]).timestamp()
                if rows[0]["at"] <= anchor <= rows[-1]["at"]:
                    anchors[f"cycle-{len(anchors) + 1:02}-closed"] = anchor
        groups = {stage: rows for stage in anchors}
        result["nativeClosureCount"] = len(anchors)
        result["nativeClosureEvent"] = args.closure_event
    for stage, values in groups.items():
        if stage in anchors:
            window = [r for r in values if policy["recoverySeconds"] <= r["at"] - anchors[stage] <= 6]
        else:
            window = [r for r in values
                      if policy["recoverySeconds"] <= r["seconds"] - values[0]["seconds"] <= 6]
        maximum = max(r["totalRSS"] for r in window) if window else None
        helpers_exited = all(r["helperRSS"] == 0 for r in window) if window else None
        passed = (maximum <= min(policy["recoveryAbsoluteMaximum"][args.scenario],
                                 cold + policy["recoveryAboveColdMaximum"][args.scenario]) and helpers_exited
                  if maximum is not None and cold is not None else None)
        result["recovery"].append({"stage": stage, "maximumAtFiveSeconds": maximum,
                                   "helpersExitedAtFiveSeconds": helpers_exited, "passed": passed,
                                   "nativeCloseTimestamp": anchors.get(stage), "samplesInWindow": len(window)})
    cycles = {r["stage"]: r["maximumAtFiveSeconds"] for r in result["recovery"]}
    cycle_values = [cycles.get(f"cycle-{i:02}-closed") for i in range(1, policy["cycleCount"] + 1)]
    if all(value is not None for value in cycle_values):
        growth = statistics.median(cycle_values[-5:]) - statistics.median(cycle_values[5:10])
        recovered = [r["passed"] for r in result["recovery"] if r["stage"].startswith("cycle-")]
        result.update(warmedGrowth=growth,
                      cyclesPassed=(growth <= policy["warmedCycleGrowthMaximum"] and all(recovered)
                                    if all(value is not None for value in recovered) else None))
    checks = [result["coldPassed"], result["peakPassed"], result["cyclesPassed"]]
    checks.extend(r["passed"] for r in result["recovery"])
    result["resourcePassed"] = False if False in checks else None if None in checks else True
    if args.log:
        logs = args.log.read_text()
        result["latency"] = {}
        for event in ("selection-ready", "scroll-preview-ready"):
            values = sorted(float(v) for v in re.findall(event + r" milliseconds=(\d+(?:\.\d+)?)", logs))
            p95 = values[math.ceil(len(values) * 0.95) - 1] if values else None
            result["latency"][event] = {"count": len(values), "p95Milliseconds": p95,
                "passed": (p95 < policy["latencyP95Milliseconds"]
                           if len(values) >= policy["minimumLatencySamples"] else None)}
    write(args.output, result)
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("record")
    capture.add_argument("--executable", required=True)
    capture.add_argument("--stage-file", type=pathlib.Path, required=True)
    capture.add_argument("--seconds", type=int, default=1800)
    capture.add_argument("--interval", type=float, default=0.2)
    capture.add_argument("--output", type=pathlib.Path, required=True)
    evaluate = commands.add_parser("report")
    evaluate.add_argument("--samples", type=pathlib.Path, required=True)
    evaluate.add_argument("--scenario", choices=("ordinary", "image", "video"), required=True)
    evaluate.add_argument("--log", type=pathlib.Path)
    evaluate.add_argument("--native-closures", action="store_true")
    evaluate.add_argument("--closure-event", choices=("workspace-closed", "copy-closed", "pins-closed"),
                          default="workspace-closed")
    evaluate.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    (record if args.command == "record" else report)(args)


if __name__ == "__main__":
    main()
