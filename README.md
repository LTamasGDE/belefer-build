# Belefér

Magyar nyelvű, személyes pénzügykövető Androidra és iOS-re, Flutterrel.
Kiadás: **26.11.2**, alkalmazásverzió: `0.3.0+3`.

## Funkciók

- **Áttekintés:** a kiválasztott hónap bevétele, kiadása és a kettő különbsége
  („Maradt”). Előző és következő hónapra lehet lapozni. Az interaktív
  gyűrűdiagram kategóriánként mutatja a kiadásokat (`100% | 124 500 Ft`).
  Gyorsgombok: **Új kiadás**, **Új bevétel**.
- **Gyorsrögzítés (26.11.1):** egy mondatból könyvel, internet nélkül, a
  telefonon: „Lidl 4500 tegnap”, „megjött a fizetés 420e”, „kávé 890”.
  Tűri az elírásokat („lild”, „kvae”), a toldalékokat („Tescóban”, „850-ért”),
  a felcserélt szórendet, a számneveket („kétezer-ötszáz”, „másfél millió”),
  a `12e`/`2,5k` alakot és a magyar dátumokat („pénteken”, „nov. 3.”,
  „3 napja”). A korábbi tételeidből tanulja a kategóriákat. Halványan mindig
  mutatja, mire kell még válasz (*Mennyi? · Mire, hol? · Mikor? · Kiadás vagy
  bevétel?*); ha minden megvan, egy koppintással könyvel, visszavonhatóan.
  Ismétlődő tételt is felvesz („Netflix havi 4990”), lemond („lemondtam a
  Spotifyt”) vagy módosít („mostantól 190 ezer a lakbér”).
- **Saját nyelvi modell (26.11.2):** a gyorsrögzítés, a blokkok és a banki
  értesítések értelmezése mögött a Belefér saját, a telefonon futó modellje
  áll (kb. 1,4 MB, internet, kulcs és előfizetés nélkül). Magyar pénzügyi
  mondatokra, blokkokra és (magyar/angol) banki értesítésekre tanított,
  betűcsoport-alapú modell: kategóriát, szándékot (rögzítés, új ismétlődő
  tétel, lemondás, módosítás), értesítés-állapotot és megnevezést ad, a
  szótárban nem szereplő szavakra is („a hentesnél 6700”, „nem kell már a
  Disney”). A korábbi tételeidből is tanul. A Beállításokban kipróbálható.
- **Automatikus rögzítés (26.11.2):** Androidon a Revolut értesítéseiből
  (kizárólag a `com.revolut.revolut` alkalmazáséból – minden más app
  értesítését a kód azonnal eldobja), iPhone-on az Apple Pay-fizetésekből a
  Parancsok app automatizmusával. Kiszűri a sikertelen fizetéseket, a saját
  számlák közötti mozgást és a nem pénzmozgással járó értesítéseket, a
  devizás összeget a napi EKB-árfolyamon forintra váltja, és a felismerő
  szavak alapján a jó számlára teszi. Napló a Beállításokban.
- **Számlák (26.11.2):** pl. Saját, Megtakarítás, Közös; alapértelmezett
  számla, felismerő szavak (kártyanév, szó vagy kártyaszám vége), szűrés
  számlánként az Áttekintésen és a Tételek között.
- **Blokk és e-számla (26.11.1):** fotó a kamerával, kép vagy képernyőkép a
  galériából, illetve PDF-számla. A szövegfelismerés a telefonon fut (ML Kit);
  a felismert szöveget és az értelmezést (kereskedő, végösszeg, dátum,
  kategória) átnézed, javítod, majd egy koppintással könyveled.
- **Ismétlődő tételek (26.11.1):** hetente, kéthetente, havonta,
  negyedévente, félévente vagy évente; kezdő és opcionális záró dátummal.
  Esedékességkor maguktól rögzülnek, vagy kérésre jóváhagyásra várnak
  (az összeg ekkor módosítható). Összegváltozás a következő esedékességtől,
  lemondás és újraindítás.
- **Emlékeztetők (26.11.1):** helyi értesítés az esedékesség előtt
  (aznap, 1–7 nappal), választható időpontban, akár saját szöveggel
  (`{név}`, `{összeg}`, `{dátum}`, `{mikor}` helyőrzőkkel, előnézettel).
  Főkapcsoló és próbaértesítés a Beállításokban.
- **Előrejelzés (26.11.1):** a hónap végére várható egyenleg a még esedékes
  ismétlődő tételekből és az eddigi napi átlagos költésből (az első napokban
  az előző hónapok átlagából).
- **Keresés (26.11.1):** minden hónap tételei között, megnevezésre,
  megjegyzésre, kategóriára, összegre vagy dátumra; ékezet nélkül és elírva is.
- **Saját kategóriák (26.11.1):** névvel, színnel és ikonnal, akár közvetlenül
  az űrlapról. Törléskor a tételeik az „Egyéb” kategóriába kerülnek.
- **Kezdőképernyő-widget (26.11.1):** a hónap egyenlege, bevétele, kiadása és
  a következő esedékes tétel; gyorsrögzítés és blokkfotózás egy koppintással
  (Android és iOS).
- **Bemutató (26.11.1):** első indításkor körbevezet; kihagyható, és a
  Beállításokban újraindítható. Ha még nincs adatod, bemutató adatokkal
  mutatja be (ezek nem mentődnek); ha van, a sajátjaiddal – semmi sem törlődik.
- **Tételek:** felvétel, szerkesztés, törlés; hónap és típus szerinti szűrés.
- **Sablonok:** kiadási és bevételi sablonok (pl. *Lakbér*, *Fizetés*);
  használatkor a kitöltött űrlap nyílik meg a mai dátummal.
- **Beállítások:** világos/sötét mód, saját modell, automatikus rögzítés,
  számlák, kategóriák, emlékeztetők, bemutató, verzió, **Összes adat
  törlése** megerősítéssel.

Bejelentkezés nincs, az alkalmazás egyetlen felhasználónak készült. Webes
változat szándékosan nincs.

## Adattárolás

Minden adat helyben, a készüléken marad. Az adatbázis egy Sembast-fájl
(`belefer.db`) az alkalmazás saját tárhelyén: Androidon az app adatkönyvtárában,
iOS-en az Application Support mappában. Szerver és szinkronizálás nincs. Az
alkalmazás törlésekor az adatok is törlődnek.

- Az összegek pozitív egész forintként tárolódnak; a kiadás/bevétel típus
  dönti el az irányt.
- A dátum naptári napként (`ÉÉÉÉ-HH-NN`) tárolódik, így időzónától
  függetlenül mindig a saját hónapjában marad.
- Tárolók: tételek, sablonok, ismétlődő tételek, saját kategóriák és
  beállítások, számlák. A gyorsrögzítés, a saját modell, a szövegfelismerés
  és az automatikus rögzítés sem küld adatot sehova. Egyetlen hálózati hívás
  a devizás értesítéseknél az EKB-árfolyam lekérése (Frankfurter), amely
  csak a pénznemet tartalmazza.

## APK letöltése (Android)

A telepíthető APK a build-repó kiadásai között van, bejelentkezés nélkül
letölthető: <https://github.com/LTamasGDE/belefer-build/releases/tag/26.11.2>.
Telefonon a `belefer-26.11.2.apk` fájlt érdemes letölteni (release mód,
debug-kulccsal aláírva). Nyisd meg a letöltött fájlt, és engedélyezd a
telepítést ismeretlen forrásból. A `-debug.apk` változat hibakereséshez
való. Minden CI-futás a debug APK-t `belefer-android-debug-apk`
artifactként is feltölti (GitHub-bejelentkezéssel, zipben tölthető le).

## iPhone-ra telepítés (ingyenes Apple ID-val)

iOS-en linkről nem lehet appot telepíteni, ezért a kiadás egy aláíratlan
csomagot is tartalmaz: `belefer-26.11.2-unsigned.ipa`. Ezt a
[SideStore](https://docs.sidestore.io/docs/installation/prerequisites) írja
alá a saját Apple ID-ddal:

1. Telepítsd a SideStore-t a leírás szerint (iloader, LocalDevVPN).
2. Töltsd le az `.ipa` fájlt az iPhone-on a kiadás oldaláról (Fájlok app).
3. Kapcsold be a LocalDevVPN-t, majd a SideStore-ban: **My Apps → +**, és
   válaszd ki a letöltött fájlt.

Korlátok ingyenes Apple ID-val: legfeljebb 3 saját telepítésű app, és az
aláírás 7 napig érvényes, ezért ennyi időnként frissíteni kell a SideStore-ban
(**My Apps → Refresh All**, bekapcsolt LocalDevVPN-nel). Az adatok
frissítéskor megmaradnak.

Új verzióra (pl. 26.11.1 → 26.11.2) ugyanígy kell betölteni az új `.ipa`-t;
az adatok megmaradnak. A 26.11.1 kezdőképernyő-widgetje külön bővítmény, ezért
a SideStore két App ID-t használ hozzá (ingyenes Apple ID-val hetente legfeljebb
10 új App ID hozható létre).

## Automatikus rögzítés beállítása

**Android (Revolut-értesítések):** Beállítások → Automatikus rögzítés →
kapcsold be a *Revolut-fizetések rögzítése* kapcsolót, és add meg az
értesítés-hozzáférést. Mivel az app nem a Play Áruházból jön, az Android 13+
először szürkén mutatja a kapcsolót: Beállítások → Alkalmazások → Belefér →
⋮ → *Korlátozott beállítások engedélyezése*, majd újra. A Belefér kódja csak a
Revolut értesítéseit tartja meg, minden más alkalmazásét (bankokét,
üzenetekét) azonnal eldobja. A tételek a Belefér következő megnyitásakor
kerülnek be.

**iPhone (Apple Pay):** Parancsok app → Automatizálás → + → *Wallet*
(régebben *Tranzakció*) → válaszd ki a kártyát → *Azonnali futtatás* → új
parancs: *Fizetés rögzítése a Belefér-ben*, az Összeg és a Kereskedő a
*Parancs bemenetéből*, a Kártya mezőbe írd be, melyik kártya ez (pl.
„Saját Revolut”). Ismételd meg a többi kártyával (pl. „Közös”), és ugyanezt a
szót írd a számla felismerő szavai közé. Az automatizmus elutasított
fizetésnél is elindulhat; a 10 percen belül megismételt, azonos fizetésből
csak egy marad.

## Kezdőképernyő-widget

- **Android:** tartsd lenyomva a kezdőképernyőt → **Modulok/Widgetek** →
  **Belefér – havi egyenleg**.
- **iPhone:** tartsd lenyomva a kezdőképernyőt → **+** → **Belefér**
  (kicsi vagy közepes méret).

## Felhős build és ellenőrzés

A buildek GitHub Actionsben futnak, rögzített Flutter-verzióval (`3.47.9`).
Helyi fejlesztőeszközre nincs szükség.

| Munkafolyamat | Mit csinál |
| --- | --- |
| `CI` (`ci.yml`) | `dart format` ellenőrzés, `flutter analyze`, `flutter test`; Android debug APK és alapfolyamat Android-emulátoron; iOS-szimulátor build és alapfolyamat iOS-szimulátoron |
| `Release APK` (`release.yml`) | tesztek, debug APK, GitHub Release a megadott címkével |
| `iOS-projekt beállítása` (`ios-setup.yml`) | ML Kit erőforráscsomag, App Group jogosultság és a widget-bővítmény hozzáadása az Xcode-projekthez, visszacommitolva |
| `Dev` (`dev.yml`) | a `wip` ágon: formázás, `flutter analyze`, `flutter test`, Android debug APK |
| `Bootstrap` (`bootstrap.yml`) | hiányzó `android/`/`ios/` generálása, arculat, `pubspec.lock`, formázás, visszacommitolás |

Újrafuttatás: a repó **Actions** fülén válaszd ki a munkafolyamatot, majd a
**Run workflow** gombot.

> A forrás a `Ventyh1/belefer` repóban van. A buildek a
> `LTamasGDE/belefer-build` forkban futnak, mert a `Ventyh1` fiókon az
> Actions számlázási okból nem indul el. A két repó `main` ága azonos.

## Felépítés

```
lib/
  domain/      számítási logika: naptári nap, modellek, kategóriák,
               havi összesítés, formázás, közös mezőszabályok
  data/        Sembast-alapú helyi tároló
  state/       AppState (egyetlen állapotforrás) és AppScope
  ui/          téma, közös komponensek és a négy képernyő
test/          unit- és widgettesztek
integration_test/  alapfolyamat valódi eszközön/emulátoron
branding/      appikon és indítóképernyő-erőforrások
tool/          ikon- és platformgeneráló szkriptek
tool/model/    a saját nyelvi modell tanítóadat-generátora és tanítása
assets/model/  a betanított modell (belefer_model.bin)
```

### A saját modell újratanítása

```
pip install numpy scipy scikit-learn
python3 tool/model/train.py 0.6     # kb. 2 perc, 0.6 = az adatmennyiség aránya
python3 tool/model/probe.py "tegnap a hentesnél 6700"
```

A `train.py` a `lib/domain/quick_entry/lexicon.dart` kereskedőit és
kulcsszavait is felhasználja, kiírja az `assets/model/belefer_model.bin`
fájlt és a `test/fixtures/model_golden.json` ellenőrző kimeneteit; a Dart
oldali `test/domain/model/model_test.dart` ezekkel ellenőrzi, hogy a telefonon
pontosan ugyanazt számolja. A kézzel írt ellenőrző mondatok a
`tool/model/eval.tsv` fájlban vannak.

A betűkészletek (Inter, Poppins) a SIL Open Font License 1.1 alatt
használhatók; lásd `assets/fonts/OFL.txt`.
