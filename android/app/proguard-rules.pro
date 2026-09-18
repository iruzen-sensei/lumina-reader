# Lumina Reader — ProGuard / R8 rules
# Referenced by android/app/build.gradle.kts. Currently INERT: R8 shrinking
# is disabled (isMinifyEnabled = false) while the release build is being
# stabilized.
#
# Every rule below is namespace-verified against the actual dependency tree
# (pubspec.lock + each plugin's android namespace in the pub cache). Entries
# for packages that are NOT dependencies were deleted: d4rt (removed from the
# project), flutter_qjs / com.ktoda, flutter_secure_storage,
# shared_preferences, epubx / es.sitio (pure Dart), site.gemu (no such
# package), io.github.vvb2060.mediainfo (no such package). When re-enabling
# R8, test the release APK on a real device before shipping.

# --- Flutter ---------------------------------------------------------------
# Flutter ships its own rules via the engine AAR; keep the standard guard
# against stripping the launcher/entry points.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- Isar (namespace dev.isar.*) -------------------------------------------
# Isar uses codegen + reflection-free accessors, but its native bridge and
# generated schemas must survive shrinking.
-keep class dev.isar.** { *; }
-keep class isar.** { *; }
-keep class **.g.** { *; }
-keep class **IsarCollection { *; }
-dontwarn dev.isar.**

# --- media_kit / libmpv (namespace com.alexmercerind.*) --------------------
-keep class com.alexmercerind.** { *; }
-dontwarn com.alexmercerind.**

# --- flutter_inappwebview (namespace com.pichillilorenzo.*) ----------------
-keep class com.pichillilorenzo.** { *; }
-dontwarn com.pichillilorenzo.**

# --- flutter_web_auth_2 (namespace com.linusu.*) ---------------------------
-keep class com.linusu.** { *; }
-dontwarn com.linusu.**

# (floating / PiP rule removed with the phantom `floating` dependency —
#  zero imports anywhere in lib/; its 3.0.0 Android module still referenced
#  the removed Flutter v1 embedding and failed to compile on AGP 8.)

-dontwarn javax.naming.**
