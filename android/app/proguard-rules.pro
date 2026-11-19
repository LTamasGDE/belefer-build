# A szövegfelismerés csak a latin írást tartalmazza; a többi írásrendszer
# opcionális ML Kit-moduljaira a bővítmény hivatkozik, de nincsenek benne.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit szövegfelismerés: a natív (JNI) rész és a komponensregisztráció
# osztálynév szerint keresi az osztályokat, ezért ezeket az optimalizáló nem
# nevezheti át és nem hagyhatja ki (különben a beolvasás kiadási buildben
# hibával áll le).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.odml.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-dontwarn com.google.android.play.core.**
