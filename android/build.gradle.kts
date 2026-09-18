allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redirect all build output to <repo>/build/<subproject> (verbatim from the
// Flutter 3.47.4 template). Without this, :app builds into android/app/build
// while `flutter build apk` looks for the APK under <repo>/build/app/outputs/
// flutter-apk — the build succeeds but the tool reports "failed to produce an
// .apk file".
val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Evaluation-order guard (verbatim from the template): Gradle evaluates
// subprojects in alphabetical path order, so a plugin module sorting before
// ":app" (e.g. :android_intent_plus) would otherwise be fully evaluated by
// the time :app applies the Flutter Gradle plugin — whose PluginHandler then
// crashes registering afterEvaluate hooks on it. Forcing every subproject to
// depend on :app's evaluation keeps :app first, as the plugin assumes.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
