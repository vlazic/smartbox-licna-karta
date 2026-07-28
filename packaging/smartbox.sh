#!/bin/bash
#
# SmartBox launcher sa podrskom za licnu kartu (MUP) na Linux-u.
#
# Instalira ga paket smartbox-licna-karta preko dpkg-divert, na mesto zvanicne
# /opt/smartbox/smartbox.sh. Original je sacuvan kao /opt/smartbox/smartbox.sh.distrib.
#
# Jedina sustinska razlika u odnosu na original: umesto "java -jar smartbox.jar",
# pokrece se "java -cp <patch.jar>:<smartbox.jar> com.itsinbox.smartbox.SmartBox",
# cime nasa MUPSmartCard klasa dolazi ranije na classpath i zasenjuje originalnu.
# SmartBox svoje pomocne procese pokrece preko java.class.path, pa i oni naslede patch.

PATCH_JAR="/usr/share/smartbox-licna-karta/smartbox-mup-patch.jar"
MAIN_CLASS="com.itsinbox.smartbox.SmartBox"

# Opciona podesavanja (npr. SMARTBOX_MUP_LIBRARY za drugu putanju do PKCS#11 modula).
if [ -r /etc/default/smartbox-licna-karta ]; then
    . /etc/default/smartbox-licna-karta
fi
[ -n "${SMARTBOX_MUP_LIBRARY:-}" ] && export SMARTBOX_MUP_LIBRARY

# Direktorijum za PID fajl (isto ponasanje kao zvanicna skripta).
if [ -z "$XDG_RUNTIME_DIR" ]; then
    XDG_RUNTIME_DIR="$HOME/.local/run"
    mkdir -p "$XDG_RUNTIME_DIR"
fi
PID_FILE="$XDG_RUNTIME_DIR/smartbox.pid"

# Java 21.
JAVA_BIN=$(update-alternatives --list java 2>/dev/null | grep 'java-21-openjdk' | head -1)
if [ -z "$JAVA_BIN" ]; then
    echo 'Greska: Java 21 nije instalirana niti registrovana kroz update-alternatives.' >&2
    exit 1
fi

# Zvanicni JAR, bez oslanjanja na tacnu verziju u imenu.
SMARTBOX_JAR=$(ls -1 /opt/smartbox/smartbox-*.jar 2>/dev/null | sort -V | tail -1)
if [ -z "$SMARTBOX_JAR" ]; then
    echo 'Greska: nije pronadjen /opt/smartbox/smartbox-*.jar. Da li je paket smartbox instaliran?' >&2
    exit 1
fi

# Vec pokrenut?
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "SmartBox je vec pokrenut."
    exit 0
fi

if [ -r "$PATCH_JAR" ]; then
    "$JAVA_BIN" -cp "$PATCH_JAR:$SMARTBOX_JAR" "$MAIN_CLASS" &
else
    # Patch nedostaje: pokreni original da aplikacija bar radi za ostala sert. tela.
    echo "Upozorenje: $PATCH_JAR ne postoji, pokrecem SmartBox bez podrske za licnu kartu." >&2
    "$JAVA_BIN" -jar "$SMARTBOX_JAR" &
fi

echo $! > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT
wait $!
