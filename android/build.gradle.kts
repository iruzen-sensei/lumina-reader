// Gradle 9 evaluates subprojects in alphabetical path order. Any Flutter
// plugin module whose name sorts before ":app" (e.g. :android_intent_plus)
// is therefore already evaluated when the Flutter Gradle plugin applies to
// :app — and Flutter 3.47.4's PluginHandler then dies with
// "Cannot run Project.afterEvaluate(Action) when the project is already
// evaluated" (PluginHandler.kt:122). Forcing :app to configure first
// restores the ordering the Flutter plugin assumes. Verified against a
// minimal Gradle 9.3.1 multi-project repro. Remove when Flutter fixes
// PluginHandler (still unfixed on master as of 3.47.4).
evaluationDependsOn(":app")

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val clean by tasks.registering(Delete::class) {
    delete(rootProject.layout.buildDirectory)
}
