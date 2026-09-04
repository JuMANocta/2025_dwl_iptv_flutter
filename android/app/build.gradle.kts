import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Charge les propriétés de signature depuis android/key.properties (local uniquement)
// En CI : build non signé → apksigner signe après
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}
val hasSigningConfig = keystorePropertiesFile.exists() && keystoreProperties["keyAlias"] != null

// §apkDiet — L'ABI x86_64 est RETIRÉE de l'APK de release.
//
// Mesuré sur l'APK 1.16.16 : les bibliothèques natives pèsent 94,6 % du paquet,
// et elles y sont stockées NON COMPRESSÉES (Android les mappe en mémoire depuis
// l'APK). Réparties : x86_64 21,5 Mo, arm64-v8a 20,0 Mo, armeabi-v7a 18,0 Mo.
// Tout le reste réuni ne fait que 3,8 Mo.
//
// AUCUN matériel réel visé n'est x86_64 : ni téléphone Android, ni Fire TV
// Stick (armeabi-v7a / arm64), ni box, ni téléviseur. Cette ABI ne sert qu'à
// l'ÉMULATEUR — et `driver.sh` y installe justement un build **release**, pas
// debug. D'où l'échappatoire plutôt qu'un retrait sec :
//
//     flutter build apk --release -Pabi-x86=true      (ou : driver.sh build --x86)
//
// ⚠️ Sans cette option, `adb install` sur l'AVD échoue en
// INSTALL_FAILED_NO_MATCHING_ABIS — c'est attendu, pas un bug de packaging.
//
// ⚠️ POURQUOI PAS `ndk { abiFilters }` — piège payé le 2026-09-02 : AGP **unit**
// (union) les `abiFilters` de `defaultConfig`, des flavors et du `buildType`.
// Le plugin Gradle de Flutter en déclare déjà, donc en ajouter au buildType
// n'enlève RIEN — le build passe, et l'APK sort inchangé à 61,7 Mo. Seule
// l'exclusion au PACKAGING retire vraiment les fichiers, et `onVariants` la
// limite proprement au release (le debug reste universel).
val keepX86 = project.hasProperty("abi-x86")

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        if (!keepX86) {
            variant.packaging.jniLibs.excludes.add("lib/x86_64/*.so")
            variant.packaging.jniLibs.excludes.add("lib/x86/*.so")
        }
    }
}

android {
    namespace =  "com.juman.aetherstream"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    // §apkDiet — L'app est en français imposé (§frOnly) et ne fournit que fr/en.
    // Sans ce filtre, `resources.arsc` et `res/` embarquent les 84 locales de
    // media3-ui, androidx et Material — des traductions qu'aucun écran ne peut
    // afficher, puisque `main.dart` fige `locale: Locale('fr')`.
    androidResources {
        localeFilters += listOf("fr", "en")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.juman.aetherstream"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasSigningConfig) signingConfigs.getByName("release") else null
            // §apkDiet — le retrait de x86_64 se fait au packaging, en tête de
            // fichier (`androidComponents.onVariants`). Ne PAS le refaire ici en
            // `ndk { abiFilters }` : AGP les unionne, ça ne retire rien.
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // §castRelay — Conversion du son POUR LE CAST : le récepteur générique de
    // Google ne décode ni AC3 ni DTS (constaté sur Philips Android TV le
    // 2026-09-04 : image sans son). Media3 Transformer réencode la seule piste
    // audio en AAC et RECOPIE la vidéo, puis le fichier est servi au
    // téléviseur par le serveur HTTP local de l'app.
    //
    // ⚠️ Le moteur vendoré (`packages/aether_video`) apporte déjà media3 1.5.0
    // (exoplayer, hls, session…) : rester sur la MÊME version, sinon Gradle
    // résout deux jeux d'artefacts et le lecteur casse.
    implementation("androidx.media3:media3-transformer:1.5.0")
    implementation("androidx.media3:media3-muxer:1.5.0")
    implementation("androidx.media3:media3-effect:1.5.0")
    implementation("androidx.media3:media3-common:1.5.0")
}
