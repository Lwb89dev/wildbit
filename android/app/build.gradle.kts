import java.security.MessageDigest
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.ZipFile

private fun verifyElfLoadAlignment(bytes: ByteArray, description: String) {
    check(bytes.size >= 64 && bytes[0] == 0x7f.toByte() &&
        bytes[1] == 'E'.code.toByte() && bytes[2] == 'L'.code.toByte() &&
        bytes[3] == 'F'.code.toByte()) {
        "Native artifact is not an ELF shared object: $description"
    }

    val elfClass = bytes[4].toInt()
    check(elfClass == 1 || elfClass == 2) {
        "Unsupported ELF class in native artifact: $description"
    }
    check(bytes[5].toInt() == 1) {
        "Only little-endian ELF artifacts are supported: $description"
    }

    val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
    val programHeaderOffset = if (elfClass == 1) {
        header.getInt(28).toLong() and 0xffffffffL
    } else {
        header.getLong(32)
    }
    val programHeaderSize = header.getShort(if (elfClass == 1) 42 else 54)
        .toInt() and 0xffff
    val programHeaderCount = header.getShort(if (elfClass == 1) 44 else 56)
        .toInt() and 0xffff
    check(programHeaderSize > 0 && programHeaderCount > 0) {
        "Missing ELF program headers in native artifact: $description"
    }

    for (index in 0 until programHeaderCount) {
        val offset = programHeaderOffset + index.toLong() * programHeaderSize
        check(offset >= 0 && offset + programHeaderSize <= bytes.size) {
            "Invalid ELF program header in native artifact: $description"
        }
        val programHeader = offset.toInt()
        if (header.getInt(programHeader) != 1) continue // PT_LOAD
        val alignmentOffset = if (elfClass == 1) programHeader + 28 else programHeader + 48
        val alignment = if (elfClass == 1) {
            header.getInt(alignmentOffset).toLong() and 0xffffffffL
        } else {
            header.getLong(alignmentOffset)
        }
        check(alignment >= 16 * 1024L) {
            "Native artifact has a PT_LOAD segment below 16 kB: $description"
        }
    }
}

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

    // Keep .so files uncompressed and page-aligned in the final APK. This is
    // required by Android devices configured with 16 kB memory pages.
    packaging {
        jniLibs {
            useLegacyPackaging = false
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
// as a prebuilt blob so normal builds stay offline. It was rebuilt from
// eSpeak NG 1.52.0 using Android NDK r28 with 16 kB LOAD alignment.
// This catches both replacement and accidental reintroduction of a 4 kB ELF.
val bundledNativeChecksums = mapOf(
    "src/main/jniLibs/arm64-v8a/libespeak-ng.so" to
        "4774249ebce5ac1cce954eee05b6413a123c5e50d50387d03b4237da4701860c",
    "src/main/jniLibs/armeabi-v7a/libespeak-ng.so" to
        "7e22ae3687e1d3c788b2c1717ab36eeb9a0e40025ab15f2a78f70aae4fb9b8c4",
    "src/main/jniLibs/x86_64/libespeak-ng.so" to
        "b05d149d076e138f7836739a11dde4b52ca7f4ae987a42b4d48c072a13806791",
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

            if (artifact.extension == "so") {
                val bytes = artifact.readBytes()
                check(bytes.size >= 64 && bytes[0] == 0x7f.toByte() &&
                    bytes[1] == 'E'.code.toByte() && bytes[2] == 'L'.code.toByte() &&
                    bytes[3] == 'F'.code.toByte()) {
                    "Bundled native artifact is not an ELF shared object: $path"
                }

                val elfClass = bytes[4].toInt()
                check(elfClass == 1 || elfClass == 2) {
                    "Unsupported ELF class in bundled native artifact: $path"
                }
                check(bytes[5].toInt() == 1) {
                    "Only little-endian ELF artifacts are supported: $path"
                }

                val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                val programHeaderOffset = if (elfClass == 1) {
                    header.getInt(28).toLong() and 0xffffffffL
                } else {
                    header.getLong(32)
                }
                val programHeaderSize = header.getShort(if (elfClass == 1) 42 else 54)
                    .toInt() and 0xffff
                val programHeaderCount = header.getShort(if (elfClass == 1) 44 else 56)
                    .toInt() and 0xffff
                check(programHeaderSize > 0 && programHeaderCount > 0) {
                    "Missing ELF program headers in bundled native artifact: $path"
                }

                for (index in 0 until programHeaderCount) {
                    val offset = programHeaderOffset + index.toLong() * programHeaderSize
                    check(offset >= 0 && offset + programHeaderSize <= bytes.size) {
                        "Invalid ELF program header in bundled native artifact: $path"
                    }
                    val programHeader = offset.toInt()
                    if (header.getInt(programHeader) != 1) continue // PT_LOAD
                    val alignmentOffset = if (elfClass == 1) {
                        programHeader + 28
                    } else {
                        programHeader + 48
                    }
                    val alignment = if (elfClass == 1) {
                        header.getInt(alignmentOffset).toLong() and 0xffffffffL
                    } else {
                        header.getLong(alignmentOffset)
                    }
                    check(alignment >= 16 * 1024L) {
                        "Bundled native artifact has a PT_LOAD segment below 16 kB: $path"
                    }
                }
            }
        }
    }
}

// Plugins contribute their .so files after `preBuild`, so verify the actual
// release APK too. This prevents a compliant bundled eSpeak from masking an
// incompatible third-party native dependency.
val verifyRelease16kNativeLibraries by tasks.registering {
    dependsOn("packageRelease")
    val releaseApk = layout.buildDirectory.file("outputs/apk/release/app-release.apk")
    inputs.file(releaseApk)
    doLast {
        val apk = releaseApk.get().asFile
        check(apk.isFile) { "Missing release APK for 16 kB validation: $apk" }
        ZipFile(apk).use { zip ->
            val nativeEntries = zip.entries().toList().filter { entry ->
                !entry.isDirectory && entry.name.startsWith("lib/") &&
                    entry.name.endsWith(".so")
            }
            check(nativeEntries.isNotEmpty()) {
                "Release APK contains no native libraries to validate: $apk"
            }
            for (entry in nativeEntries) {
                zip.getInputStream(entry).use { stream ->
                    verifyElfLoadAlignment(stream.readBytes(), "${apk.name}!/${entry.name}")
                }
            }
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn(verifyBundledNativeAssets)
}

tasks.configureEach {
    if (name == "assembleRelease") {
        finalizedBy(verifyRelease16kNativeLibraries)
    }
}
