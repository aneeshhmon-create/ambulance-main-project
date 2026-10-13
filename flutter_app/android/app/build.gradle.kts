plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.team19.ambulance"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        resValues = true
    }

    // ── Product Flavors ───────────────────────────────────────────────────────
    // Two flavors so both APKs can be installed simultaneously on the same device.
    // Build commands:
    //   flutter build apk --flavor user   -t lib/user_app/main.dart
    //   flutter build apk --flavor driver -t lib/driver_app/main.dart
    flavorDimensions += "app"

    productFlavors {
        create("user") {
            dimension = "app"
            applicationId = "com.team19.ambulance.user"
            resValue("string", "app_name", "Ambulance User")
        }
        create("driver") {
            dimension = "app"
            applicationId = "com.team19.ambulance.driver"
            resValue("string", "app_name", "Ambulance Driver")
        }
    }
    // ─────────────────────────────────────────────────────────────────────────

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
