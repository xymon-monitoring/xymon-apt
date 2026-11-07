#!/bin/sh
# Run inside a container booted with systemd as PID 1.
#   Usage: tests/systemd.sh <deb-dir>
# Client alone: xymon-client.service runs. Then the server: xymon.service runs
# and xymon-client.service is skipped by its ExecCondition, so the host does
# not report twice.
set -eu
DEBS=$(realpath "$1")
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

fail() { echo "FAIL: $*"; systemctl --no-pager status xymon xymon-client || true; exit 1; }
active() { for _ in $(seq 15); do systemctl is-active -q "$1" && return 0; sleep 2; done; return 1; }

apt-get install -y -qq "$DEBS"/xymon-client_*.deb >/dev/null
active xymon-client || fail "xymon-client.service not active on a client-only host"
echo "PASS: client-only host runs xymon-client.service"

apt-get install -y -qq "$DEBS"/xymon_*.deb >/dev/null
active xymon || fail "xymon.service not active"
systemctl restart xymon-client || true
sleep 2
systemctl is-active -q xymon-client && fail "xymon-client.service runs beside the server (double reporting)"
systemctl is-failed -q xymon-client && fail "xymon-client.service failed instead of being skipped"
echo "PASS: server host runs xymon.service, xymon-client.service skipped"
