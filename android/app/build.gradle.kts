plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.upsc.upsc_daily_edge"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.upsc.upsc_daily_edge"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // Load signing properties if available (CI or local)
    val keyPropertiesFile = rootProject.file("key.properties")
    val useUploadSigning = keyPropertiesFile.exists()

    signingConfigs {
        if (useUploadSigning) {
            create("upload") {
                val lines = keyPropertiesFile.readLines()
                val props = mutableMapOf<String, String>()
                for (line in lines) {
                    val parts = line.split("=", limit = 2)
                    if (parts.size == 2) props[parts[0].trim()] = parts[1].trim()
                }
                storeFile = file(props["storeFile"] ?: "")
                storePassword = props["storePassword"] ?: ""
                keyAlias = props["keyAlias"] ?: ""
                keyPassword = props["keyPassword"] ?: ""
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (useUploadSigning) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
