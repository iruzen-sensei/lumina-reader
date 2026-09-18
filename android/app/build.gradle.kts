plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin
    // Gradle plugins. Do NOT add `kotlin-android` here: with
    // `android.builtInKotlin=false` the Flutter plugin applies KGP itself to
    // every subproject that needs it (app + plugin modules).
    id("dev.flutter.flutter-gradle-plugin")
}

// CI / local signing inputs. Unset or BLANK env vars (unset GitHub secrets
// arrive as "") fall back to the same defaults the workflow's "Prepare
// signing keystore" step uses, so both sides always agree.
fun envOrDefault(name: String, fallback: String): String =
    System.getenv(name)?.takeIf { it.isNotBlank() } ?: fallback

// The keystore the CI workflow materializes before the build:
// <repo>/.github/signing-keystore.jks (repo root = two levels above this
// android/app directory). KEYSTORE_PATH overrides it for local builds. When
// no keystore exists at all (fresh checkout without secrets), the release
// build falls back to the debug key further below instead of failing.
val releaseKeystore: File? =
    System.getenv("KEYSTORE_PATH")?.takeIf { it.isNotBlank() }?.let { file(it) }
        ?: rootProject.file("../.github/signing-keystore.jks").takeIf { it.exists() }

android {
    namespace = "com.lumina.reader"
    // flutter.* values come from the Flutter Gradle plugin and track the
    // pinned Flutter toolchain (3.47.4: compileSdk 36, NDK 28.2.13676358,
    // targetSdk 36) instead of hardcoding SDK versions that drift.
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (and friends) require core library
        // desugaring for java.time APIs below API 26 — the AAR metadata
        // check hard-fails the build without this flag.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.lumina.reader"
        // Deliberately above flutter.minSdkVersion (24): the background
        // service + workmanager code paths rely on API 26+ behavior.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only registered when a keystore file is actually present — see the
        // releaseKeystore val above.
        if (releaseKeystore != null) {
            create("release") {
                keyAlias = envOrDefault("KEY_ALIAS", "lumina")
                keyPassword = envOrDefault("KEY_PASSWORD", "lumina2026")
                storeFile = releaseKeystore
                storePassword = envOrDefault("KEYSTORE_PASSWORD", "lumina2026")
            }
        }
    }

    buildTypes {
        release {
            // Debug-key fallback keeps `flutter build apk --release` working
            // on fresh checkouts without a keystore; CI always provides one
            // (the workflow generates it before the build).
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            // R8 shrinking DISABLED while stabilizing the release build: the
            // previous rules file contained entries for packages that are not
            // dependencies (d4rt, flutter_qjs, flutter_secure_storage,
            // shared_preferences, epubx) plus guessed names, and shrinking can
            // break media_kit / WebView / OAuth / background services at
            // runtime with no build-time error. Re-enable ONLY together with
            // on-device verification of the release APK.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// KGP 2.x DSL (kotlinOptions {} was removed in Kotlin 2.4). The `kotlin`
// extension exists because the Flutter plugin applies KGP before this
// script body runs.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
