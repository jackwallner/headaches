package com.jackwallner.headachelogger.ui.theme

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

fun Modifier.tappable(label: String? = null, role: Role = Role.Button, enabled: Boolean = true, onClick: () -> Unit): Modifier =
    this.clickable(
        interactionSource = MutableInteractionSource(),
        indication = androidx.compose.material3.ripple(),
        enabled = enabled,
        role = role,
        onClick = onClick,
    ).let { if (label != null) it.semantics { contentDescription = label } else it }

/** `secondarySystemGroupedBackground` in a continuous rounded rectangle. */
@Composable
fun Card(
    modifier: Modifier = Modifier,
    radius: Dp = Geo.cardRadius,
    padding: Dp = 18.dp,
    background: Color? = null,
    border: Color? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(background ?: palette.card)
            .let { if (border != null) it.border(1.dp, border, shape) else it }
            .padding(padding),
        content = content,
    )
}

/** Inline top bar: centered title like `.navigationBarTitleDisplayMode(.inline)`, optional leading and trailing text actions. */
@Composable
fun TopBar(
    title: String,
    leading: Pair<String, () -> Unit>? = null,
    trailing: Pair<String, () -> Unit>? = null,
    trailingEnabled: Boolean = true,
    trailingBold: Boolean = false,
    insets: Boolean = true,
) {
    Box(
        Modifier.fillMaxWidth().let { if (insets) it.windowInsetsPadding(WindowInsets.statusBars) else it }.height(52.dp).padding(horizontal = 8.dp),
    ) {
        Text(
            title, style = Type.headline, color = palette.textPrimary, maxLines = 1,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 84.dp),
            textAlign = TextAlign.Center,
        )
        leading?.let { (label, action) ->
            Text(
                label, style = Type.body, color = Brand.primary,
                modifier = Modifier.align(Alignment.CenterStart).clip(RoundedCornerShape(8.dp)).tappable(label, onClick = action).padding(horizontal = 8.dp, vertical = 10.dp),
            )
        }
        trailing?.let { (label, action) ->
            Text(
                label, style = if (trailingBold) Type.headline else Type.body,
                color = if (trailingEnabled) Brand.primary else palette.textTertiary,
                modifier = Modifier.align(Alignment.CenterEnd).clip(RoundedCornerShape(8.dp))
                    .tappable(label, enabled = trailingEnabled, onClick = action).padding(horizontal = 8.dp, vertical = 10.dp),
            )
        }
    }
}

/** A large title header for tab roots, like iOS `.navigationTitle` in large mode. */
@Composable
fun LargeTitle(title: String, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(
        modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = Geo.gutter, end = 12.dp, top = 12.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = Type.largeTitle, color = palette.textPrimary, modifier = Modifier.weight(1f), maxLines = 1)
        trailing()
    }
}

/** The brand-gradient capsule button used for every purchase and primary action. */
@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    brush: Brush = Brand.gradient,
    shape: androidx.compose.ui.graphics.Shape = RoundedCornerShape(14.dp),
) {
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 50.dp)
            .clip(shape)
            .background(brush)
            .alpha(if (enabled || loading) 1f else 0.5f)
            .tappable(text, enabled = enabled && !loading, onClick = onClick)
            .padding(vertical = 14.dp, horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (loading) {
            CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.5.dp)
        } else {
            Text(text, style = Type.headline, color = Color.White, textAlign = TextAlign.Center)
        }
    }
}

/** A plain text button, centered: "Not now", "Restore Purchases". */
@Composable
fun TextAction(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = palette.textSecondary, style: androidx.compose.ui.text.TextStyle = Type.subheadBold, enabled: Boolean = true) {
    Box(
        modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).tappable(text, enabled = enabled, onClick = onClick).heightIn(min = 44.dp).padding(vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = style, color = if (enabled) color else palette.textTertiary, textAlign = TextAlign.Center) }
}

/** A tinted capsule label. */
@Composable
fun StatusBadge(label: String, tint: Color, modifier: Modifier = Modifier) {
    Text(
        label, style = Type.captionBold, color = tint, maxLines = 1,
        modifier = modifier.clip(CircleShape).background(tint.copy(alpha = 0.12f)).padding(horizontal = 10.dp, vertical = 6.dp),
    )
}

/** Header and footer around a grouped list, like an iOS `Form` section. */
@Composable
fun FormSection(header: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        if (header != null) {
            Text(header.uppercase(), style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(palette.card), content = content)
        if (footer != null) {
            Text(footer, style = Type.footnote, color = palette.textSecondary, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
        }
    }
}

@Composable
fun RowDivider() {
    Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(0.5.dp).background(palette.separator))
}

@Composable
fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, subtitle: String? = null, enabled: Boolean = true, tag: String? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.body, color = if (enabled) palette.textPrimary else palette.textTertiary)
            if (subtitle != null) Text(subtitle, style = Type.footnote, color = palette.textSecondary)
        }
        Spacer(Modifier.width(12.dp))
        Switch(
            checked = checked, onCheckedChange = onChange, enabled = enabled,
            modifier = Modifier.semantics { contentDescription = title }.let { if (tag != null) it.testTag(tag) else it },
            colors = SwitchDefaults.colors(
                checkedTrackColor = Tint.green, checkedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent,
                uncheckedTrackColor = palette.separator, uncheckedThumbColor = Color.White,
            ),
        )
    }
}

fun Modifier.testTagCompat(tag: String): Modifier = this.testTag(tag)

@Composable
fun NavRow(
    title: String,
    onClick: () -> Unit,
    subtitle: String? = null,
    trailing: String? = null,
    icon: ImageVector? = null,
    iconTint: Color = Brand.primary,
    titleColor: Color? = null,
    chevron: Boolean = true,
    locked: Boolean = false,
) {
    Row(
        Modifier.fillMaxWidth().tappable(title, onClick = onClick).heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = iconTint, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(12.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.body, color = titleColor ?: palette.textPrimary)
            if (subtitle != null) Text(subtitle, style = Type.footnote, color = palette.textSecondary)
        }
        if (locked) Icon(Icons.Filled.Lock, "Pro", tint = Brand.primary, modifier = Modifier.size(14.dp).padding(end = 2.dp))
        if (trailing != null) Text(trailing, style = Type.body, color = palette.textSecondary, maxLines = 1)
        if (chevron) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textTertiary)
    }
}

/** A text-only row inside a form section. */
@Composable
fun ValueRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
        Text(value, style = Type.body, color = palette.textSecondary)
    }
}

@Composable
fun SegmentedControl(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(9.dp)).background(palette.separator.copy(alpha = 0.25f)).padding(2.dp)) {
        options.forEachIndexed { index, title ->
            val isSelected = index == selected
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(7.dp))
                    .background(if (isSelected) palette.card else Color.Transparent)
                    .tappable(title, Role.Tab) { onSelect(index) }
                    .heightIn(min = 34.dp).padding(vertical = 7.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(title, style = if (isSelected) Type.captionBold.copy(fontSize = Type.footnote.fontSize) else Type.footnote, color = palette.textPrimary, maxLines = 1)
            }
        }
    }
}

/** iOS `DisclosureGroup`: a tappable label that reveals its content. */
@Composable
fun Disclosure(label: String, modifier: Modifier = Modifier, initiallyOpen: Boolean = false, labelColor: Color = palette.textSecondary, content: @Composable ColumnScope.() -> Unit) {
    var open by remember { mutableStateOf(initiallyOpen) }
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).tappable(label) { open = !open }.heightIn(min = 36.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = Type.footnote, color = labelColor, modifier = Modifier.weight(1f))
            Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = palette.textTertiary, modifier = Modifier.size(20.dp))
        }
        AnimatedVisibility(open) { Column(content = content) }
    }
}

/** A row of small icon + text. */
@Composable
fun IconLine(icon: ImageVector, text: String, tint: Color = palette.textSecondary, style: androidx.compose.ui.text.TextStyle = Type.caption, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(14.dp))
        Text(text, style = style, color = tint, maxLines = 1)
    }
}

val SolidBrand: Brush = SolidColor(Brand.primary)
