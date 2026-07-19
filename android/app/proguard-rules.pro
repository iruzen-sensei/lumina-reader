# Flutter engine & embedding
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core (referenced by Flutter deferred components, not bundled)
-dontwarn com.google.android.play.core.**

# Kotlin
-dontwarn kotlin.**

# media_kit / libmpv (JNI)
-keep class com.alexmercerind.** { *; }
-keep class dev.media_kit.** { *; }

# flutter_inappwebview
-keep class com.pichillilorenzo.** { *; }

# flutter_local_notifications (Gson reflection)
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# flutter_qjs (QuickJS JNI)
-keep class soko.ekibun.flutter_qjs.** { *; }

# flutter_background_service
-keep class id.flutter.flutter_background_service.** { *; }

# Isar
-keep class dev.isar.** { *; }

# Firebase / Firestore
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
