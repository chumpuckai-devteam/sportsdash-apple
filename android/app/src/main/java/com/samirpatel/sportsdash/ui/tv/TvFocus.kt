package com.samirpatel.sportsdash.ui.tv

import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.LedGlow
import com.samirpatel.sportsdash.ui.theme.TvFocusScale

/**
 * Android TV / D-pad gold focus ring + slight scale (006 §1).
 *
 * 3dp gold border + a second 0.35-alpha ring (Modifier.shadow is not glow).
 * Cards/rows default to [RectangleShape] and [TvFocusScale] 1.045.
 */
fun Modifier.tvFocusRing(
    enabled: Boolean = true,
    shape: Shape = RectangleShape,
    makeFocusable: Boolean = false,
    scaleFocused: Float = TvFocusScale,
): Modifier = if (!enabled) {
    this
} else {
    composed {
        var focused by remember { mutableStateOf(false) }
        this
            .onFocusChanged { focused = it.isFocused || it.hasFocus }
            .then(if (makeFocusable) Modifier.focusable() else Modifier)
            .scale(if (focused) scaleFocused else 1f)
            .drawBehind {
                if (focused) {
                    drawRect(LedGlow.copy(alpha = 0.35f))
                }
            }
            .border(
                width = if (focused) 3.dp else 0.dp,
                color = if (focused) Gold else Color.Transparent,
                shape = shape,
            )
            .border(
                width = if (focused) 6.dp else 0.dp,
                color = if (focused) Gold.copy(alpha = 0.35f) else Color.Transparent,
                shape = shape,
            )
    }
}

/** Circle controls (player transport, etc.). */
fun Modifier.tvFocusCircle(
    enabled: Boolean = true,
    makeFocusable: Boolean = false,
): Modifier = tvFocusRing(
    enabled = enabled,
    shape = CircleShape,
    makeFocusable = makeFocusable,
    scaleFocused = 1.08f,
)

/** Group D-pad traversal for a horizontal chrome row (filters, guide bar). */
fun Modifier.tvFocusGroup(enabled: Boolean = true): Modifier =
    if (enabled) this.focusGroup() else this
