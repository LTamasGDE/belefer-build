# Csak a CI-ben, a minifikált debug-buildhez: a Flutter beágyazás (a kiadási
# buildben ezt a Flutter saját szabályai adják).
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**
