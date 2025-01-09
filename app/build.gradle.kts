plugins {
    id("com.android.application")  // Make sure the Android application plugin is applied
    id("kotlin-android")  // For Kotlin support (if using Kotlin)
}

android {
    compileSdk = 33 // or whatever your target version is

    defaultConfig {
        applicationId = "com.yourapp.package"
        minSdk = 21 // use appropriate minSdkVersion
        targetSdk = 33 // or whatever your target version is
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),"build/app/outputs/mapping/release/missing_rules.txt"
                ,"proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // Add your dependencies here
    implementation("com.stripe:stripe-android:21.3.0") // Example dependency for Stripe, update version as required.
}

// You can include other configurations as necessary