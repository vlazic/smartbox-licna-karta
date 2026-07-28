# smartbox-licna-karta

Podrška za **ličnu kartu** u zvaničnoj **SmartBox** aplikaciji Poreske uprave, na Linuxu.

Bez ovoga, prijava na [ePorezi](https://eporezi.purs.gov.rs) ličnom kartom na Linuxu
jednostavno nije moguća, bez obzira na to koliko ispravno je sve ostalo podešeno.

> Nezvanično rešenje. Nije povezano sa Poreskom upravom Republike Srbije niti sa
> proizvođačem SmartBox aplikacije.

---

## Problem

Instalirate zvaničan `smartbox` paket iz PURS repozitorijuma, ubacite ličnu kartu,
otvorite ePorezi, prihvatite konekciju u pregledaču. Sve deluje ispravno, a lista
sertifikacionih tela je **prazna**.

U logu SmartBox aplikacije to izgleda ovako:

```
received message from /127.0.0.1:56580: {"operation":"GET_PROVIDERS"}
{"operation":"GET_PROVIDERS","status":0,"payload":{"providers":[]}}
```

Čitač radi, kartica se očitava, PIN je ispravan. Ništa od toga nije problem.

## Uzrok

U SmartBox aplikaciji, klasa `com.itsinbox.pkcs11.sc.MUPSmartCard` ima upisanu
**isključivo Windows putanju** do middleware biblioteke:

```
C:\Program Files\TrustEdgeID\netsetpkcs11_x64.dll
```

Za Linux i macOS ne postoji nijedna putanja, pa `getLibPath()` vraća **prazan string**.
Zatim `SmartCard.isMiddlewareInstalled()` odmah odustaje:

```java
if (Objects.equals(getLibPath(), "")) return false;   // na Linuxu uvek
```

MUP zbog toga ispada iz liste sertifikacionih tela pre nego što se kartica uopšte
dodirne. Za poređenje, `PostaSmartCard` i `EsmartSmartCard` imaju uredno navedene
Linux putanje (`/usr/lib/libaetpkss.so`, odnosno `/usr/lib/libeToken.so`).
**MUP i Halcom ih nemaju.**

Dakle, nije reč o pogrešnom podešavanju na vašem računaru. Linux verzija aplikacije
prosto ne može da vidi ličnu kartu. Detaljna analiza sa bajtkodom je u
[`docs/analiza.md`](docs/analiza.md).

## Rešenje

Java klase se traže redom po classpath-u, a SmartBox svoje pomoćne procese pokreće
prosleđujući `java.class.path`. Dovoljno je, dakle, postaviti **jednu zamensku klasu
ispred** zvaničnog JAR-a:

```
java -cp smartbox-mup-patch.jar:/opt/smartbox/smartbox-2.0.0.jar com.itsinbox.smartbox.SmartBox
```

Zamenska `MUPSmartCard` vraća putanju do otvorenog PKCS#11 modula
[`ubavic/srb-id-pkcs11`](https://github.com/ubavic/srb-id-pkcs11), koji podržava
i čitanje i potpisivanje ličnom kartom.

Zbog toga ovaj paket:

- **ne menja** zvanični `smartbox-2.0.0.jar`,
- **ne redistribuira** softver Poreske uprave,
- **preživljava** `apt upgrade` paketa `smartbox`, jer koristi `dpkg-divert`,
- uredno se **deinstalira** i vraća sistem u prvobitno stanje.

## Zahtevi

- Ubuntu 22.04 ili noviji (potreban `glibc >= 2.34`), odnosno ekvivalent
- Instaliran zvanični `smartbox` paket iz PURS repozitorijuma
- Čitač pametnih kartica i `pcscd`
- Lična karta sa **aktiviranim kvalifikovanim sertifikatom** (aktivira se u MUP-u)

## Instalacija

Preuzmite `.deb` sa [Releases](https://github.com/vlazic/smartbox-licna-karta/releases)
strane i instalirajte:

```bash
sudo apt install ./smartbox-licna-karta_1.0.0_amd64.deb
```

Zatim pokrenite `smartbox` i prijavite se na ePorezi.

<details>
<summary>Sastavljanje iz izvornog koda</summary>

```bash
git clone https://github.com/vlazic/smartbox-licna-karta
cd smartbox-licna-karta
./build-deb.sh                                  # potreban JDK 17+ i dpkg-deb
sudo apt install ./build/smartbox-licna-karta_1.0.0_amd64.deb
```

Patch se kompajlira naspram malih lokalnih „stub“ klasa u `stubs/`, a ne naspram
zvaničnog JAR-a, pa build ne zavisi ni od jednog PURS fajla.

</details>

<details>
<summary>Sistemi bez dpkg (Arch, Fedora...)</summary>

```bash
sudo ./install.sh      # deinstalacija: sudo ./uninstall.sh
```

Pri toj varijanti nema `dpkg-divert`, pa nadogradnja zvaničnog paketa prepisuje
launcher. Posle svake nadogradnje ponovo pokrenite `install.sh`.

</details>

## Provera da li radi

Bez otvaranja pregledača, direktno se može proveriti da li SmartBox sada vidi MUP:

```bash
JAVA=$(update-alternatives --list java | grep java-21-openjdk | head -1)
JAR=$(printf '%s\n' /opt/smartbox/smartbox-*.jar | sort -V | tail -1)
"$JAVA" -cp "/usr/share/smartbox-licna-karta/smartbox-mup-patch.jar:$JAR" \
        com.itsinbox.smartbox.SmartBox ACTION GET_VENDORS
```

Očekivani izlaz:

```
######VENDOR_LIST######WyJNVVAiXQ==
```

`WyJNVVAiXQ==` je Base64 za `["MUP"]`. Ako dobijete `W10=`, to je `[]` i patch se ne
primenjuje.

Dve zamke, zbog kojih komanda namerno izgleda ovako:

> **Mora Java 21**, jer je smartbox JAR class file verzije 65. Ako vam je podrazumevani `java`
> stariji (na primer 17, kroz `asdf` ili `update-alternatives`), dobićete
> `UnsupportedClassVersionError ... only recognizes class file versions up to 61.0`, iako je
> paket sasvim ispravno instaliran.

> **`printf` i glob umesto `ls`.** Uz `alias ls='ls --color=auto'` `ls` ume da ubaci ANSI
> kodove i unutar `$(...)`, pa putanja postane neupotrebljiva i dobijete
> `ClassNotFoundException`. Iz istog razloga i launcher u paketu koristi glob.

Da li kartica uopšte radi, nezavisno od SmartBox-a:

```bash
pkcs11-tool --module /usr/lib/libsrb-id-pkcs11.so -L   # očekuje se "NetSeT's CardEdge Token"
pkcs11-tool --module /usr/lib/libsrb-id-pkcs11.so -O   # očekuju se sertifikati "Auth" i "Sign"
```

## Podešavanje

Ako želite drugu verziju PKCS#11 modula, upišite putanju u
`/etc/default/smartbox-licna-karta`:

```sh
SMARTBOX_MUP_LIBRARY=/usr/local/lib/libsrb-id-pkcs11.so
```

Namerno je promenljiva okruženja, a ne `-D` svojstvo: SmartBox pokreće pomoćne JVM
procese sa ručno sastavljenom listom argumenata i ne prosleđuje sistemska svojstva,
ali `ProcessBuilder` nasleđuje okruženje.

## Deinstalacija

```bash
sudo apt remove smartbox-licna-karta
```

Zvanični launcher se vraća na mesto, preusmerenje se uklanja, SmartBox nastavlja da
radi kao pre (bez podrške za ličnu kartu).

## Ako ste ranije ručno zakrpili JAR

Ako ste pre ovog paketa sami ubacivali klasu u `smartbox-2.0.0.jar`, vratite original
i skinite zadršku sa paketa, da se dve izmene ne bi preklapale:

```bash
sudo cp /opt/smartbox/smartbox-2.0.0.jar.orig /opt/smartbox/smartbox-2.0.0.jar
sudo apt-mark unhold smartbox
```

## Poznata ograničenja

- **Verzija PKCS#11 modula je namerno 0.4.3.** Novija 0.5.0 zahteva `GLIBC_2.36` i
  **ne učitava se** na Ubuntu 22.04 (`glibc 2.35`), a upravo je jammy ono što PURS
  repozitorijum cilja. Greška izgleda ovako:
  `version 'GLIBC_2.36' not found`.
- **Samo `amd64`.** Upstream ne objavljuje `arm64` build za Linux.
- **Natpisi `???enter_pin???` i slično** na stranici za prijavu su greška u
  prevodima samog portala ePorezi. Nema veze sa SmartBox-om ni sa ovim paketom, i
  ne sprečava prijavu. Očekivani natpisi su u
  [zvaničnom uputstvu](https://eporezi.purs.gov.rs/upload/eporezi/Korisnicko_uputstvo-aplikacija_SmartBox-13.12.2024.pdf).
- **Ime čitača ume da se prikaže sa smećem na kraju.** Kozmetički problem, izbor
  čitača ide preko ID-a slota. Više o tome u [`docs/analiza.md`](docs/analiza.md).

## Zahvalnice

- [Nikola Ubavić](https://github.com/ubavic) za
  [`srb-id-pkcs11`](https://github.com/ubavic/srb-id-pkcs11) i
  [`bas-celik`](https://github.com/ubavic/bas-celik), bez kojih ništa od ovoga ne bi
  bilo moguće.

## Licenca

Kod u ovom repozitorijumu: [MIT](LICENSE).

Isporučeni `libsrb-id-pkcs11.so` je delo Nikole Ubavića, pod
[Unlicense](https://unlicense.org) licencom (javno vlasništvo).

Ovaj projekat ne sadrži i ne redistribuira softver Poreske uprave Republike Srbije.
