package com.juman.aetherstream

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.Clock
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultDecoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExoPlayerAssetLoader
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMuxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File

/**
 * §castRelay — Réencode le SON d'un flux pour qu'un récepteur Chromecast
 * puisse le lire, en RECOPIANT la vidéo telle quelle.
 *
 * **Pourquoi ça existe** : le récepteur générique de Google ne décode que
 * AAC / MP3 / Opus / Vorbis / FLAC / PCM. Les films IPTV arrivent en AC3,
 * E-AC3 ou DTS — constaté sur une Philips Android TV le 2026-09-04 : l'image
 * passe, le son non. Un téléphone ne peut pas transcoder à la volée pour le
 * téléviseur… mais il peut se mettre au milieu.
 *
 * ⚠️ **La recopie de la vidéo ne se DEMANDE pas, elle s'OBTIENT.** Mesuré deux
 * fois sur appareil le 2026-09-04 : `c2.qti.hevc.encoder` alloué, 1,3 Go
 * écrits par minute, téléviseur bloqué sur « Chargement ». Le bytecode de
 * Media3 1.5.0 (`TransformerUtil.shouldTranscodeVideo`) explique pourquoi
 * `Composition.setTransmuxVideo(true)` n'a rien changé : le drapeau n'est lu
 * QUE pour une composition à plusieurs éléments. Pour un fichier unique, la
 * décision revient à cinq critères sur le `Format` de la piste — et deux
 * d'entre eux se déclenchent sur les films 4K courants :
 *  - le **type MIME** : un Dolby Vision est publié `video/dolby-vision` par
 *    `MatroskaExtractor`, que le muxeur MP4 de Media3 n'accepte pas ;
 *  - le **rapport de pixels**, qui doit valoir exactement 1.
 * D'où [RelayExtractorsFactory] : on réécrit le `Format` **à la sortie de
 * l'extracteur**, avant que Transformer ne décide. C'est le seul point où on a
 * la main sans vendoriser le chargeur.
 *
 * ⚠️ **La langue se règle au même endroit.** Le sélecteur de pistes du
 * chargeur force le plus haut débit et n'expose aucun réglage (vérifié à
 * `javap`) : sur un film à trois pistes E-AC3, il avait pris l'Atmos anglais
 * contre deux françaises. On marque donc la piste voulue « par défaut » et les
 * autres « alternatives » — deux critères que le sélecteur consulte AVANT le
 * débit.
 *
 * ⚠️ **Profil de requête IPTV** : le flux source est demandé avec l'UA
 * `IPTVSmartersPro` (§iptvUaCompat), sans quoi les panels répondent 500.
 *
 * ⚠️ **Sortie fragmentée** : le fichier doit être lisible AVANT la fin de la
 * conversion. Un MP4 classique place son index à la fin et ne se lit qu'une
 * fois complet. Côté Dart, `CastRelayService` indexe les fragments au fil de
 * l'eau et les sert en HLS.
 */
@UnstableApi
class AetherCastRelay(private val context: Context) {

    interface Callbacks {
        /** Progression 0..100. */
        fun onProgress(percent: Int)
        fun onCompleted(outputPath: String)

        /**
         * [userFacing] : le message est déjà écrit en français pour l'écran
         * (refus motivé). Sinon c'est la cause technique, à ne pas afficher.
         */
        fun onFailed(message: String, userFacing: Boolean)
    }

    private var transformer: Transformer? = null
    private var outputFile: File? = null
    private val main = Handler(Looper.getMainLooper())
    private var progressTicker: Runnable? = null

    val isRunning: Boolean get() = transformer != null

    /** Chemin du fichier produit (existe dès les premiers fragments). */
    fun outputPath(): String? = outputFile?.absolutePath

    /**
     * [audioIndex] — rang de la piste audio à convertir, dans l'ordre du
     * fichier (le même que celui du lecteur, §engineVendor patch 11) ; `-1`
     * laisse Media3 choisir.
     *
     * [startMs] — §castResume : où COMMENCER la conversion. Convertir depuis
     * le début imposait d'attendre d'avoir converti tout ce qui précède pour
     * reprendre un film en cours (≈ 22 min d'attente pour un film vu à 45 min,
     * mesuré le 2026-09-05). On saute donc directement à la position.
     * ⚠️ Exige que la source accepte les requêtes partielles — la sonde
     * d'éligibilité l'a déjà vérifié (HTTP 206).
     */
    fun start(url: String, audioIndex: Int, startMs: Long, callbacks: Callbacks) {
        stop()

        val dir = File(context.cacheDir, "cast_relay").apply { mkdirs() }
        // Un seul relais à la fois : on repart d'un fichier propre.
        dir.listFiles()?.forEach { it.delete() }
        val out = File(dir, "relay.mp4")
        outputFile = out

        // §iptvUaCompat — même profil de requête que Dio et que le lecteur.
        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent("IPTVSmartersPro")
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(20_000)
            .setReadTimeoutMs(20_000)

        // ⚠️ Ce qui FORCE le réencodage de la piste AUDIO, c'est
        // `setAudioMimeType` ci-dessous : sans lui, Transformer recopie l'AC3
        // et le téléviseur reste muet. Aucun effet audio n'est nécessaire.
        // §castResume — La coupe se cale sur l'image clé précédente : on
        // repart au plus quelques secondes AVANT la position demandée, jamais
        // après. C'est le bon sens de l'erreur (on ne saute rien).
        val item = if (startMs > 0) {
            MediaItem.Builder()
                .setUri(url)
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(startMs)
                        .build()
                )
                .build()
        } else {
            MediaItem.fromUri(url)
        }
        if (startMs > 0) Log.i(TAG, "conversion démarrée à ${startMs / 1000} s")
        val edited = EditedMediaItem.Builder(item).build()
        // `setTransmuxVideo` est laissé pour l'intention ; il est SANS EFFET sur
        // un élément unique (voir l'en-tête). La recopie vient de l'extracteur.
        val composition = Composition.Builder(EditedMediaItemSequence(edited))
            .setTransmuxVideo(true)
            .build()

        var failed = false
        val refuse: (String) -> Unit = { message ->
            main.post {
                if (!failed) {
                    failed = true
                    stop()
                    callbacks.onFailed(message, userFacing = true)
                }
            }
        }

        val extractors = RelayExtractorsFactory(audioIndex, onUnsupported = refuse)

        val t = Transformer.Builder(context)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            // ⚠️ **Fragmenté, sinon rien n'est lisible avant la fin.** Un MP4
            // classique écrit son index (`moov`) à la toute fin. Les fragments
            // sont découpés à la première image clé après 2 s : c'est aussi le
            // grain des segments HLS servis au téléviseur.
            .setMuxerFactory(
                InAppMuxer.Factory.Builder()
                    .setOutputFragmentedMp4(true)
                    .setFragmentDurationMs(2_000)
                    .build()
            )
            // ⚠️ **Ne PAS trop allonger ce délai.** Par défaut Transformer
            // abandonne après 10 s sans échantillon au muxeur ; porté à 60 s
            // « pour tolérer les panels lents », il a surtout **bâillonné la
            // seule erreur** qui aurait expliqué un blocage constaté le
            // 2026-09-04 (3 fragments puis plus rien, une minute durant). Un
            // compromis : assez long pour un panel qui souffle, assez court
            // pour que Media3 parle avant qu'on abandonne nous-mêmes.
            .setMaxDelayBetweenMuxerSamplesMs(20_000)
            // ⚠️ **Ce qui met le son en phase avec l'image sur une reprise en
            // cours de film.** Mesuré le 2026-09-05 : sans ceci, les deux
            // pistes sont bien régulières (aucune dérive : 21 391 paquets AAC
            // = 456,33 s calculées contre 456,320 mesurées) mais elles ne
            // commencent PAS au même endroit du film. La vidéo, recopiée, doit
            // partir d'une image clé ; le son, réencodé, est coupé net à la
            // position demandée. Les deux sont ensuite remis à zéro — le
            // fichier paraît sain et le son a l'avance qui sépare l'image clé
            // de la position, soit ~2 s. Cette option réencode le court
            // fragment de tête pour obtenir une coupe EXACTE, et recopie tout
            // le reste : les deux pistes démarrent enfin au même instant.
            .experimentalSetTrimOptimizationEnabled(true)
            .setAssetLoaderFactory(
                ExoPlayerAssetLoader.Factory(
                    context,
                    DefaultDecoderFactory.Builder(context).build(),
                    Clock.DEFAULT,
                    DefaultMediaSourceFactory(httpFactory, extractors)
                )
            )
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, result: ExportResult) {
                    // Même garde qu'`onError` : après un refus (profil 5), une
                    // course ne doit pas envoyer « terminé » après « échoué ».
                    if (failed) return
                    failed = true
                    Log.i(
                        TAG,
                        "conversion finie — vidéo ${describeProcess(result.videoConversionProcess)}, " +
                            "son ${describeProcess(result.audioConversionProcess)}, " +
                        "coupe ${describeTrim(result.optimizationResult)}"
                    )
                    stopTicker()
                    callbacks.onProgress(100)
                    callbacks.onCompleted(out.absolutePath)
                    transformer = null
                }

                override fun onError(
                    composition: Composition,
                    result: ExportResult,
                    exception: ExportException
                ) {
                    Log.w(TAG, "conversion échouée : ${exception.errorCodeName} ${exception.message}")
                    stopTicker()
                    if (!failed) {
                        failed = true
                        callbacks.onFailed(
                            exception.message ?: "conversion impossible",
                            userFacing = false
                        )
                    }
                    transformer = null
                }
            })
            .build()

        transformer = t
        try {
            t.start(composition, out.absolutePath)
        } catch (e: Exception) {
            // Sinon `transformer` reste non nul : `isRunning` mentirait et
            // aucun arrêt ultérieur ne trouverait de quoi nettoyer.
            transformer = null
            failed = true
            callbacks.onFailed(e.message ?: "conversion impossible", false)
            return
        }
        startTicker(callbacks)
    }

    private fun startTicker(callbacks: Callbacks) {
        val holder = ProgressHolder()
        val ticker = object : Runnable {
            override fun run() {
                val t = transformer ?: return
                val state = t.getProgress(holder)
                if (state != Transformer.PROGRESS_STATE_NOT_STARTED) {
                    callbacks.onProgress(holder.progress)
                }
                main.postDelayed(this, 1000)
            }
        }
        progressTicker = ticker
        main.postDelayed(ticker, 1000)
    }

    private fun stopTicker() {
        progressTicker?.let { main.removeCallbacks(it) }
        progressTicker = null
    }

    fun stop() {
        stopTicker()
        try {
            transformer?.cancel()
        } catch (e: Exception) {
            // Rien à récupérer : on jette la conversion de toute façon.
        }
        transformer = null
    }

    /** Supprime le fichier temporaire (plusieurs Go). */
    fun clean() {
        stop()
        outputFile?.let { if (it.exists()) it.delete() }
        outputFile = null
    }

    /**
     * §castResume — Verdict de la coupe exacte. ⚠️ Media3 ne le rend qu'à la
     * FIN de l'export : trop tard pour décider quoi que ce soit, mais c'est
     * la seule façon de savoir après coup si le son pouvait être décalé.
     * `ABANDONNÉE (déjà optimale)` est un BON cas : la position tombait déjà
     * sur une image clé, rien à réencoder.
     */
    private fun describeTrim(result: Int): String = when (result) {
        ExportResult.OPTIMIZATION_NONE -> "sans objet"
        ExportResult.OPTIMIZATION_SUCCEEDED -> "EXACTE"
        ExportResult.OPTIMIZATION_ABANDONED_KEYFRAME_PLACEMENT_OPTIMAL_FOR_TRIM ->
            "abandonnée (déjà optimale)"
        else -> "ABANDONNÉE ($result) — son possiblement décalé"
    }

    private fun describeProcess(process: Int): String = when (process) {
        ExportResult.CONVERSION_PROCESS_TRANSMUXED -> "RECOPIÉE"
        ExportResult.CONVERSION_PROCESS_TRANSCODED -> "RÉENCODÉE"
        ExportResult.CONVERSION_PROCESS_TRANSMUXED_AND_TRANSCODED -> "mixte"
        else -> "?"
    }

    companion object {
        const val TAG = "AetherCastRelay"
    }
}

// ── Réécriture des formats à la sortie de l'extracteur ───────────────────────

/**
 * Enveloppe `DefaultExtractorsFactory` pour intercepter chaque `Format` publié
 * et le rendre **recopiable** par Transformer (voir l'en-tête du fichier).
 */
@UnstableApi
private class RelayExtractorsFactory(
    private val audioIndex: Int,
    private val onUnsupported: (String) -> Unit,
) : ExtractorsFactory {
    private val delegate = DefaultExtractorsFactory()

    override fun createExtractors(): Array<Extractor> =
        delegate.createExtractors().map { wrap(it) }.toTypedArray()

    override fun createExtractors(
        uri: Uri,
        responseHeaders: Map<String, List<String>>,
    ): Array<Extractor> =
        delegate.createExtractors(uri, responseHeaders).map { wrap(it) }.toTypedArray()

    private fun wrap(e: Extractor): Extractor = RelayExtractor(e, audioIndex, onUnsupported)
}

@UnstableApi
private class RelayExtractor(
    private val inner: Extractor,
    private val audioIndex: Int,
    private val onUnsupported: (String) -> Unit,
) : Extractor {
    override fun sniff(input: ExtractorInput): Boolean = inner.sniff(input)
    override fun init(output: ExtractorOutput) =
        inner.init(RelayExtractorOutput(output, audioIndex, onUnsupported))
    override fun read(input: ExtractorInput, seekPosition: PositionHolder): Int =
        inner.read(input, seekPosition)
    override fun seek(position: Long, timeUs: Long) = inner.seek(position, timeUs)
    override fun release() = inner.release()
    override fun getUnderlyingImplementation(): Extractor = inner.underlyingImplementation
}

@UnstableApi
private class RelayExtractorOutput(
    private val inner: ExtractorOutput,
    private val audioIndex: Int,
    private val onUnsupported: (String) -> Unit,
) : ExtractorOutput {
    /** Rang des pistes audio dans l'ordre du fichier — le même que le lecteur. */
    private var audioSeen = 0

    /// ⚠️ **Media3 rappelle `track()` pour une piste DÉJÀ connue** (nouveau
    /// PMT sur un TS, reprise après `seek`). Sans ce cache, `audioSeen`
    /// avançait à chaque rappel : les rangs se décalaient et la piste
    /// marquée « par défaut » n'était plus la bonne — soit exactement le
    /// bug de langue décrit en en-tête, mais silencieux.
    private val outputs = HashMap<Long, TrackOutput>()

    override fun track(id: Int, type: Int): TrackOutput {
        val key = (id.toLong() shl 32) or (type.toLong() and 0xFFFFFFFFL)
        return outputs.getOrPut(key) {
            val out = inner.track(id, type)
            when (type) {
                C.TRACK_TYPE_VIDEO -> RelayTrackOutput(out) { normalizeVideo(it) }
                C.TRACK_TYPE_AUDIO -> {
                    val rank = audioSeen++
                    RelayTrackOutput(out) { tagAudio(it, rank) }
                }
                else -> out
            }
        }
    }

    override fun endTracks() = inner.endTracks()
    override fun seekMap(seekMap: SeekMap) = inner.seekMap(seekMap)

    /**
     * Rend la piste vidéo acceptable par le muxeur SANS la toucher : seule
     * l'étiquette change, pas un octet du flux.
     *
     * Dolby Vision : les profils 7 et 8 ont une couche de base HEVC standard
     * (HDR10) ; le profil 9 une couche AVC. Le **profil 5** n'a PAS de couche
     * de base lisible ailleurs que sur un décodeur Dolby Vision : le relayer
     * donnerait une image aux couleurs fausses, on refuse en le disant.
     */
    private fun normalizeVideo(f: Format): Format {
        Log.i(
            AetherCastRelay.TAG,
            "source vidéo : ${f.sampleMimeType} ${f.width}x${f.height} " +
                "codecs=${f.codecs} pixels=${f.pixelWidthHeightRatio}"
        )
        var b: Format.Builder? = null
        if (f.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION) {
            val codecs = f.codecs ?: ""
            val profile = codecs.split('.').getOrNull(1)?.toIntOrNull()
            if (profile == 5) {
                onUnsupported(
                    "Ce film est en Dolby Vision profil 5 : sans décodeur Dolby " +
                        "Vision, l'image aurait des couleurs fausses. Il ne peut pas " +
                        "être converti pour le téléviseur."
                )
                return f
            }
            val base = if (codecs.startsWith("dva")) MimeTypes.VIDEO_H264 else MimeTypes.VIDEO_H265
            b = f.buildUpon().setSampleMimeType(base).setCodecs(null)
            Log.i(AetherCastRelay.TAG, "vidéo : Dolby Vision ($codecs) réétiqueté $base pour la recopie")
        }
        if (f.pixelWidthHeightRatio != 1f) {
            b = (b ?: f.buildUpon()).setPixelWidthHeightRatio(1f)
            Log.i(
                AetherCastRelay.TAG,
                "vidéo : rapport de pixels ${f.pixelWidthHeightRatio} forcé à 1 pour la recopie"
            )
        }
        return b?.build() ?: f
    }

    /**
     * Fait gagner la piste [rank] == [audioIndex] au sélecteur du chargeur :
     * « par défaut » et rôle principal pour elle, « alternative » pour les
     * autres — deux critères qu'il consulte AVANT le débit (qu'il force au
     * maximum).
     */
    private fun tagAudio(f: Format, rank: Int): Format {
        Log.i(
            AetherCastRelay.TAG,
            "source audio #$rank : ${f.sampleMimeType} langue=${f.language} " +
                "canaux=${f.channelCount} débit=${f.bitrate} flags=${f.selectionFlags}"
        )
        if (audioIndex < 0) return f
        val wanted = rank == audioIndex
        return if (wanted) {
            f.buildUpon()
                .setSelectionFlags(f.selectionFlags or C.SELECTION_FLAG_DEFAULT)
                .setRoleFlags(C.ROLE_FLAG_MAIN)
                .build()
        } else {
            f.buildUpon()
                .setSelectionFlags(f.selectionFlags and C.SELECTION_FLAG_DEFAULT.inv())
                .setRoleFlags(C.ROLE_FLAG_ALTERNATE)
                .build()
        }
    }
}

@UnstableApi
private class RelayTrackOutput(
    private val inner: TrackOutput,
    private val rewrite: (Format) -> Format,
) : TrackOutput {
    override fun format(format: Format) = inner.format(rewrite(format))

    override fun sampleData(
        input: DataReader,
        length: Int,
        allowEndOfInput: Boolean,
        sampleDataPart: Int,
    ): Int = inner.sampleData(input, length, allowEndOfInput, sampleDataPart)

    override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) =
        inner.sampleData(data, length, sampleDataPart)

    override fun sampleMetadata(
        timeUs: Long,
        flags: Int,
        size: Int,
        offset: Int,
        cryptoData: TrackOutput.CryptoData?,
    ) = inner.sampleMetadata(timeUs, flags, size, offset, cryptoData)
}
