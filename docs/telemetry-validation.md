# Telemetry extension verification

Approved scope: POWER, COMPUTE and THERMAL, preserving the original Endfield power HUD. Network monitoring and long-term history are not implemented in this phase.

## Result and semantics

- POWER: approximate signed battery-side W, adapter-reported W, cycles and recent elapsed-weighted discharge average. Adapter output rating is distinct from battery/system draw. The average holds prior observed W until the next sample, covers at most 5 minutes/150 intervals, and resets on charging, unavailable readings or gaps over 60 seconds.
- COMPUTE: CPU tick differences; approximate physical memory = active + wired + physical compressor pages, scaled by the actual page size; compressor bytes, Swap and system pressure. The estimate is not Activity Monitor's Memory Used. First CPU sample/reset is unknown.
- THERMAL: public ProcessInfo state, not a measured CPU temperature. Alerts skip initial state, avoid repeated/downgraded warnings, allow an upgrade to critical and rearm after cooling.
- One additional resident timer: 2 seconds visible, 30 seconds hidden/minimized/closed; all three modules disabled stops it. Readers use native Mach/IOKit/Foundation/sysctl and release their returned resources.
- An on-demand child owns the native terminal, fonts and up to 300 graph points. It receives one snapshot per IPC message. Close acknowledgment, final frame/tab, rapid reopen, parent EOF and fallback exit reuse the settings lifecycle. The terminal never overwrites resident preferences from its disk cache.

## Verification

31 core tests passed. The initial telemetry implementation produced 17 expected red assertions before the CPU/current/average/alert algorithms were implemented. Legacy preference migration preserves the existing values and defaults new toggles to enabled.

All 12 native runtime groups passed, including all five settings pages and three terminal pages, native selector actions, the bounded graph, 2.52 s/Reduce Motion 0.15 s header timer stop, view/window/monitor release, visible/background sampling, disabled modules, ordered/fragmented pipe messages, actual child preview/close acknowledgment/reopen/tab/frame, minimize/hide/restore notifications and natural exit on parent pipe EOF. Checks use independent preference domains. A live legacy battery update with all modules disabled changes the child header without adding a new graph point or waking another collector.

Final universal app contains arm64 and x86_64 with macOS 13.0 deployment target. Strict ad-hoc signature verification, archive integrity, every extracted file's byte equality and unchanged baseline resources passed. The installed preference blob was unchanged, including Command + Shift + E. On the actual running final app, direct `--telemetry` exited successfully, kept the existing resident PID and created exactly one terminal child.

Every POWER/COMPUTE/THERMAL page was exported with real and visibly labeled fixture data, plus Reduce Motion. The normal POWER opening was exported at 0.5, 1.55 and 2.35 s. Final layout review found no clipped rows/footers; the selector uses explicit charcoal/lime drawing because macOS 27 ignored native selectedSegmentBezelColor. It keeps native selection/keyboard/accessibility behavior. The original power HUD PNGs at 1.55 and 3 s remained byte-identical to the pre-extension build.

Real sample checks matched 16 GiB physical memory, 16 KiB pages, the system Swap/pressure query and battery cycle/voltage/current/adapter fields. These counters are sampled at different instants, so variable memory/CPU values are not expected to be byte-identical to later OS reads. Missing registry/sysctl fields remain unknown. No exact-temperature, battery-health or fast-charge claim is made.

## Footprint

Three cold starts per scenario on this MacBook Air M5, macOS 27. Metric: sum of `ri_phys_footprint` for resident and direct UI children, sampled every 200 ms after 300 ms launch settling. Values below are medians of final samples; peaks are maximum observed samples across the three runs.

| Scenario | Pre-extension | Telemetry build | Telemetry sampled peak |
| --- | ---: | ---: | ---: |
| Idle resident | 11.20 MiB | 11.36 MiB | 11.49 MiB |
| Settings open, both processes | 42.55 MiB | 41.97 MiB | 43.24 MiB |
| Original animation finished | 14.33 MiB | 14.44 MiB | 16.39 MiB |
| Terminal open, both processes | — | 55.63 MiB | 98.05 MiB |
| Terminal helper exited | — | 11.30 MiB | 11.52 MiB |

The terminal's larger window and initial native drawing caches have a transient opening cost. It does not remain in the resident after the UI process exits. For the footprint experiment, only that run's owned helper was sent SIGTERM; actual window close/acknowledgment was separately verified by the native suite. A three-run attempt to isolate the header into a backing layer did not reduce footprint reliably and broke offscreen header export; it was reverted. The final battery-forwarding fix was packaged and all three-run scenarios remeasured; its SHA matches the final capture.

Short stable-tail CPU windows showed about 0.39% of one core for the open terminal; this is a sampled development observation, not a long-duration idle or battery-life benchmark. `rusage_info` time uses Mach absolute units on this ARM host: 4,761,708 ticks × 125/3 ns matched getrusage's 0.198404 s in a local busy-loop calibration. The profiler now converts through mach_timebase_info, and the earlier baseline capture’s CPU fields were normalized; physical-footprint samples were unchanged.

Final local artifact: executable 980,288 B; `.app` disk allocation 1,136 KiB; ZIP 490,449 B. No extra package/runtime or sampler subprocess is included. The measurement script and compressed sample data are developer artifacts, not runtime resources.

Artifact hashes, source-file fingerprints, run-level summaries and full compressed samples are in [telemetry-measurements.json](telemetry-measurements.json) and [telemetry-samples.json.gz](telemetry-samples.json.gz). The results can vary with display scaling, OS drawing caches and system memory pressure; neither these finite samples nor the 200 ms peaks establish a global worst-case bound. Ad-hoc signing does not imply Developer ID signing or notarization.

## Review

Independent review found two functional issues: minimize/hide did not slow the resident sampler, and direct `--telemetry` could not reach an already-running resident. Both were repaired and re-reviewed; the native visibility sequence and real resident CLI test verified the resulting behavior. The fixed-action local request is addressed to the resident PID, handled on the main queue and accepts no paths, arbitrary arguments or preference edits.

The final eight-line legacy battery forwarding fix was independently reviewed with no concrete P1/P2 finding. It updates only the cached battery fields, preserves the telemetry sample timestamp, honors the closing send gate and introduces no timer or additional collection.

## Published source

Final application source: `b1e77d18e2072420be09fbc196e5f3b00c63713b`. Its [GitHub macOS build](https://github.com/MarkYang44/Endfield-Charge/actions/runs/37219089147) completed successfully, including core tests, universal app packaging and artifact upload. Later documentation-only commits do not change the measured executable. Source fingerprints and the local artifact hash were checked against this commit.
