package com.samirpatel.sportsdash.ui.tv

import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.samirpatel.sportsdash.ui.theme.Gold

/**
 * Android TV / D-pad gold focus ring + slight scale.
 *
 * Does **not** call [focusable] by default — pair with `clickable` /
 * `combinedClickable` / Material buttons so there is a single focus target.
 * Use [makeFocusable]=true only for bare containers that must accept focus.
 *
 * Uses [FocusState.hasFocus] so a parent ring lights when a child is focused
 * (optional nesting) and [isFocused] for the node itself.
 */
fun Modifier.tvFocusRing(
    enabled: Boolean = true,
    shape: Shape = RoundedCornerShape(12.dp),
    makeFocusable: Boolean = false,
    scaleFocused: Float = 1.04f,
): Modifier = if (!enabled) {
    this
} else {
    composed {
        var focused by remember { mutableStateOf(false) }
        this
            .onFocusChanged { focused = it.isFocused || it.hasFocus }
            .then(if (makeFocusable) Modifier.focusable() else Modifier)
            .scale(if (focused) scaleFocused else 1f)
            .border(
                width = if (focused) 2.5.dp else 0.dp,
                color = if (focused) Gold else Color.Transparent,
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
