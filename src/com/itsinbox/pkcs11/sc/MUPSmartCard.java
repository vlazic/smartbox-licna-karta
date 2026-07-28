package com.itsinbox.pkcs11.sc;

import com.itsinbox.os.OsType;
import com.itsinbox.os.OsUtil;

import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Zamena za originalnu {@code MUPSmartCard} klasu iz SmartBox aplikacije.
 *
 * <p>Originalna klasa ima ugradjenu iskljucivo Windows putanju do middleware biblioteke,
 * pa {@code getLibPath()} na Linux-u vraca prazan string. Zbog toga
 * {@code SmartCard.isMiddlewareInstalled()} uvek vraca {@code false}, MUP se izbacuje iz
 * liste sertifikacionih tela, a {@code GET_PROVIDERS} vraca praznu listu.
 *
 * <p>Ova verzija na Linux-u i macOS-u vraca putanju do modula
 * <a href="https://github.com/ubavic/srb-id-pkcs11">srb-id-pkcs11</a>.
 *
 * <p>Klasa se ne ubacuje u zvanicni JAR. Ucitava se tako sto se nalazi ranije na
 * classpath-u od zvanicnog JAR-a, pa je JVM pronalazi prvu.
 */
public class MUPSmartCard extends SmartCard {

    /** Putanje koje se redom proveravaju ako {@code SMARTBOX_MUP_LIBRARY} nije postavljen. */
    private static final String[] CANDIDATES = {
        "/usr/lib/libsrb-id-pkcs11.so",
        "/usr/local/lib/libsrb-id-pkcs11.so",
        "/usr/lib/x86_64-linux-gnu/libsrb-id-pkcs11.so",
        "/usr/lib64/libsrb-id-pkcs11.so",
        System.getProperty("user.home", "") + "/lib/libsrb-id-pkcs11.so",
        "/usr/local/lib/libsrb-id-pkcs11.dylib",
    };

    private static final String DEFAULT_PATH = "/usr/lib/libsrb-id-pkcs11.so";

    private static final String WINDOWS_PATH =
        "C:\\Program Files\\TrustEdgeID\\netsetpkcs11_x64.dll";

    @Override
    protected String getCardName() {
        // Mora ostati tacno "MUP": koristi se kao "name = MUP" u generisanom pkcs11.cfg
        // i kao ime provajdera "SunPKCS11-MUP".
        return "MUP";
    }

    @Override
    public String getLibPath() {
        if (OsUtil.getOsType() == OsType.WINDOWS) {
            return WINDOWS_PATH;
        }

        // Promenljiva okruzenja, a ne sistemsko svojstvo: SmartBox pokrece pomocne JVM
        // procese sa rucno sastavljenom listom argumenata i ne prosledjuje -D svojstva,
        // ali ProcessBuilder nasledjuje okruzenje roditelja.
        String configured = System.getenv("SMARTBOX_MUP_LIBRARY");
        if (configured != null && !configured.isBlank() && exists(configured)) {
            return configured;
        }

        for (String candidate : CANDIDATES) {
            if (exists(candidate)) {
                return candidate;
            }
        }

        // Nepostojeca putanja je bezbedna: isMiddlewareInstalled() u nadklasi radi
        // Files.exists() i korektno prijavi da middleware nije instaliran.
        return DEFAULT_PATH;
    }

    private static boolean exists(String path) {
        try {
            return Files.exists(Path.of(path));
        } catch (RuntimeException e) {
            return false;
        }
    }
}
