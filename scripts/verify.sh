#!/bin/bash
set -euo pipefail
usage() { echo 'Usage: bash scripts/verify.sh {core [--filter regex]|desktop {all|hud|telemetry|sharing|editors|ipc}|package|release}' >&2; exit 2; }
[[ $# -ge 1 ]] || usage
mode=$1
shift
case "$mode" in
  core) [[ $# == 0 || ( $# == 2 && "$1" == --filter && -n "$2" ) ]] || usage ;;
  desktop)
    [[ $# == 1 ]] || usage
    group=$1
    case "$group" in all|hud|telemetry|sharing|editors|ipc) ;; *) usage ;; esac ;;
  package|release) [[ $# == 0 ]] || usage ;;
  *) usage ;;
esac
cd "$(dirname "$0")/.."
case "$mode" in
  core) bash scripts/test.sh "$@" ;;
  desktop)
    if [[ "$group" == all ]]; then bash scripts/test.sh; fi
    bash scripts/check-runtime.sh --group "$group" ;;
  package) bash scripts/check-package.sh ;;
  release)
    bash scripts/test.sh
    bash scripts/check-runtime.sh --group all
    bash scripts/build-app.sh --universal
    bash scripts/check-package.sh ;;
esac
