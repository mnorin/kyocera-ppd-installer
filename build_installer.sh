#!/usr/bin/env bash
# Builds kyocera_ppds_installer.sh: install.sh with the driver files appended,
# so the installer is a single file that can be downloaded and run.
#
# Usage: build_installer.sh [output-file]

set -euo pipefail
cd "$(dirname "$0")"

OUT=${1:-kyocera_ppds_installer.sh}
FILES=(Kyocera_FS-*GDI.ppd rastertokpsl_32 rastertokpsl_64 rastertokpsl_wrapper)

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# Fixed owner, order and timestamps, so the output only changes when a file does.
{
    cat install.sh
    echo "__PAYLOAD_BELOW__"
    tar -c --owner=0 --group=0 --numeric-owner --sort=name --mtime='2020-01-01 00:00Z' "${FILES[@]}" |
        gzip -9n | base64
} > "$tmp"

chmod 755 "$tmp"
mv "$tmp" "$OUT"
trap - EXIT
echo "Built $OUT"
