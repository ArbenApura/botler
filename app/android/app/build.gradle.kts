plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.util.Properties

// THE RELEASE KEY: key.properties (next to this folder's parent, gitignored) names the keystore. Without it a release build is signed with the
// debug key, which installs on the owner's own phone but is not for sharing.
// UPDATE: since the in-app updates plan (BTL-20261022-1428) that fallback is gone and a release build without key.properties fails.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.arbenger.botler"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Scheduled notifications use java.time on older Android versions
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.arbenger.botler"
        // Android 7.0 and newer. Exact alarms, biometrics and the on-device text reader all work from here
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // R8 shrinking breaks the shared_preferences plugin (NoSuchMethodError at start), so the release build is not shrunk
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // No debug fallback any more: an update only installs over the same key, so every release build must use the release key
            signingConfig = if (keyProps.containsKey("storeFile")) signingConfigs.getByName("release") else null
        }
    }
}

// A release build without key.properties fails loudly instead of producing an APK that could never update the installed app
gradle.taskGraph.whenReady {
    val releaseBuild = allTasks.any { it.name.matches(Regex("(assemble|bundle|package)Release")) }
    if (releaseBuild && !keyProps.containsKey("storeFile")) {
        throw GradleException("app/android/key.properties is missing: a release build must be signed with the release key (see docs/ANDROID.md)")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
