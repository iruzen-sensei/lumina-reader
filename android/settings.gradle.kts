pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 8.11.1 / KGP 2.2.20 = Flutter 3.47.4's exact minimum supported
    // versions. Several pinned plugins (win32-5 cascade: inappwebview 6.x,
    // file_picker 11, share_plus 12, wakelock_plus 1.5.2) ship 2025-era
    // Android modules written for the AGP 8 world — e.g. inappwebview uses
    // getDefaultProguardFile('proguard-android.txt'), which AGP 9 removed.
    // Stay on the last AGP 8 line until those plugins are upgraded.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
