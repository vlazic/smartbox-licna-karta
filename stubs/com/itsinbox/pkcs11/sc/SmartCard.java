package com.itsinbox.pkcs11.sc;

/**
 * SAMO ZA KOMPAJLIRANJE. Ne ulazi u isporuceni JAR.
 *
 * <p>Minimalni "stub" koji odgovara stvarnoj klasi iz smartbox JAR-a, tako da patch moze
 * da se kompajlira bez zvanicnog JAR-a (koji ne smemo redistribuirati). Potpis je preuzet
 * doslovno iz {@code javap -p} nad smartbox-2.0.0.jar:
 *
 * <pre>
 * public abstract class com.itsinbox.pkcs11.sc.SmartCard {
 *   public com.itsinbox.pkcs11.sc.SmartCard();
 *   protected abstract java.lang.String getCardName();
 *   public abstract java.lang.String getLibPath();
 *   ...
 * }
 * </pre>
 *
 * <p>Bitno: stvarna klasa ima tacno ove dve apstraktne metode, pa je nasa podklasa
 * kompletna i u vreme izvrsavanja, kada se ucita prava nadklasa.
 *
 * <p>UPOZORENJE: ako bi ovaj stub zavrsio u isporucenom JAR-u, zasenio bi pravu klasu
 * i potpuno bi polomio SmartBox. build.sh zato proverava sadrzaj JAR-a.
 */
public abstract class SmartCard {

    public SmartCard() {
    }

    protected abstract String getCardName();

    public abstract String getLibPath();
}
