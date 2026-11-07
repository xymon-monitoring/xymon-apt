#!/bin/sh
# Install test, run as root in a fresh Debian/Ubuntu container.
#   Usage: tests/install.sh <deb-dir> fresh|upgrade
# fresh:   install our xymon + xymon-client on an empty system.
# upgrade: install the distro's official xymon first, then upgrade to ours --
#          the compatibility promise this repo makes.
# Either way: start the server (SysV script; no PID 1 here) and wait until
# its own client's data is analysed into cpu/disk/memory/procs columns.
set -eu
DEBS=$(realpath "$1") MODE=$2
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

if [ "$MODE" = upgrade ]; then
    apt-get install -y -qq xymon >/dev/null
    old=$(dpkg-query -W -f '${Version}' xymon)
    echo "official xymon $old installed"
fi
apt-get install -y -qq procps "$DEBS"/xymon_*.deb "$DEBS"/xymon-client_*.deb >/dev/null
new=$(dpkg-query -W -f '${Version}' xymon)
case "$new" in *~~xymon*) ;; *) echo "FAIL: xymon $new is not ours"; exit 1 ;; esac
# Must yield to the official backport and upload of the same Debian version.
deb=${new%%~~xymon*}
dpkg --compare-versions "$new" lt "$deb~bpo00+1" || { echo "FAIL: $new sorts above $deb~bpo"; exit 1; }
[ "$(dpkg-query -W -f '${Version}' xymon-client)" = "$new" ] || { echo "FAIL: client/server versions differ"; exit 1; }
echo "xymon $new installed"

/etc/init.d/xymon restart
host=$(awk '$1 ~ /^[0-9]/ && $2 != "" {print $2; exit}' /etc/xymon/hosts.cfg)
echo "waiting for $host to report"
for _ in $(seq 60); do
    cols=$(/usr/lib/xymon/server/bin/xymon 127.0.0.1 "xymondboard host=$host fields=testname" 2>/dev/null | sort | tr '\n' ' ')
    missing=""
    for c in cpu disk memory procs; do
        case " $cols " in *" $c "*) ;; *) missing="$missing $c" ;; esac
    done
    [ -z "$missing" ] && { echo "PASS ($MODE): $host reports: $cols"; exit 0; }
    sleep 5
done
echo "FAIL ($MODE): missing:$missing (have: $cols)"
tail -20 /var/log/xymon/*.log
exit 1
