// Applied by bootstrap_client.py after SDK platform generation.
android {
    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        externalNativeBuild {
            cmake { cppFlags += "-std=c++17" }
        }
    }
    buildTypes.getByName("release") {
        proguardFile(file("../../platform_config/android/proguard-rules.pro"))
    }
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
dependencies {
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
}
