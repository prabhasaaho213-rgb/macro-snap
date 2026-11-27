plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.macrosnap.macro_snap"
    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // Removed ndkVersion — use Flutter's bundled NDK

    defaultConfig {
        applicationId = "com.macrosnap.macro_snap"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // The App Links host, in ONE place: the https intent filter, the
        // assetlinks file the server serves and the shared invite URL all have
        // to agree, so the host is a placeholder instead of a literal in the
        // manifest. Override without editing code:
        //   flutter build appbundle --dart-define=... -PappLinkHost=links.example.com
        manifestPlaceholders["appLinkHost"] =
            (project.findProperty("appLinkHost") as String?)
                ?: "macro-snap-backend.vercel.app"
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    // IMPORTANT: Release builds MUST use upload-keystore.jks, not the debug keystore.
    // Google Sign-In requires the signing certificate's SHA-1 to be registered in
    // Firebase Console. Only upload-keystore.jks's SHA-1 is registered.
    // If you change the keystore, update Firebase Console or Sign-In will break.
    signingConfigs {
        create("release") {
            storeFile = rootProject.file(keystoreProperties.getProperty("storeFile", "upload-keystore.jks"))
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            // AGP stopped adding the v1 (JAR) signature because minSdk is 26,
            // so the sideloaded APK carried a v2 signature ONLY. Several OEM
            // installers (MIUI/HyperOS, the reported "App not installed as
            // package appears to be invalid") reject an APK they cannot verify
            // through the JAR manifest, so all three schemes are written now.
            // Play ignores the extra schemes and re-signs with its own key.
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = false
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8 code + resource shrinking, declared explicitly (Play Console
            // flags "Optimized resource shrinking isn't enabled" otherwise).
            // With AGP 9 the optimized resource-shrinking pipeline
            // (android.r8.optimizedResourceShrinking) is standard whenever the
            // resource shrinker is on. Without these rules R8 strips Gson
            // generic signatures, breaking flutter_local_notifications'
            // scheduled-notification cache and pendingNotificationRequests
            // (TypeToken error at runtime) — covered in proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Reads the `referrer=join_code=CODE` a league invite carries through the
    // Play Store install, so a friend who installs from the link lands in the
    // league without tapping it again. Called from MainActivity's
    // macrosnap/install_referrer channel.
    implementation("com.android.installreferrer:installreferrer:2.2")
}

flutter {
    source = "../.."
}
