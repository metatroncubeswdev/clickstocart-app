import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties from key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile =
    listOf(rootProject.file("key.properties"), rootProject.file("../key.properties"))
        .firstOrNull { it.exists() }
if (keystorePropertiesFile != null) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val hasReleaseKeystore =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
        keystoreProperties.getProperty(it)?.isNotBlank() == true
    }
val storeFilePath = keystoreProperties.getProperty("storeFile")
val releaseKeystoreFile =
    if (storeFilePath.isNullOrBlank()) {
        null
    } else {
        listOfNotNull(
            keystorePropertiesFile?.parentFile?.resolve(storeFilePath),
            rootProject.file(storeFilePath),
            rootProject.file("../$storeFilePath"),
        ).firstOrNull { it.exists() } ?: keystorePropertiesFile?.parentFile?.resolve(storeFilePath)
    }

// Firebase (google-services.json) — only applied once that file actually
// exists, so the build doesn't break before Firebase/push notifications are
// set up. Drop google-services.json in this directory to activate it.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.clickstocart.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required by flutter_local_notifications (push notification display).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.clickstocart.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Disable code and resource shrinking for first release
            isMinifyEnabled = false
            isShrinkResources = false

            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
