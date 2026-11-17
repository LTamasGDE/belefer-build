#!/usr/bin/env bash
# A hiányzó android/ és ios/ projektet a rögzített Flutter-verzióval
# generálja, majd ráteszi a Belefér arculatát (név, ikon, nyelv).
# Ha a mappák már léteznek, csak az arculati lépés fut le újra.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -d android || ! -d ios ]]; then
  had_widget_test=0
  [[ -f test/widget_test.dart ]] && had_widget_test=1
  flutter create \
    --project-name belefer \
    --org com.ventyh1 \
    --platforms android,ios \
    --no-pub \
    .
  # A sablon számlálós mintatesztje nem része a Belefér tesztjeinek.
  if [[ $had_widget_test == 0 && -f test/widget_test.dart ]]; then
    rm test/widget_test.dart
  fi
fi

python3 tool/apply_branding.py
