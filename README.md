# Belefér

Magyar nyelvű, személyes pénzügykövető Androidra és iOS-re, Flutterrel.
Kiadás: **26.11.0**, alkalmazásverzió: `0.1.0+1`.

## Funkciók

- **Áttekintés:** a kiválasztott hónap bevétele, kiadása és a kettő különbsége
  („Maradt”). Előző és következő hónapra lehet lapozni. Az interaktív
  gyűrűdiagram kategóriánként mutatja a kiadásokat (`100% | 124 500 Ft`). Egy
  szeletre vagy jelmagyarázati sorra koppintva megjelenik a kategória neve,
  százaléka és pontos összege. Gyorsgombok: **Új kiadás**, **Új bevétel**.
- **Tételek:** kiadás és bevétel felvétele, megtekintése, szerkesztése és
  megerősítés utáni törlése. Mezők: megnevezés, összeg, típus, kategória,
  dátum (alapból a mai nap) és megjegyzés. A lista dátum szerint rendezett,
  hónap és típus szerint szűrhető.
- **Sablonok:** kiadási és bevételi sablonok (pl. *Lakbér*, *Fizetés*)
  névvel, kategóriával, opcionális összeggel és megjegyzéssel. Használatkor a
  kitöltött űrlap nyílik meg a mai dátummal. Mentés előtt minden mező
  szerkeszthető, a mentett tétel a saját adataival tárolódik.
- **Beállítások:** világos/sötét mód (újranyitás után is megmarad), az
  alkalmazás verziója a build metaadataiból, és **Összes adat törlése**
  megerősítéssel.

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

## APK letöltése (Android)

A telepíthető APK a build-repó kiadásai között van, bejelentkezés nélkül
letölthető: <https://github.com/LTamasGDE/belefer-build/releases/tag/26.11.0>.
Telefonon a `belefer-26.11.0.apk` fájlt érdemes letölteni (release mód,
debug-kulccsal aláírva). Nyisd meg a letöltött fájlt, és engedélyezd a
telepítést ismeretlen forrásból. A `-debug.apk` változat hibakereséshez
való. Minden CI-futás a debug APK-t `belefer-android-debug-apk`
artifactként is feltölti (GitHub-bejelentkezéssel, zipben tölthető le).

## Felhős build és ellenőrzés

A buildek GitHub Actionsben futnak, rögzített Flutter-verzióval (`3.47.9`).
Helyi fejlesztőeszközre nincs szükség.

| Munkafolyamat | Mit csinál |
| --- | --- |
| `CI` (`ci.yml`) | `dart format` ellenőrzés, `flutter analyze`, `flutter test`; Android debug APK és alapfolyamat Android-emulátoron; iOS-szimulátor build és alapfolyamat iOS-szimulátoron |
| `Release APK` (`release.yml`) | tesztek, debug APK, GitHub Release a megadott címkével |
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
```

A betűkészletek (Inter, Poppins) a SIL Open Font License 1.1 alatt
használhatók; lásd `assets/fonts/OFL.txt`.
