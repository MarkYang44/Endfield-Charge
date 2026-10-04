#!/usr/bin/env python3
"""Cold-start physical-footprint measurements; quit existing Endfield Charge instances first."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--single-process-settings", action="store_true", help="Measure an older build with settings in the resident")
arguments = parser.parse_args()
binary = arguments.binary.resolve()
result = {"binary": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
          "metric": "sum of ri_phys_footprint for parent and direct children", "interval_seconds": 0.2,
          "launch_settle_seconds": 0.3, "runs": []}
with tempfile.TemporaryDirectory(prefix="endfield-memory-") as directory:
    probe = Path(directory) / "probe"
    subprocess.run(["clang", "-O2", str(Path(__file__).with_suffix(".c")), "-o", str(probe)], check=True)
    for scenario, flags, samples in [("idle", [], 25), ("settings", ["--settings"], 25),
                                      ("animation", ["--demo"], 40)]:
        for run in range(1, 4):
            process = subprocess.Popen([str(binary), *flags], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                time.sleep(0.3)
                reading = subprocess.run([str(probe), str(process.pid), str(samples)], capture_output=True, text=True, check=True)
                data = [json.loads(line) for line in reading.stdout.splitlines()]
                if not data or process.poll() is not None:
                    raise RuntimeError("App exited early; quit existing instances before measuring")
                if any(process.pid not in [member["pid"] for member in row["members"]] for row in data):
                    raise RuntimeError("Resident missing from a memory sample")
                expected = 2 if scenario == "settings" and not arguments.single_process_settings else 1
                if len(data[-1]["members"]) != expected:
                    raise RuntimeError(f"Expected {expected} app processes in {scenario}; measurement was interrupted or helper missing")
                result["runs"].append({"scenario": scenario, "run": run, "samples": data})
                arguments.output.write_text(json.dumps(result, indent=2) + "\n")
                print(json.dumps({"scenario": scenario, "run": run,
                                  "last_MiB": round(data[-1]["footprint_bytes"] / 1048576, 2),
                                  "sampled_peak_MiB": round(max(row["footprint_bytes"] for row in data) / 1048576, 2)}), flush=True)
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
                # The child observes stdin EOF when the parent dies and exits independently.
                time.sleep(0.3)
for scenario in ("idle", "settings", "animation"):
    readings = [run["samples"][-1]["footprint_bytes"] / 1048576 for run in result["runs"] if run["scenario"] == scenario]
    print(f"{scenario}: median last sample {statistics.median(readings):.2f} MiB", flush=True)
