#!/bin/sh
# Packs tests/fixtures/justtype-test-app into an ipk for the "app installed
# after boot" section of run-api-tests.sh. Runs on the build host (needs ar).
#
#   tests/make-test-ipk.sh <output.ipk>
set -e
OUT=${1:?usage: make-test-ipk.sh <output.ipk>}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT;; esac
SRC=$(cd "$(dirname "$0")/fixtures/justtype-test-app" && pwd)
ID=org.webosports.app.justtypetest
W=$(mktemp -d "${OUT%/*}/ipk.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/data/usr/palm/applications/$ID" "$W/control"
cp "$SRC"/* "$W/data/usr/palm/applications/$ID/"
cat > "$W/control/control" <<EOC
Package: $ID
Version: 1.0.0
Section: misc
Priority: optional
Architecture: all
Maintainer: webOS Ports
Description: universalsearch test fixture (Just Type app providers)
EOC
echo "2.0" > "$W/debian-binary"
tar -C "$W/control" --owner=0 --group=0 -czf "$W/control.tar.gz" .
tar -C "$W/data" --owner=0 --group=0 -czf "$W/data.tar.gz" .
rm -f "$OUT"
(cd "$W" && ar rc "$OUT" debian-binary control.tar.gz data.tar.gz)
echo "$OUT"
