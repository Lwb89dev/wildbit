import java.security.MessageDigest

val releaseStoreFile = System.getenv("WILDBIT_RELEASE_STORE_FILE")
val releaseStorePassword = System.getenv("WILDBIT_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("WILDBIT_RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("WILDBIT_RELEASE_KEY_PASSWORD")
val releaseSigningConfigured = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wildbit.wildbit"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wildbit.wildbit"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("wildbitRelease") {
                storeFile = file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            // Local smoke tests keep working without secrets. CI/distribution
            // sets all WILDBIT_RELEASE_* variables and gets a real signature.
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("wildbitRelease")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// The native eSpeak NG phonemizer (used by Bit's offline voice) is committed
// as a prebuilt blob so normal builds stay offline. This catches accidental
// or malicious replacement of that blob even on a plain `flutter build`.
val bundledNativeChecksums = mapOf(
    "src/main/jniLibs/arm64-v8a/libespeak-ng.so" to
        "a53a8ce4a9f815f393d10a220772701c077a3773aad6e8c0256341671f7b6955",
    "src/main/jniLibs/armeabi-v7a/libespeak-ng.so" to
        "8097f3faf64b01ef5f76e693f1d58ea0ae518945e49a6dd555d9efabb38e582d",
    "src/main/jniLibs/x86_64/libespeak-ng.so" to
        "eaa1991e55b9194a1e97eac745d4a3d9dbab64b0382a54004fe800a1416daa5e",
    "../../assets/espeak-ng-data.tar.gz" to
        "441d5fcf375f9bd0418fda5fa772d386388ea31e95de95f7e3a96c57104b67f3",
)

val verifyBundledNativeAssets by tasks.registering {
    val checkedFiles = bundledNativeChecksums.keys.map(::file)
    inputs.files(checkedFiles)
    doLast {
        for ((path, expected) in bundledNativeChecksums) {
            val artifact = file(path)
            check(artifact.isFile) { "Missing bundled native artifact: $path" }
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(artifact.readBytes())
                .joinToString("") { "%02x".format(it) }
            check(digest == expected) {
                "Bundled native artifact failed SHA-256 verification: $path"
            }
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(verifyBundledNativeAssets)
}
