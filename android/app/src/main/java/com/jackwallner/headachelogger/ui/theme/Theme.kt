package com.jackwallner.headachelogger.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** iOS grouped-list system colors in both appearances; the brand coral is fixed. */
class HeadachePalette(
    val background: Color,
    val card: Color,
    val cardRaised: Color,
    val separator: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val isDark: Boolean,
)

val LightPalette = HeadachePalette(
    background = Color(0xFFF2F2F7),
    card = Color(0xFFFFFFFF),
    cardRaised = Color(0xFFF2F2F7),
    separator = Color(0x4A3C3C43),
    textPrimary = Color(0xFF000000),
    textSecondary = Color(0x993C3C43),
    textTertiary = Color(0x4D3C3C43),
    isDark = false,
)

val DarkPalette = HeadachePalette(
    background = Color(0xFF000000),
    card = Color(0xFF1C1C1E),
    cardRaised = Color(0xFF2C2C2E),
    separator = Color(0x99545458),
    textPrimary = Color(0xFFFFFFFF),
    textSecondary = Color(0x99EBEBF5),
    textTertiary = Color(0x4DEBEBF5),
    isDark = true,
)

val LocalPalette = staticCompositionLocalOf { LightPalette }

object Brand {
    val primary = Color(0xFFF2405C)
    val secondary = Color(0xFFDB296E)
    val gradient: Brush get() = Brush.linearGradient(listOf(primary, secondary))
}

/** iOS system tints the screens use for chips, badges and charts. */
object Tint {
    val green = Color(0xFF34C759)
    val orange = Color(0xFFFF9500)
    val yellow = Color(0xFFFFCC00)
    val red = Color(0xFFFF3B30)
    val blue = Color(0xFF007AFF)
    val indigo = Color(0xFF5856D6)
    val teal = Color(0xFF30B0C7)
    val mint = Color(0xFF00C7BE)
    val purple = Color(0xFFAF52DE)
    val pink = Color(0xFFFF2D55)
    val cyan = Color(0xFF32ADE6)
    val brown = Color(0xFFA2845E)
    val gray = Color(0xFF8E8E93)
}

object Geo {
    val gutter = 20.dp
    val cardRadius = 22.dp
}

object Type {
    fun of(size: TextUnit, weight: FontWeight = FontWeight.Normal) = TextStyle(fontWeight = weight, fontSize = size, lineHeight = size * 1.3f)

    val largeTitle = of(32.sp, FontWeight.Bold)
    val title = of(28.sp, FontWeight.Bold)
    val title2 = of(22.sp, FontWeight.Bold)
    val title3 = of(20.sp, FontWeight.SemiBold)
    val headline = of(17.sp, FontWeight.SemiBold)
    val body = of(17.sp)
    val callout = of(16.sp)
    val subhead = of(15.sp)
    val subheadBold = of(15.sp, FontWeight.SemiBold)
    val footnote = of(13.sp)
    val caption = of(12.sp)
    val captionBold = of(12.sp, FontWeight.SemiBold)
    val caption2 = of(11.sp)
}

@Composable
fun HeadacheTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val palette = if (dark) DarkPalette else LightPalette
    val scheme = if (dark) {
        darkColorScheme(
            primary = Brand.primary, onPrimary = Color.White, background = palette.background, surface = palette.card,
            onSurface = palette.textPrimary, onBackground = palette.textPrimary, surfaceVariant = palette.cardRaised,
            onSurfaceVariant = palette.textSecondary, outline = palette.separator, surfaceContainerHigh = palette.card,
            surfaceContainer = palette.card, surfaceContainerLow = palette.card, surfaceContainerHighest = palette.cardRaised,
        )
    } else {
        lightColorScheme(
            primary = Brand.primary, onPrimary = Color.White, background = palette.background, surface = palette.card,
            onSurface = palette.textPrimary, onBackground = palette.textPrimary, surfaceVariant = palette.cardRaised,
            onSurfaceVariant = palette.textSecondary, outline = palette.separator, surfaceContainerHigh = palette.card,
            surfaceContainer = palette.card, surfaceContainerLow = palette.card, surfaceContainerHighest = palette.cardRaised,
        )
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

val palette: HeadachePalette @Composable get() = LocalPalette.current
