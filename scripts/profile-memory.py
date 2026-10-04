#!/usr/bin/env python3
"""Cold-start physical-footprint measurements; quit existing Endfield Charge instances first."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--single-process-settings", action="store_true", help="Measure an older build with settings in the resident")
parser.add_argument("--telemetry", action="store_true", help="Also measure telemetry and resident after its UI helper exits")
arguments = parser.parse_args()
binary = arguments.binary.resolve()
result = {"binary": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
          "metric": "sum of ri_phys_footprint for parent and direct children", "interval_seconds": 0.2,
          "cpu_time_unit": "nanoseconds converted from Mach absolute time; 100% means one core",
          "launch_settle_seconds": 0.3, "runs": []}
with tempfile.TemporaryDirectory(prefix="endfield-memory-") as directory:
    probe = Path(directory) / "probe"
    subprocess.run(["clang", "-O2", str(Path(__file__).with_suffix(".c")), "-o", str(probe)], check=True)
    scenarios = [("idle", [], 25), ("settings", ["--settings"], 25), ("animation", ["--demo"], 40)]
    if arguments.telemetry:
        scenarios.append(("telemetry", ["--telemetry"], 25))
    for scenario, flags, samples in scenarios:
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
                expected = 2 if scenario == "telemetry" or (scenario == "settings" and not arguments.single_process_settings) else 1
                if len(data[-1]["members"]) != expected:
                    raise RuntimeError(f"Expected {expected} app processes in {scenario}; measurement was interrupted or helper missing")
                result["runs"].append({"scenario": scenario, "run": run, "samples": data})
                arguments.output.write_text(json.dumps(result, indent=2) + "\n")
                print(json.dumps({"scenario": scenario, "run": run,
                                  "last_MiB": round(data[-1]["footprint_bytes"] / 1048576, 2),
                                  "sampled_peak_MiB": round(max(row["footprint_bytes"] for row in data) / 1048576, 2)}), flush=True)
                if scenario == "telemetry":
                    # The native runtime suite separately verifies actual window-close/acknowledgment.
                    # Terminate only this run's helper here to measure cache release without UI automation.
                    for member in data[-1]["members"]:
                        if member["pid"] != process.pid:
                            os.kill(member["pid"], signal.SIGTERM)
                    time.sleep(0.5)
                    closed = subprocess.run([str(probe), str(process.pid), "25"], capture_output=True, text=True, check=True)
                    closed_data = [json.loads(line) for line in closed.stdout.splitlines()]
                    if process.poll() is not None or any(len(row["members"]) != 1 or row["members"][0]["pid"] != process.pid for row in closed_data):
                        raise RuntimeError("Telemetry helper did not exit or resident was lost")
                    result["runs"].append({"scenario": "telemetry_helper_exited", "run": run,
                        "closure_method": "SIGTERM to the owned helper; native suite verifies UI close separately", "samples": closed_data})
                    arguments.output.write_text(json.dumps(result, indent=2) + "\n")
                    print(json.dumps({"scenario": "telemetry_helper_exited", "run": run,
                        "last_MiB": round(closed_data[-1]["footprint_bytes"] / 1048576, 2)}), flush=True)
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
                # The child observes stdin EOF when the parent dies and exits independently.
                time.sleep(0.3)
for scenario in dict.fromkeys(run["scenario"] for run in result["runs"]):
    readings = [run["samples"][-1]["footprint_bytes"] / 1048576 for run in result["runs"] if run["scenario"] == scenario]
    print(f"{scenario}: median last sample {statistics.median(readings):.2f} MiB", flush=True)
