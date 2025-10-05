plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.smartwael"
    compileSdk = 34  // ✅ دعم Android 14
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.smartwael"
        // ✅ إعدادات محدثة لدعم Android 14
        minSdk = 21  // الحد الأدنى لدعم معظم الميزات
        targetSdk = 34  // ✅ استهداف Android 14
        versionCode = flutter.versionCode
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
