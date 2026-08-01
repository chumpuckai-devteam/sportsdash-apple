package com.samirpatel.sportsdash.core.player

import android.content.Context
import android.net.Uri
import android.view.ViewGroup
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

/**
 * Hard IPTV engine — libVLC (same family as iOS MobileVLCKit).
 *
 * Uses **TextureView** (not SurfaceView) so Compose overlays (back, pause, ticker)
 * stay on top and receive taps. SurfaceView punches above the window and ate the X.
 */
class VlcPlayerController(context: Context) {
    private val appContext = context.applicationContext
    private val libVlc: LibVLC = LibVLC(
        appContext,
        arrayListOf(
            "--network-caching=1500",
            "--live-caching=1500",
            "--http-reconnect",
            "--avcodec-hw=any",
            "--no-drop-late-frames",
            "--no-skip-frames",
        ),
    )
    private val mediaPlayer: MediaPlayer = MediaPlayer(libVlc)
    private var attachedLayout: VLCVideoLayout? = null
    private var muted: Boolean = false

    val isPlaying: Boolean get() = mediaPlayer.isPlaying
    val isMuted: Boolean get() = muted

    fun attach(layout: VLCVideoLayout) {
        if (attachedLayout === layout) return
        detach()
        // subtitlesSurface=false, textureView=true → Compose chrome can receive clicks
        mediaPlayer.attachViews(layout, null, false, true)
        attachedLayout = layout
        applyVolume()
    }

    fun detach() {
        try {
            mediaPlayer.detachViews()
        } catch (_: Exception) {
        }
        attachedLayout = null
    }

    fun play(url: String) {
        val media = Media(libVlc, Uri.parse(url))
        media.setHWDecoderEnabled(true, false)
        media.addOption(":network-caching=1500")
        media.addOption(":live-caching=1500")
        media.addOption(":http-user-agent=VLC/3.0.21 LibVLC/3.0.21")
        mediaPlayer.media = media
        media.release()
        mediaPlayer.play()
        applyVolume()
    }

    fun stop() {
        try {
            mediaPlayer.stop()
        } catch (_: Exception) {
        }
    }

    fun pause() {
        mediaPlayer.pause()
    }

    fun resume() {
        mediaPlayer.play()
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

    private fun applyVolume() {
        // libVLC volume 0–100
        mediaPlayer.volume = if (muted) 0 else 100
    }

    fun release() {
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

    fun setEventListener(listener: MediaPlayer.EventListener?) {
        mediaPlayer.setEventListener(listener)
    }
}

/** Factory helper for Compose AndroidView. */
fun createVlcVideoLayout(context: Context): VLCVideoLayout {
    return VLCVideoLayout(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        // Don't let the video layout steal focus from Compose buttons
        isClickable = false
        isFocusable = false
    }
}
