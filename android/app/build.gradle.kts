import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// ── Lecture de key.properties ────────────────────────────────────────────────
val keyProps = Properties()
val keyPropsFile = rootProject.file("key.properties")   // android/key.properties → absent du git
if (keyPropsFile.exists()) keyProps.load(keyPropsFile.inputStream())

android {
    namespace = "sn.dem.demapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    // ── Signing ───────────────────────────────────────────────────────────────
    signingConfigs {
        create("release") {
            storeFile     = file(keyProps["storeFile"]     as String)
            storePassword = keyProps["storePassword"]      as String
            keyAlias      = keyProps["keyAlias"]           as String
            keyPassword   = keyProps["keyPassword"]        as String
        }
    }

    defaultConfig {
        applicationId = "sn.dem.demapp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        val mapsProps = Properties()
        val mapsPropsFile = rootProject.file("maps.properties")
        if (mapsPropsFile.exists()) mapsProps.load(mapsPropsFile.inputStream())
        val localProps = Properties()
        val localPropsFile = rootProject.file("local.properties")
        if (localPropsFile.exists()) localProps.load(localPropsFile.inputStream())
        val googleMapsKey = mapsProps.getProperty("GOOGLE_MAPS_API_KEY")
            ?: localProps.getProperty("GOOGLE_MAPS_API_KEY") ?: ""
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = googleMapsKey
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled   = true    // obfuscation du code
            isShrinkResources = true    // supprime les ressources inutilisées
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
