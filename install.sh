#!/usr/bin/env bash
#
# Ručna instalacija, za sisteme bez dpkg (Arch, Fedora, openSUSE...).
# Na Debianu i Ubuntuu koristite .deb paket, jer se on uredno deinstalira.
#
# Radi isto što i paket: postavlja patch JAR ispred zvaničnog na classpath,
# preko zamenjenog launchera. Zvanični JAR se ne dira.
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

PKCS11_VERSION=0.4.3
PKCS11_URL="https://github.com/ubavic/srb-id-pkcs11/releases/download/v${PKCS11_VERSION}/libsrb-id-pkcs11.so.${PKCS11_VERSION}"
PKCS11_SHA256=bbbd1966ce01b53f4e25c1badc2d0ea6c007b76f2e1320b8eab1e4f0e2bb9702

LAUNCHER=/opt/smartbox/smartbox.sh
BACKUP=/opt/smartbox/smartbox.sh.distrib
SHARE=/usr/share/smartbox-licna-karta
MODULE=/usr/lib/libsrb-id-pkcs11.so

[ "$(id -u)" -eq 0 ] || { echo "GREŠKA: pokrenite kao root (sudo ./install.sh)" >&2; exit 1; }

if ! ls /opt/smartbox/smartbox-*.jar >/dev/null 2>&1; then
    echo "GREŠKA: SmartBox nije pronađen u /opt/smartbox." >&2
    echo "Prvo instalirajte zvaničnu aplikaciju sa https://eporezi.purs.gov.rs" >&2
    exit 1
fi

echo "==> Kompajliram patch"
sudo -u "${SUDO_USER:-root}" "$ROOT/build.sh"

echo "==> Preuzimam srb-id-pkcs11 v${PKCS11_VERSION}"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "$PKCS11_URL"
actual=$(sha256sum "$tmp" | cut -d' ' -f1)
if [ "$actual" != "$PKCS11_SHA256" ]; then
    echo "GREŠKA: SHA256 se ne poklapa (očekivano $PKCS11_SHA256, dobijeno $actual)" >&2
    exit 1
fi

echo "==> Instaliram"
install -d -m 0755 "$SHARE"
install -m 0644 "$ROOT/build/smartbox-mup-patch.jar" "$SHARE/smartbox-mup-patch.jar"
install -m 0644 "$tmp" "$MODULE"

if [ ! -e "$BACKUP" ]; then
    cp -a "$LAUNCHER" "$BACKUP"
    echo "    original launcher sačuvan kao $BACKUP"
fi
install -m 0755 "$ROOT/packaging/smartbox.sh" "$LAUNCHER"

if [ ! -e /etc/default/smartbox-licna-karta ]; then
    install -d -m 0755 /etc/default
    install -m 0644 "$ROOT/packaging/smartbox-licna-karta.default" /etc/default/smartbox-licna-karta
fi

systemctl enable --now pcscd.socket >/dev/null 2>&1 || true

echo ""
echo "Gotovo. Pokrenite 'smartbox' i prijavite se na https://eporezi.purs.gov.rs"
echo "Deinstalacija: sudo ./uninstall.sh"
echo ""
echo "NAPOMENA: nadogradnja zvaničnog smartbox paketa će prepisati $LAUNCHER."
echo "Posle svake nadogradnje ponovo pokrenite ovu skriptu."
