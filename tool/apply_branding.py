#!/usr/bin/env python3
"""A generált Android- és iOS-projekt testreszabása a Belefér arculatára.

Idempotens: többször is futtatható. Csak a Python standard könyvtárát
használja, így a CI-ban külön telepítés nélkül fut.
"""

import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "branding"
APP_NAME = "Belefér"


def _copy_tree(src: Path, dst: Path) -> None:
    for file in src.rglob("*"):
        if file.is_file():
            target = dst / file.relative_to(src)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(file, target)


def android() -> None:
    main = ROOT / "android" / "app" / "src" / "main"
    if not main.exists():
        print("Nincs android/ mappa, kihagyva.")
        return
    _copy_tree(BRANDING / "android" / "res", main / "res")

    manifest = main / "AndroidManifest.xml"
    text = manifest.read_text(encoding="utf-8")
    text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', text, count=1)
    if "android:enableOnBackInvokedCallback" not in text:
        text = text.replace(
            'android:icon="@mipmap/ic_launcher"',
            'android:icon="@mipmap/ic_launcher"\n'
            '        android:enableOnBackInvokedCallback="true"',
            1,
        )
    manifest.write_text(text, encoding="utf-8")
    print("Android: név, ikon és indítóképernyő beállítva.")


def ios() -> None:
    runner = ROOT / "ios" / "Runner"
    if not runner.exists():
        print("Nincs ios/ mappa, kihagyva.")
        return
    icons = runner / "Assets.xcassets" / "AppIcon.appiconset"
    for png in (BRANDING / "ios").glob("*.png"):
        shutil.copyfile(png, icons / png.name)

    plist = runner / "Info.plist"
    text = plist.read_text(encoding="utf-8")
    text = re.sub(
        r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
        rf"\g<1>{APP_NAME}\g<2>",
        text,
        count=1,
    )
    if "<key>CFBundleLocalizations</key>" not in text:
        text = text.replace(
            "<key>CFBundleDisplayName</key>",
            "<key>CFBundleLocalizations</key>\n"
            "\t<array>\n\t\t<string>hu</string>\n\t</array>\n"
            "\t<key>CFBundleDisplayName</key>",
            1,
        )
    text = re.sub(
        r"(<key>CFBundleDevelopmentRegion</key>\s*<string>)[^<]*(</string>)",
        r"\g<1>hu\g<2>",
        text,
        count=1,
    )
    plist.write_text(text, encoding="utf-8")
    print("iOS: név, nyelv és ikon beállítva.")


if __name__ == "__main__":
    android()
    ios()
    sys.exit(0)
