package com.itsinbox.os;

/**
 * SAMO ZA KOMPAJLIRANJE. Ne ulazi u isporuceni JAR.
 *
 * <p>Redosled konstanti je isti kao u stvarnoj klasi (WINDOWS=0, MAC=1, LINUX=2, UNKNOWN=3).
 * Patch poredi reference preko {@code ==}, pa redosled ne utice na ispravnost, ali se
 * zadrzava radi vernosti originalu.
 */
public enum OsType {
    WINDOWS,
    MAC,
    LINUX,
    UNKNOWN
}
