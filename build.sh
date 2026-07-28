#!/usr/bin/env bash
#
# Kompajlira patch klasu i pakuje je u smartbox-mup-patch.jar.
#
# Kompajlira se naspram lokalnih "stub" klasa iz stubs/, a ne naspram zvanicnog
# smartbox JAR-a. Time build ne zavisi od PURS-ovog softvera i radi na bilo kom
# JDK 17+ (zvanicni JAR je class file v65, koji javac 17 ne ume da procita).
#
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD="$ROOT/build"
OUT_JAR="$BUILD/smartbox-mup-patch.jar"
PATCH_CLASS="com/itsinbox/pkcs11/sc/MUPSmartCard.class"

find_tool() {
    local tool=$1
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/$tool" ]; then
        echo "$JAVA_HOME/bin/$tool"; return 0
    fi
    if command -v "$tool" >/dev/null 2>&1; then
        command -v "$tool"; return 0
    fi
    # Poslednja sansa: bilo koji JDK ispod /usr/lib/jvm
    local found
    found=$(find /usr/lib/jvm -name "$tool" -type f 2>/dev/null | sort | tail -1)
    [ -n "$found" ] && { echo "$found"; return 0; }
    return 1
}

JAVAC=$(find_tool javac) || { echo "GRESKA: javac nije pronadjen. Instalirajte JDK 17 ili noviji." >&2; exit 1; }
JAR=$(find_tool jar)     || { echo "GRESKA: jar nije pronadjen. Instalirajte JDK 17 ili noviji." >&2; exit 1; }

echo "javac: $JAVAC ($("$JAVAC" -version 2>&1))"

rm -rf "$BUILD"
mkdir -p "$BUILD/classes"

"$JAVAC" --release 17 -nowarn \
    -d "$BUILD/classes" \
    $(find "$ROOT/stubs" "$ROOT/src" -name '*.java')

# U JAR ide ISKLJUCIVO nasa klasa. Stub klase ne smeju da se isporuce: stub
# SmartCard bi zasenio pravu klasu iz smartbox JAR-a i polomio celu aplikaciju.
"$JAR" --create --file "$OUT_JAR" -C "$BUILD/classes" "$PATCH_CLASS"

# Sigurnosna provera: tacno jedan .class unos, i to bas nas.
entries=$("$JAR" --list --file "$OUT_JAR" | grep -c '\.class$' || true)
if [ "$entries" -ne 1 ] || ! "$JAR" --list --file "$OUT_JAR" | grep -qx "$PATCH_CLASS"; then
    echo "GRESKA: JAR sadrzi neocekivane klase:" >&2
    "$JAR" --list --file "$OUT_JAR" >&2
    exit 1
fi

echo "OK: $OUT_JAR"
"$JAR" --list --file "$OUT_JAR" | sed 's/^/  /'
