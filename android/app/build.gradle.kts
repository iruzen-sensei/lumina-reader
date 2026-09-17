import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
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
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.lumina.reader"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
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

flutter {
    source = "../.."
}
