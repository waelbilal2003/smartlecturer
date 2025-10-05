plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.smartwael"
    // ✅ الترقية إلى 36 كما هو مطلوب من الإضافات
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    // ✅✅ توحيد إصدار Java لكل من Java و Kotlin
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = '11'
    }

    defaultConfig {
        applicationId = "com.example.smartwael"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ملاحظة: isMinifyEnabled و isShrinkResources يجب أن يكونا متطابقين
            // إذا كان أحدهما true، يجب أن يكون الآخر true أيضًا.
            isMinifyEnabled = true
            isShrinkResources = true // تفعيل هذا أيضًا لحل مشكلة سابقة

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
