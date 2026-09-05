#!/bin/bash
# Drive tests/run-api-tests.sh against a LuneOS VirtualBox emulator from the host.
#
# Usage: tests/run-on-vm.sh [ssh-port]   (default port 5522, root@localhost)
#
# Serves tests/fixtures/ over http on port 8931 so the emulator can reach the
# OpenSearch fixture at http://10.0.2.2:8931/opensearch-test.xml, then copies
# and runs the on-device suite. Exit code = number of failed assertions.
set -u
PORT=${1:-5522}
HTTP_PORT=8931
DIR=$(cd "$(dirname "$0")" && pwd)
SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

python3 -m http.server $HTTP_PORT --bind 0.0.0.0 --directory "$DIR/fixtures" >/dev/null 2>&1 &
HTTPPID=$!
trap 'kill $HTTPPID 2>/dev/null' EXIT
sleep 1

scp -q $SSHOPTS -P $PORT "$DIR/run-api-tests.sh" root@localhost:/tmp/run-api-tests.sh
ssh -tt $SSHOPTS -p $PORT root@localhost \
    "sh /tmp/run-api-tests.sh http://10.0.2.2:$HTTP_PORT/opensearch-test.xml; rc=\$?; rm -f /tmp/run-api-tests.sh; exit \$rc"
rc=$?
exit $rc
