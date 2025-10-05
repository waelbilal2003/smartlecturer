plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.smartlecturer"
    compileSdk = 34

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.smartwael"
        // التعيين الصحيح للـ minSdk و targetSdk في صيغة Kotlin DSL
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // السطر الصحيح
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName

        // ✅ تمكين requestLegacyExternalStorage للتوافق
        manifestPlaceholders["requestLegacyExternalStorage"] = true
    }
    buildTypes {
        release {
            isMinifyEnabled = false
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
