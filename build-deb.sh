#!/usr/bin/env bash
#
# Sastavlja .deb paket smartbox-licna-karta.
#
# PKCS#11 modul se preuzima sa zvaničnog upstream releasea i proverava se
# SHA256, pa se pakuje u .deb. Tako instalacija na korisnikovoj mašini nikada
# ne dira mrežu.
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD="$ROOT/build"
STAGE="$BUILD/deb"
VERSION=$(cat "$ROOT/VERSION")
ARCH=amd64

# Verzija 0.4.3 je namerno zakucana. Novija 0.5.0 zahteva GLIBC_2.36 i NE RADI
# na Ubuntu 22.04 (glibc 2.35), a upravo je jammy ono što PURS repozitorijum
# cilja. 0.4.3 traži najviše GLIBC_2.34.
PKCS11_VERSION=0.4.3
PKCS11_URL="https://github.com/ubavic/srb-id-pkcs11/releases/download/v${PKCS11_VERSION}/libsrb-id-pkcs11.so.${PKCS11_VERSION}"
PKCS11_SHA256=bbbd1966ce01b53f4e25c1badc2d0ea6c007b76f2e1320b8eab1e4f0e2bb9702

command -v dpkg-deb >/dev/null 2>&1 || { echo "GREŠKA: dpkg-deb nije pronađen." >&2; exit 1; }

echo "==> Kompajliram patch"
"$ROOT/build.sh"

echo "==> Preuzimam srb-id-pkcs11 v${PKCS11_VERSION}"
CACHE="$BUILD/libsrb-id-pkcs11.so"
curl -fsSL -o "$CACHE" "$PKCS11_URL"

actual=$(sha256sum "$CACHE" | cut -d' ' -f1)
if [ "$actual" != "$PKCS11_SHA256" ]; then
    echo "GREŠKA: SHA256 se ne poklapa." >&2
    echo "  očekivano: $PKCS11_SHA256" >&2
    echo "  dobijeno:  $actual" >&2
    exit 1
fi
echo "    SHA256 ispravan"

echo "==> Sastavljam stablo paketa"
rm -rf "$STAGE"
install -d -m 0755 \
    "$STAGE/DEBIAN" \
    "$STAGE/opt/smartbox" \
    "$STAGE/usr/lib" \
    "$STAGE/usr/share/smartbox-licna-karta" \
    "$STAGE/usr/share/doc/smartbox-licna-karta" \
    "$STAGE/etc/default"

sed "s/@VERSION@/$VERSION/" "$ROOT/packaging/DEBIAN/control" > "$STAGE/DEBIAN/control"
install -m 0644 "$ROOT/packaging/DEBIAN/conffiles" "$STAGE/DEBIAN/conffiles"
for script in preinst postinst postrm; do
    install -m 0755 "$ROOT/packaging/DEBIAN/$script" "$STAGE/DEBIAN/$script"
done

install -m 0755 "$ROOT/packaging/smartbox.sh"                  "$STAGE/opt/smartbox/smartbox.sh"
install -m 0644 "$CACHE"                                       "$STAGE/usr/lib/libsrb-id-pkcs11.so"
install -m 0644 "$BUILD/smartbox-mup-patch.jar"                "$STAGE/usr/share/smartbox-licna-karta/smartbox-mup-patch.jar"
install -m 0644 "$ROOT/packaging/smartbox-licna-karta.default" "$STAGE/etc/default/smartbox-licna-karta"
install -m 0644 "$ROOT/README.md"                              "$STAGE/usr/share/doc/smartbox-licna-karta/README.md"

cat > "$STAGE/usr/share/doc/smartbox-licna-karta/copyright" <<EOF
Ime: smartbox-licna-karta
Izvor: https://github.com/vlazic/smartbox-licna-karta

Fajlovi: *
Autorsko pravo: Vladimir Lazić <contact@vlazic.com>
Licenca: MIT

Fajlovi: /usr/lib/libsrb-id-pkcs11.so
Autorsko pravo: Nikola Ubavić
Licenca: Unlicense (javno vlasništvo)
Izvor: https://github.com/ubavic/srb-id-pkcs11 (v${PKCS11_VERSION})

Ovaj paket ne sadrži niti redistribuira softver Poreske uprave Republike Srbije.
EOF
chmod 0644 "$STAGE/usr/share/doc/smartbox-licna-karta/copyright"

DEB="$BUILD/smartbox-licna-karta_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB" >/dev/null

echo "==> Gotovo: $DEB"
dpkg-deb --info "$DEB" | sed 's/^/  /'
echo "  --- sadržaj ---"
dpkg-deb --contents "$DEB" | sed 's/^/  /'
