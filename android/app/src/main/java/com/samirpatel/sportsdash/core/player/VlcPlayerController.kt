package com.samirpatel.sportsdash.core.player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

/**
 * Hard IPTV engine — libVLC (same family as iOS MobileVLCKit).
 *
 * TextureView so Compose overlays receive taps.
 * Channel switches must **rebind** video surface or friends get audio-only.
 */
class VlcPlayerController(context: Context) {
    private val appContext = context.applicationContext
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
        ),
    )
    private val mediaPlayer: MediaPlayer = MediaPlayer(libVlc)
    private var attachedLayout: VLCVideoLayout? = null
    private var muted: Boolean = false
    private var currentUrl: String? = null

    val isPlaying: Boolean get() = mediaPlayer.isPlaying
    val isMuted: Boolean get() = muted

    fun attach(layout: VLCVideoLayout) {
        if (attachedLayout === layout) {
            // Still force a rebind if views were detached by a prior stop/switch
            rebindViews(layout)
            return
        }
        detach()
        rebindViews(layout)
        attachedLayout = layout
        applyVolume()
        // Resume media if we already have a URL (surface late attach)
        currentUrl?.let { playInternal(it, force = false) }
    }

    fun detach() {
        try {
            mediaPlayer.detachViews()
        } catch (_: Exception) {
        }
        attachedLayout = null
    }

    /** Play or switch stream. Always rebinds TextureView after media change. */
    fun play(url: String) {
        playInternal(url, force = true)
    }

    private fun playInternal(url: String, force: Boolean) {
        if (!force && currentUrl == url && mediaPlayer.isPlaying) return
        currentUrl = url
        val layout = attachedLayout
        try {
            mediaPlayer.stop()
        } catch (_: Exception) {
        }
        // Detach before swapping media so surface doesn't stick on old decoder
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
        mediaPlayer.media = media
        media.release()
        if (layout != null) {
            rebindViews(layout)
        }
        mediaPlayer.play()
        applyVolume()
        // Second rebind after a tick — fixes “audio only” after ticker channel switch
        if (layout != null) {
            mainHandler.postDelayed({
                if (attachedLayout === layout && currentUrl == url) {
                    rebindViews(layout)
                    if (!mediaPlayer.isPlaying) {
                        try {
                            mediaPlayer.play()
                        } catch (_: Exception) {
                        }
                    }
                }
            }, 250)
        }
    }

    private fun rebindViews(layout: VLCVideoLayout) {
        try {
            // textureView=true → Compose chrome stays interactive
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
        mediaPlayer.volume = if (muted) 0 else 100
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

    fun setEventListener(listener: MediaPlayer.EventListener?) {
        mediaPlayer.setEventListener(listener)
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
    }
}
