import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.rotransit.app"
    // compileSdk, ndkVersion and minSdk are pinned above the Flutter 3.27
    // defaults (flutter.compileSdkVersion etc.) for the plugins this app uses.
    // Revisit these pins when upgrading Flutter.
    compileSdk = 36
    ndkVersion = "28.1.13356709"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_21.toString()
    }

    defaultConfig {
        applicationId = "com.rotransit.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Only for local release runs with allowDebugRelease=true (see below).
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Never ship a debug-signed release by accident: without key.properties a
// release build fails unless allowDebugRelease=true (for example in
// ~/.gradle/gradle.properties for local testing).
gradle.taskGraph.whenReady {
    val releaseTask = allTasks.any {
        it.name.endsWith("Release") && (it.name.startsWith("assemble") || it.name.startsWith("bundle"))
    }
    val allowDebugRelease = project.findProperty("allowDebugRelease")?.toString() == "true"
    if (releaseTask && !keystorePropertiesFile.exists() && !allowDebugRelease) {
        throw GradleException(
            "android/key.properties is missing, so this release would be debug-signed. " +
                "Run scripts/setup-android-signing.sh, or for a local test build set " +
                "allowDebugRelease=true in ~/.gradle/gradle.properties " +
                "(or flutter build ... --android-project-arg allowDebugRelease=true).",
        )
    }
}

flutter {
    source = "../.."
}
