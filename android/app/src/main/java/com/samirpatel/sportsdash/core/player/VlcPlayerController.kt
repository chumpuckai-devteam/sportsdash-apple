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
 * Prefer for MPEG-TS / messy live; soft Exo path can be added later for clean HLS.
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
        ),
    )
    private val mediaPlayer: MediaPlayer = MediaPlayer(libVlc)
    private var attachedLayout: VLCVideoLayout? = null

    val isPlaying: Boolean get() = mediaPlayer.isPlaying

    fun attach(layout: VLCVideoLayout) {
        if (attachedLayout === layout) return
        detach()
        mediaPlayer.attachViews(layout, null, false, false)
        attachedLayout = layout
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
    }

    fun stop() {
        mediaPlayer.stop()
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

    fun release() {
        stop()
        detach()
        mediaPlayer.release()
        libVlc.release()
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
    }
}
