# Lumina Reader — ProGuard / R8 rules
# Referenced by android/app/build.gradle.kts (was missing entirely, which
# broke release builds with minifyEnabled=true).

# --- Flutter ---------------------------------------------------------------
# Flutter ships its own rules via the engine AAR; keep the standard guard
# against stripping the launcher/entry points.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- Isar ------------------------------------------------------------------
# Isar uses codegen + reflection-free accessors, but its native bridge and
# generated schemas must survive shrinking.
-keep class dev.isar.** { *; }
-keep class isar.** { *; }
-keep class com.example.**.isar.** { *; }
-keep class **.g.** { *; }
-keep class **IsarCollection { *; }
-dontwarn dev.isar.**

# --- media_kit / libmpv ----------------------------------------------------
-keep class com.alexmercerind.media_kit.** { *; }
-keep class io.github.vvb2060.mediainfo.** { *; }
-dontwarn com.alexmercerind.**

# --- QuickJS (flutter_qjs) -------------------------------------------------
-keep class com.ktoda.** { *; }
-dontwarn com.ktoda.**

# --- d4rt (Dart interpreter) ----------------------------------------------
-keep class d4rt.** { *; }
-dontwarn d4rt.**

# --- epubx / archive -------------------------------------------------------
-keep class es.sitio.** { *; }
-dontwarn es.sitio.**

# --- Plugins with JNI bridges ---------------------------------------------
-keep class site.gemu.** { *; }          # flutter_inappwebview
-keep class com.pichillilorenzo.** { *; } # flutter_inappwebview (legacy id)
-dontwarn site.gemu.**
-keep class com.linusu.** { *; }          # flutter_web_auth_2
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn javax.naming.**
