plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "in.farmerapp.kisan"
    // permission_handler_android 14 compiles against API 37 and requires
    // apps depending on it to do the same (targetSdk stays Flutter's).
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on API 26+ devices.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {

        applicationId = "in.farmerapp.kisan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // FM-014 (< 25 MB per ABI): store the native libraries (Flutter engine,
    // SQLCipher, CameraX JNI) compressed in the APK. Farmers side-load or
    // download over 2G/3G, so the file size is what they pay for; the cost
    // is that Android extracts the .so files at install (~17 MB more on
    // disk, fine on the 16 GB reference phones, NF-001). Play delivers AAB
    // splits compressed on the wire either way.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // SEC-008: never debuggable, R8 shrinking + obfuscation of the
            // Java/Kotlin side (Dart: --obfuscate --split-debug-info in
            // tool/build_release.sh), unused resources removed.
            isDebuggable = false
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // SEC-024 Play Integrity standard requests (MainActivity.kt).
    implementation("com.google.android.play:integrity:1.6.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
