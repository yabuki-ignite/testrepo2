#!/bin/sh
set -eu

if ! command -v pwsh >/dev/null 2>&1; then
    echo "PowerShell 7 (pwsh) is required but was not found on PATH." >&2
    exit 127
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec pwsh -NoLogo -NoProfile -File "$script_dir/download-discovered-artifact.ps1" "$@"
