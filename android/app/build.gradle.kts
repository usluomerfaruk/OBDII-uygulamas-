plugins {
    id("com.android.application")
    kotlin("android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin") // Bu satır sizin orijinal dosyanızdan geldi
}

android {
    namespace = "com.example.obd_app" // Orijinal dosyanızdaki namespace
    compileSdk = flutter.compileSdkVersion.toInt() 
    ndkVersion = flutter.ndkVersion.toString() // String olmasını sağlamak için toString eklendi

    compileOptions {
        // Bu versiyonları da Java 11 uyumluluğu için bıraktım
        sourceCompatibility = JavaVersion.VERSION_11 
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.obd_app"
        
        // KRİTİK DÜZELTME: minSdk değerini 21'e sabitledik.
        minSdk = flutter.minSdkVersion 
        
        targetSdk = flutter.targetSdkVersion.toInt()
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Burada ek bağımlılıklar varsa kalmalıdır
}
