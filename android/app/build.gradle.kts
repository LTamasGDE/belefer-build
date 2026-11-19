plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Állandó aláírókulcs (a CI a ANDROID_KEYSTORE_B64 titokból írja ki). Nélküle
// minden build más ideiglenes kulcsot kapna, és a frissítés csak az app
// eltávolítása (és az adatok elvesztése) után települne.
val beleferKeystore = System.getenv("BELEFER_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }
val beleferKeystorePassword = System.getenv("BELEFER_KEYSTORE_PASSWORD") ?: "belefer-android"

android {
    namespace = "com.ventyh1.belefer"
    // Az értesítések bővítménye legalább 37-es SDK-t kér.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Ütemezett értesítések régebbi Androidokon (java.time).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ventyh1.belefer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (beleferKeystore != null) {
            create("belefer") {
                storeFile = beleferKeystore
                storePassword = beleferKeystorePassword
                keyAlias = "belefer"
                keyPassword = beleferKeystorePassword
            }
        }
    }

    buildTypes {
        val signing = signingConfigs.findByName("belefer") ?: signingConfigs.getByName("debug")
        release {
            signingConfig = signing
            proguardFiles("proguard-rules.pro")
        }
        getByName("debug") {
            signingConfig = signing
        }
        // CI: a kiadási optimalizáló (R8) a debug-buildben is bekapcsolható,
        // hogy az emulátoros próba a kiadással azonos Java-oldalt teszteljen.
        if (System.getenv("BELEFER_MINIFY_DEBUG") == "1") {
            getByName("debug") {
                isMinifyEnabled = true
                proguardFiles(
                    getDefaultProguardFile("proguard-android-optimize.txt"),
                    "proguard-rules.pro",
                    "proguard-ci-debug.pro",
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
