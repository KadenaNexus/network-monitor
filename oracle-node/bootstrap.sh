#!/usr/bin/env bash
set -euo pipefail
snapshot=2026-10-07
data=/var/lib/chainweb
if [[ -f "$data/.snapshot-verified" ]]; then
  echo "Snapshot previously verified; preserving running node databases."
  exit 0
fi
free=$(df --output=avail -B1 "$data" | tail -1)
(( free > 85000000000 )) || { echo "Need at least 85 GB free for initial snapshot"; exit 1; }
echo "Downloading official compacted snapshot for $snapshot"
aria2c --continue=true --max-concurrent-downloads=4 --max-connection-per-server=8 \
  --split=8 --min-split-size=32M --file-allocation=none \
  --auto-file-renaming=false --allow-overwrite=true --max-tries=5 \
  --retry-wait=5 --connect-timeout=30 --timeout=120 --summary-interval=60 \
  --console-log-level=warn --download-result=hide --show-console-readout=false \
  --input-file=/etc/chainweb/snapshot-downloads.txt
for db in rocksDb sqlite; do
  curl --fail --silent --show-error --retry 3 "https://snapshots.chainweb-community.org/snapshots/compacted/$snapshot/0/$db/BLAKE2SUMS" -o "$data/0/$db/BLAKE2SUMS.https"
  (cd "$data/0/$db" && b2sum --quiet -c BLAKE2SUMS.https)
done
printf '%s\n' "$snapshot compacted snapshot verified with BLAKE2 manifests over HTTPS" > "$data/.snapshot-verified"
echo "Snapshot checksums verified. Node may start."
