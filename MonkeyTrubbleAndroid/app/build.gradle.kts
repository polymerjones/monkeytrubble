import java.util.Properties

plugins {
    id("com.android.application")
}

// Release signing reads the upload key from keystore.properties (storeFile, storePassword, keyAlias, keyPassword), kept out of git.
val keystoreProps = Properties().apply {
    rootProject.file("keystore.properties").takeIf { it.exists() }?.inputStream()?.use(::load)
}

android {
    namespace = "com.paulfisher.monkeytrubble"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.paulfisher.monkeytrubble"
        minSdk = 26
        targetSdk = 36
        versionCode = 14
        versionName = "1.0"

        // AdMob app ID (Android app in the AdMob console). Release builds use the real rewarded unit; debug builds use Google's
        // sample rewarded unit, so testing never serves or clicks real ads.
        manifestPlaceholders["admobAppId"] = "ca-app-pub-2053987639996867~1017622010"
        buildConfigField("String", "ADMOB_REWARDED_ID", "\"ca-app-pub-3940256099942544/5224354917\"")
    }

    signingConfigs {
        if (keystoreProps.isNotEmpty()) {
            create("upload") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            buildConfigField("String", "ADMOB_REWARDED_ID", "\"ca-app-pub-2053987639996867/3791572124\"")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("upload")?.let { signingConfig = it }
        }
    }

    buildFeatures {
        buildConfig = true
    }

    // The card art, music and calls are already compressed; storing them as-is lets the WebView read them straight from the APK.
    androidResources {
        noCompress += listOf("mp3", "wav", "jpg", "png", "webp")
    }
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.13.0")
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.webkit:webkit:1.17.1")
    implementation("com.google.android.gms:play-services-games-v2:22.1.0")
    implementation("com.google.android.gms:play-services-ads:25.5.0")
    implementation("com.google.android.ump:user-messaging-platform:4.0.0")
}

/** Copies ../web into the app's assets as web/, the same way Xcode bundles it for iPhone, so edits there ship on the next build. */
abstract class BundleWebTask : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val webDir: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @get:Inject
    abstract val fs: FileSystemOperations

    @TaskAction
    fun bundle() {
        fs.sync {
            from(webDir)
            into(outputDir.dir("web"))
            // Web-only and tooling files: the phone-frame page, AdMob's app-ads.txt and vercel.json (monkeytrubble.app), the service
            // worker (register-sw.js stays; without sw.js it does nothing), build scripts, server SQL, concept art.
            exclude("frame.html", "sw.js", "app-ads.txt", "vercel.json", "tools/**", "supabase/**", "dl gfx/**", "**/.DS_Store", "README.md")
        }
    }
}

val bundleWeb = tasks.register<BundleWebTask>("bundleWeb") {
    webDir.set(rootProject.layout.projectDirectory.dir("../web"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(bundleWeb, BundleWebTask::outputDir)
    }
}
