#!/usr/bin/env bash
# Integrációs teszt futtatása az emulátoron időkorláttal és egy újrapróbával:
# a Flutter néha nem kapcsolódik az elinduló apphoz, és ilyenkor percekig
# kimenet nélkül vár.
set -u
target="$1"
limit="${2:-900}"
for attempt in 1 2; do
  if timeout "$limit" flutter test "$target" -d emulator-5554 --reporter expanded; then
    exit 0
  fi
  echo "::warning::$target: a(z) $attempt. futás sikertelen vagy elakadt."
  adb -s emulator-5554 logcat -d -t 400 \
    | grep -iE "flutter|belefer|mlkit|vision|AndroidRuntime|FATAL|Exception" \
    | tail -120 || true
  adb -s emulator-5554 shell am force-stop com.ventyh1.belefer || true
done
exit 1
