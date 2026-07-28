#!/usr/bin/env bash
#
# Poništava install.sh. Za .deb instalaciju koristite:
#   sudo apt remove smartbox-licna-karta
#
set -euo pipefail

LAUNCHER=/opt/smartbox/smartbox.sh
BACKUP=/opt/smartbox/smartbox.sh.distrib
SHARE=/usr/share/smartbox-licna-karta
MODULE=/usr/lib/libsrb-id-pkcs11.so

[ "$(id -u)" -eq 0 ] || { echo "GREŠKA: pokrenite kao root (sudo ./uninstall.sh)" >&2; exit 1; }

if [ -e "$BACKUP" ]; then
    mv -f "$BACKUP" "$LAUNCHER"
    echo "vraćen zvanični launcher: $LAUNCHER"
else
    echo "upozorenje: $BACKUP ne postoji, launcher nije vraćen" >&2
fi

rm -rf "$SHARE"
rm -f "$MODULE"
rm -f /etc/default/smartbox-licna-karta

echo "Deinstalirano."
