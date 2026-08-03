package com.samirpatel.sportsdash.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.samirpatel.sportsdash.core.ratings.MovieRating
import com.samirpatel.sportsdash.ui.theme.Gold
import com.samirpatel.sportsdash.ui.theme.Muted

/** Compact critic/audience chips — iOS MovieRatingBadge parity (no RT trademarks). */
@Composable
fun MovieRatingChips(
    rating: MovieRating?,
    loading: Boolean,
    compact: Boolean = true,
    modifier: Modifier = Modifier,
) {
    when {
        rating != null && rating.hasAnyScore -> {
            Row(
                modifier = modifier,
                horizontalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                rating.criticLabel?.let { label ->
                    ScoreChip(
                        iconTint = Color(0xFFF25959),
                        label = if (compact) label else "Critic $label",
                        compact = compact,
                    )
                }
                rating.audienceLabel?.let { label ->
                    ScoreChip(
                        iconTint = Gold,
                        label = if (compact) label else "Audience $label",
                        compact = compact,
                        useStar = false,
                    )
                }
            }
        }
        loading -> {
            Row(
                modifier = modifier.padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(if (compact) 10.dp else 12.dp),
                    strokeWidth = 1.5.dp,
                    color = Gold,
                )
                if (!compact) {
                    Text("Ratings…", color = Muted, fontSize = 10.sp)
                }
            }
        }
    }
}

@Composable
private fun ScoreChip(
    iconTint: Color,
    label: String,
    compact: Boolean,
    useStar: Boolean = true,
) {
    Row(
        modifier = Modifier
            .border(1.dp, iconTint.copy(alpha = 0.7f), RoundedCornerShape(50))
            .padding(horizontal = if (compact) 6.dp else 8.dp, vertical = if (compact) 3.dp else 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Star,
            contentDescription = null,
            tint = iconTint,
            modifier = Modifier.size(if (compact) 10.dp else 12.dp),
        )
        Text(
            text = label,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = if (compact) 10.sp else 11.sp,
        )
    }
}

@Composable
fun MovieRatingRow(
    title: String?,
    rating: MovieRating?,
    loading: Boolean,
    onRequest: () -> Unit,
    compact: Boolean = true,
    modifier: Modifier = Modifier,
) {
    if (title.isNullOrBlank()) return
    LaunchedEffect(title) { onRequest() }
    MovieRatingChips(rating = rating, loading = loading, compact = compact, modifier = modifier)
}
