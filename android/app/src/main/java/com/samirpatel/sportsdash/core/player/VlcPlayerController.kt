package com.samirpatel.sportsdash.core.player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class PlaybackState { IDLE, OPENING, BUFFERING, PLAYING, PAUSED, ERROR, STOPPED }


/**
 * Hard IPTV engine — libVLC (same family as iOS MobileVLCKit).
 *
 * TextureView so Compose overlays receive taps.
 * Channel switches must **rebind** video surface or friends get audio-only.
 *
 * Volume: libVLC allows 0–200 (100 = unity). We default above 100 so IPTV
 * streams that encode quiet don't feel whisper-quiet vs system media volume.
 */
class VlcPlayerController(context: Context) {
    private val appContext = context.applicationContext
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val libVlc: LibVLC = LibVLC(
        appContext,
        arrayListOf(
            "--network-caching=1500",
            "--live-caching=1500",
            "--http-reconnect",
            "--avcodec-hw=any",
            "--no-drop-late-frames",
            "--no-skip-frames",
            // Prefer Android OpenSL ES path when available
            "--aout=opensles",
        ),
    )
    private val mediaPlayer: MediaPlayer = MediaPlayer(libVlc)
    private var attachedLayout: VLCVideoLayout? = null

    private val _playbackState = MutableStateFlow(PlaybackState.IDLE)
    val playbackState: StateFlow<PlaybackState> = _playbackState.asStateFlow()

    private val eventListener = object : MediaPlayer.EventListener {
        override fun onEvent(event: MediaPlayer.Event) {
            val newState = when (event.type) {
                MediaPlayer.Event.Opening -> PlaybackState.OPENING
                MediaPlayer.Event.Buffering -> PlaybackState.BUFFERING
                MediaPlayer.Event.Playing -> PlaybackState.PLAYING
                MediaPlayer.Event.Paused -> PlaybackState.PAUSED
                MediaPlayer.Event.Stopped, MediaPlayer.Event.EndReached -> PlaybackState.STOPPED
                MediaPlayer.Event.EncounteredError -> PlaybackState.ERROR
                else -> _playbackState.value
            }
            _playbackState.value = newState
        }
    }

    init {
        mediaPlayer.setEventListener(eventListener)
    }

    private var muted: Boolean = false
    /** 0–200; 100 = normal. Default boost for quiet IPTV encodes. */
    private var volumePercent: Int = DEFAULT_VOLUME_PERCENT
    private var currentUrl: String? = null
    /** Pending URL to start once attached (ensures single start owner). */
    private var pendingUrl: String? = null
    /** The URL for which start has been issued (prevents dup starts on attach/play). */
    private var startedUrl: String? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus: Boolean = false


    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            -> {
                // Don't auto-pause live IPTV on transient loss; just note focus
                hasAudioFocus = false
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasAudioFocus = true
                applyVolume()
            }
        }
    }

    val isPlaying: Boolean get() = _playbackState.value == PlaybackState.PLAYING
    val isMuted: Boolean get() = muted

    fun attach(layout: VLCVideoLayout) {
        if (attachedLayout === layout) {
            rebindViews(layout)
            return
        }
        detach()
        rebindViews(layout)
        attachedLayout = layout
        applyVolume()
        // Attach ONLY attaches views and starts pending URL exactly once if not already started.
        // No call to playInternal here; no duplicate starts.
        val p = pendingUrl
        if (p != null && startedUrl != p) {
            startedUrl = p
            pendingUrl = null
            startMedia(p)
        }
    }

    fun detach() {
        try {
            mediaPlayer.detachViews()
        } catch (_: Exception) {
        }
        attachedLayout = null
    }

    /** Play or switch stream. Sets current/pending URL.
     *  If attached, starts once (if not already owner for this URL).
     *  For retry of *same* URL: explicitly resets ownership then starts once.
     *  Stores URL safely until attach without premature start.
     */
    fun play(url: String) {
        if (currentUrl == url) {
            // explicit retry of same URL: reset ownership to allow restart
            startedUrl = null
        }
        currentUrl = url
        pendingUrl = url
        if (attachedLayout != null && startedUrl != url) {
            startedUrl = url
            pendingUrl = null
            startMedia(url)
        }
    }

    /** Core media start (no attach logic, no delayed duplicate play). Called exactly once per owner. */
    private fun startMedia(url: String) {
        currentUrl = url
        val layout = attachedLayout
        requestPlaybackAudioFocus()
        try {
            mediaPlayer.stop()
        } catch (_: Exception) {
        }
        if (layout != null) {
            try {
                mediaPlayer.detachViews()
            } catch (_: Exception) {
            }
        }
        val media = Media(libVlc, Uri.parse(url))
        media.setHWDecoderEnabled(true, false)
        media.addOption(":network-caching=1500")
        media.addOption(":live-caching=1500")
        media.addOption(":http-user-agent=VLC/3.0.21 LibVLC/3.0.21")
        // Slight software gain on decode path when supported
        media.addOption(":volume=${volumePercent.coerceIn(0, 200)}")
        mediaPlayer.media = media
        media.release()
        if (layout != null) {
            rebindViews(layout)
        }
        mediaPlayer.play()
        applyVolume()
        // Re-assert volume after decoder starts (some builds reset to 100). NO play() restart.
        mainHandler.postDelayed({
            if (currentUrl == url) applyVolume()
        }, 120)
        mainHandler.postDelayed({
            if (currentUrl == url) applyVolume()
        }, 500)
    }

    private fun rebindViews(layout: VLCVideoLayout) {
        try {
            mediaPlayer.attachViews(layout, null, false, true)
            mediaPlayer.updateVideoSurfaces()
        } catch (_: Exception) {
            try {
                mediaPlayer.attachViews(layout, null, false, true)
            } catch (_: Exception) {
            }
        }
    }

    fun stop() {
        currentUrl = null
        pendingUrl = null
        startedUrl = null
        try {
            mediaPlayer.stop()
        } catch (_: Exception) {
        }
        abandonAudioFocus()
    }

    fun pause() {
        mediaPlayer.pause()
    }

    fun resume() {
        requestPlaybackAudioFocus()
        mediaPlayer.play()
        applyVolume()
    }

    fun togglePlayPause() {
        if (mediaPlayer.isPlaying) pause() else resume()
    }

    fun setMuted(value: Boolean) {
        muted = value
        applyVolume()
    }

    fun toggleMute() {
        setMuted(!muted)
    }

    /** 0–200; values above 100 boost soft IPTV streams. */
    fun setVolumePercent(percent: Int) {
        volumePercent = percent.coerceIn(0, 200)
        applyVolume()
    }

    private fun applyVolume() {
        val target = when {
            muted -> 0
            else -> volumePercent.coerceIn(0, 200)
        }
        try {
            mediaPlayer.volume = target
        } catch (_: Exception) {
        }
    }

    private fun requestPlaybackAudioFocus() {
        if (hasAudioFocus) return
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(focusChangeListener)
                .setAcceptsDelayedFocusGain(true)
                .build()
            audioFocusRequest = req
            audioManager.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusChangeListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusChangeListener)
        }
        hasAudioFocus = false
    }

    fun release() {
        mainHandler.removeCallbacksAndMessages(null)
        stop()
        detach()
        try {
            mediaPlayer.release()
        } catch (_: Exception) {
        }
        try {
            libVlc.release()
        } catch (_: Exception) {
        }
    }

    companion object {
        /** Unity is 100; 140 is a moderate boost for quiet IPTV without harsh clipping. */
        const val DEFAULT_VOLUME_PERCENT = 140

        /** Pure (no side effects) ownership decision helper for testability. */
        fun shouldStartMedia(pending: String?, started: String?, targetUrl: String, attached: Boolean): Boolean {
            if (targetUrl.isBlank()) return false
            if (started == targetUrl) return false
            return attached || pending == targetUrl
        }
    }
}

fun createVlcVideoLayout(context: Context): VLCVideoLayout {
    return VLCVideoLayout(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        isClickable = false
        isFocusable = false
        isFocusableInTouchMode = false
        importantForAccessibility = android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO
        descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
        setOnTouchListener { _, _ -> false }
    }
}
