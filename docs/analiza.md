# Analiza: zašto SmartBox na Linuxu ne vidi ličnu kartu

Ovaj dokument beleži ceo tok dijagnostike, sa dokazima iz bajtkoda. Namenjen je
svakome ko naiđe na isti problem i želi da proveri tvrdnje umesto da veruje na reč.

Analizirana verzija: `smartbox` **2.0.0-8**, iz `https://repo.purs.rs/ubuntu jammy/main`,
JAR sagrađen 22.11.2024.

---

## 1. Simptom

SmartBox se uredno pokreće, pregledač se poveže, ali lista sertifikacionih tela ostaje
prazna:

```
server started successfully
localhost/127.0.0.1:17165
received message from /127.0.0.1:56580: {"operation":"GET_INFO", ...}
{"operation":"GET_INFO","status":0,"payload":{}}
received message from /127.0.0.1:56580: {"operation":"GET_PROVIDERS"}
{"operation":"GET_PROVIDERS","status":0,"payload":{"providers":[]}}
```

Pritom je hardver potpuno ispravan:

```
$ opensc-tool -l
0    Yes             Gemalto PC Twin Reader (2057250D) 00 00

$ opensc-tool -a
3b:9e:96:80:31:fe:45:53:43:45:20:38:2e:30:2d:43:31:56:30:0d:0a:6f
```

Taj ATR je `SCE 8.0-C1V0`, srpska lična karta. Kartica odgovara, dakle problem je u
softveru.

## 2. Gde se lista sertifikacionih tela formira

`GetProvidersHandler.handle()` poziva `getVendorsFromProcess()`, koja **pokreće poseban
JVM proces** sa argumentima `ACTION GET_VENDORS` i parsira njegov standardni izlaz,
tražeći marker `######VENDOR_LIST######` iza kojeg sledi Base64 sa JSON listom.

To je vrlo korisno za dijagnostiku, jer se ceo korak može pozvati direktno, bez
pregledača:

```bash
java -jar /opt/smartbox/smartbox-2.0.0.jar ACTION GET_VENDORS
```

Na nezakrpljenoj instalaciji vraća `######VENDOR_LIST######W10=`, a `W10=` je Base64 za
`[]`.

Sam izbor vendora radi `SmartCardUtil.getInstalledMiddleware()`, koja filtrira
`CardVendor` vrednosti kroz `SmartCard.isMiddlewareInstalled()`.

## 3. Uzrok, u bajtkodu

```
$ javap -c -p -cp /opt/smartbox/smartbox-2.0.0.jar com.itsinbox.pkcs11.sc.MUPSmartCard

  public java.lang.String getLibPath();
       0: getstatic     #9    // MUPSmartCard$1.$SwitchMap$com$itsinbox$os$OsType:[I
       3: invokestatic  #15   // OsUtil.getOsType:()Lcom/itsinbox/os/OsType;
       6: invokevirtual #21   // OsType.ordinal:()I
       9: iaload
      10: lookupswitch  { 1: 28   default: 33 }
      28: ldc           #27   // String C:\Program Files\TrustEdgeID\netsetpkcs11_x64.dll
      30: goto          35
      33: ldc           #29   // String            <-- prazan string
      35: areturn
```

Enum `OsType` je `WINDOWS=0, MAC=1, LINUX=2, UNKNOWN=3`, a statički inicijalizator
pomoćne klase `MUPSmartCard$1` popunjava mapu **samo za WINDOWS**:

```
$ javap -c -p -cp /opt/smartbox/smartbox-2.0.0.jar 'com.itsinbox.pkcs11.sc.MUPSmartCard$1'
      12: getstatic     #13   // OsType.WINDOWS
      15: invokevirtual #17   // ordinal()
      18: iconst_1
      19: iastore              // $SwitchMap[WINDOWS.ordinal()] = 1
```

Na Linuxu je vrednost u mapi `0`, pa se izvršava `default` grana i metoda vraća prazan
string. Nakon toga:

```
$ javap -c -p -cp /opt/smartbox/smartbox-2.0.0.jar com.itsinbox.pkcs11.sc.SmartCard

  public boolean isMiddlewareInstalled();
       1: invokevirtual #78   // getLibPath()
       4: ldc           #104  // String            <-- prazan string
       6: invokestatic  #106  // Objects.equals(Object, Object)
       9: ifne          44    // ako je jednako -> skoči na "return false"
      ...
      44: iconst_0
      45: ireturn
```

Dakle na Linuxu `isMiddlewareInstalled()` za MUP **uvek** vraća `false`.

### Nije reč o propustu u konfiguraciji

Ista provera za druga sertifikaciona tela pokazuje da Linux putanje postoje, ali samo
za neke:

| Klasa | Windows | macOS | **Linux** |
|---|---|---|---|
| `PostaSmartCard` | `aetpkss1.dll` | `libaetpkss.dylib` | **`/usr/lib/libaetpkss.so`** |
| `EsmartSmartCard` | `IDPrimePKCS1164.dll` | `libIDPrimePKCS11.dylib` | **`/usr/lib/libeToken.so`** |
| `HalcomSmartCard` | `personal64.dll` | `libtokenapi.dylib` | **nema** |
| `MUPSmartCard` | `netsetpkcs11_x64.dll` | nema | **nema** |
| `PKSSmartCard` | `netsetpkcs11_x64.dll` | nema | **nema** |

Uz to, PURS repozitorijum sadrži tačno jedan paket (`smartbox`), dakle ne postoji ni
zvanični Linux middleware koji bi se instalirao:

```
$ apt-cache policy smartbox
  Installed: 2.0.0-8
  Candidate: 2.0.0-8
     500 https://repo.purs.rs/ubuntu jammy/main amd64 Packages
```

## 4. Da li kartica uopšte može da radi na Linuxu

Može, preko otvorenog modula [`ubavic/srb-id-pkcs11`](https://github.com/ubavic/srb-id-pkcs11):

```
$ pkcs11-tool --module /usr/lib/libsrb-id-pkcs11.so -L
Slot 0 (0x1): Gemalto PC Twin Reader (2057250D) 00 00
  token label        : NetSeT's CardEdge Token
  token manufacturer : NetSeT Global Solutions

$ pkcs11-tool --module /usr/lib/libsrb-id-pkcs11.so -O
Certificate Object; type = X.509 cert
  label:      ... Auth
Certificate Object; type = X.509 cert
  label:      ... Sign
```

Modul izvozi svih 68 PKCS#11 funkcija, uključujući `C_Login`, `C_SignInit` i `C_Sign`.
Sve što je SmartBox-u potrebno već postoji, samo mu niko nije rekao gde da traži.

Bitan detalj: **ID slota je `1`, a ne `0`.** SmartBox to ne pogađa napamet nego ID
dobija enumeracijom preko `org.xipki.pkcs11.wrapper`, pa ga pregledač vrati nazad i
završi kao `slot = 1` u generisanom `pkcs11.cfg`. Zbog toga nikakva dodatna izmena
nije potrebna.

## 5. Rešenje bez diranja zvaničnog JAR-a

Prva pomisao je ubaciti prepravljenu klasu u `smartbox-2.0.0.jar`. To radi, ali menja
tuđi paket i svaki `apt upgrade` tiho vraća staro stanje.

Bolje rešenje koristi činjenicu da JVM klase traži **redom po classpath-u**, i da
SmartBox svoje pomoćne procese pokreće prosleđujući im `java.class.path`. Dovoljno je,
dakle, staviti mali JAR ispred zvaničnog.

Dokaz, nad **netaknutim** originalnim JAR-om:

```bash
# sa patch-om ispred
$ java -cp smartbox-mup-patch.jar:smartbox-2.0.0.jar.orig \
       com.itsinbox.smartbox.SmartBox ACTION GET_VENDORS
######VENDOR_LIST######WyJNVVAiXQ==        # ["MUP"]

# kontrola, samo originalni JAR
$ java -cp smartbox-2.0.0.jar.orig \
       com.itsinbox.smartbox.SmartBox ACTION GET_VENDORS
######VENDOR_LIST######W10=                # []
```

Zvanična `smartbox.sh` koristi `java -jar`, što ignoriše `-cp`. Zato paket preko
`dpkg-divert` zamenjuje tu skriptu svojom, koja pokreće
`java -cp <patch>:<smartbox> com.itsinbox.smartbox.SmartBox`.

Pošto i `/usr/bin/smartbox` i `/usr/share/applications/smartbox.desktop`
(`Exec=/opt/smartbox/smartbox.sh`) pokazuju na taj isti fajl, jedna zamena pokriva i
terminal i ikonicu, pa nikada ne postoje dve instance koje se otimaju o port `17165`.

### Zašto kompajliranje ne zahteva PURS-ov JAR

`SmartCard` ima javni konstruktor bez argumenata i **tačno dve** apstraktne metode:

```
$ javap -p -cp smartbox-2.0.0.jar com.itsinbox.pkcs11.sc.SmartCard
public abstract class com.itsinbox.pkcs11.sc.SmartCard {
  public com.itsinbox.pkcs11.sc.SmartCard();
  protected abstract java.lang.String getCardName();
  public abstract java.lang.String getLibPath();
  ...
}
```

Zato je dovoljno kompajlirati naspram minimalnih „stub“ klasa iz `stubs/`. Rezultujući
bajtkod referiše ista imena, a u vreme izvršavanja se učitavaju prave klase. Kao
bonus, build radi na **bilo kom JDK 17+**, dok bi za kompajliranje naspram pravog
JAR-a bio potreban JDK 21 (JAR je class file verzije 65, koju `javac` 17 ne čita).

> Zbog toga `build.sh` proverava da u isporučeni JAR uđe **isključivo**
> `MUPSmartCard.class`. Kada bi se tu našao i stub `SmartCard`, on bi zasenio pravu
> klasu i polomio celu aplikaciju.

## 6. Usputna zapažanja

Stvari uočene tokom analize, koje nisu uzrok problema ali mogu da zbune.

### `-Djava.security.debug=sunpkcs11` je ostao uključen

`OsUtil.runInProcessWithResult()` pokreće pomoćni JVM ovako:

```
-Djava.security.debug=sunpkcs11
-Dfile.encoding=UTF-8
-Dsun.stdout.encoding=UTF-8
-Dsun.stderr.encoding=UTF-8
-cp <java.class.path> com.itsinbox.smartbox.SmartBox ACTION ...
```

Dakle, dijagnostički ispis se šalje na **isti** standardni izlaz koji roditeljski
proces potom parsira tražeći svoj marker. To je krhko po konstrukciji i najverovatniji
uzrok povremeno izobličenih natpisa u interfejsu, poput imena čitača kartice.

Isti taj poziv objašnjava i zašto se putanja do modula podešava **promenljivom
okruženja**, a ne `-D` svojstvom: lista argumenata je ručno sastavljena i ne prosleđuje
sistemska svojstva, dok `ProcessBuilder` okruženje nasleđuje.

### `srb-id-pkcs11` popunjava `slotDescription` nulama

PKCS#11 propisuje da se `CK_SLOT_INFO.slotDescription` dopuni **razmacima**. Modul
umesto toga koristi nule:

```
0000  47 65 6d 61 6c 74 6f 20 50 43 20 54 77 69 6e 20  |Gemalto PC Twin |
0010  52 65 61 64 65 72 20 28 32 30 35 37 32 35 30 44  |Reader (2057250D|
0020  29 20 30 30 20 30 30 00 00 00 00 00 00 00 00 00  |) 00 00.........|
0030  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
```

Odstupanje od specifikacije, ali bezopasno: reč je o čistim nulama, ne o
neinicijalizovanoj memoriji, a `org.xipki.pkcs11.wrapper.SlotInfo` nad tim radi
`new String(char[]).trim()`, što nule uklanja. Kozmetički problem sa imenom čitača
verovatno dolazi od stavke iznad, a ne odavde. U svakom slučaju, izbor čitača ide
preko ID-a slota, pa prikaz imena ni na šta ne utiče.

### Natpisi `???enter_pin???` na stranici za prijavu

Greška u prevodima portala ePorezi, nezavisna od SmartBox-a. SmartBox isporučuje samo
naziv sertifikacionog tela i ime čitača, i oba se prikazuju ispravno. Očekivani
natpisi, prema [zvaničnom uputstvu](https://eporezi.purs.gov.rs/upload/eporezi/Korisnicko_uputstvo-aplikacija_SmartBox-13.12.2024.pdf):

| Ključ | Očekivani natpis |
|---|---|
| `login_to_system` | Пријава на систем |
| `chosen_provider` | Изабрано сертификационо тело: |
| `chosen_terminal` | Изабрани читач: |
| `another_option` | За другачији избор потребно је да инсталирате одговарајући Middleware |
| `enter_pin` | Унесите Ваш идентификациони ПИН |
| `button_back` / `button_login` | Назад / Пријави се |

### Verzija PKCS#11 modula 0.5.0 ne radi na Ubuntu 22.04

Novije nije bolje. Upstream `v0.5.0` traži `GLIBC_2.36`:

```
$ ldd --version
ldd (Ubuntu GLIBC 2.35-0ubuntu3.14) 2.35

$ pkcs11-tool --module ./libsrb-id-pkcs11.so.0.5.0 -L
sc_dlopen failed: version `GLIBC_2.36' not found
```

Verzija `0.4.3` traži najviše `GLIBC_2.34` i radi. Pošto PURS repozitorijum cilja
jammy, paket namerno zakucava `0.4.3` sa proverom SHA256.

## 7. Šta bi bilo pravo rešenje

Da PURS, odnosno proizvođač aplikacije, doda Linux putanju u `MUPSmartCard` (i u
`HalcomSmartCard`), po ugledu na `PostaSmartCard` i `EsmartSmartCard`. Do tada,
ovaj paket popunjava tu prazninu.

## 8. Korišćene komande

Sve iz ove analize je ponovljivo sa alatima iz standardnih repozitorijuma:

```bash
# raspakivanje i čitanje bajtkoda
unzip -l /opt/smartbox/smartbox-2.0.0.jar
javap -c -p -cp /opt/smartbox/smartbox-2.0.0.jar com.itsinbox.pkcs11.sc.MUPSmartCard

# kartica i čitač
pcsc_scan -c
opensc-tool -l -a
pkcs11-tool --module /usr/lib/libsrb-id-pkcs11.so -L -O

# ponašanje same aplikacije
java -jar /opt/smartbox/smartbox-2.0.0.jar ACTION GET_VENDORS
```
