package com.jackwallner.headachelogger.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Air
import androidx.compose.material.icons.filled.ArrowCircleDown
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Eco
import androidx.compose.material.icons.filled.Hearing
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Insights
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Masks
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.NightsStay
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Thermostat
import androidx.compose.material.icons.filled.Thunderstorm
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.WbTwilight
import androidx.compose.material.icons.filled.AcUnit
import androidx.compose.material.icons.filled.Opacity
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.ui.graphics.vector.ImageVector

/** The SF Symbol names the shared engines emit, drawn with the closest Material icon. */
object Symbols {
    fun of(name: String): ImageVector = when (name) {
        "bed.double.fill" -> Icons.Filled.Hotel
        "cup.and.saucer.fill" -> Icons.Filled.Coffee
        "sunrise.fill" -> Icons.Filled.WbTwilight
        "sunset.fill" -> Icons.Filled.WbTwilight
        "sun.max.fill" -> Icons.Filled.WbSunny
        "moon.fill" -> Icons.Filled.Bedtime
        "moon.stars.fill" -> Icons.Filled.NightsStay
        "wind" -> Icons.Filled.Air
        "waveform.path.ecg" -> Icons.Filled.MonitorHeart
        "lungs.fill" -> Icons.Filled.Air
        "link.circle.fill" -> Icons.Filled.Link
        "leaf.fill" -> Icons.Filled.Eco
        "humidity.fill" -> Icons.Filled.Opacity
        "heart.text.square.fill" -> Icons.Filled.Favorite
        "figure.walk" -> Icons.Filled.DirectionsWalk
        "figure.run" -> Icons.Filled.DirectionsRun
        "facemask.fill" -> Icons.Filled.Masks
        "exclamationmark.triangle.fill" -> Icons.Filled.Warning
        "ear.fill" -> Icons.Filled.Hearing
        "drop.fill" -> Icons.Filled.WaterDrop
        "cloud.rain.fill" -> Icons.Filled.Thunderstorm
        "calendar" -> Icons.Filled.CalendarMonth
        "barometer" -> Icons.Filled.Speed
        "aqi.low", "aqi.medium", "aqi.high" -> Icons.Filled.Masks
        "thermometer.sun.fill" -> Icons.Filled.Thermostat
        "thermometer.snowflake" -> Icons.Filled.AcUnit
        "minus.circle.fill" -> Icons.Filled.RemoveCircle
        "clock.fill" -> Icons.Filled.AccessTime
        "arrow.up.right.circle.fill" -> Icons.Filled.ArrowCircleUp
        "arrow.down.right.circle.fill" -> Icons.Filled.ArrowCircleDown
        "chart.bar.xaxis" -> Icons.Filled.BarChart
        "cloud" -> Icons.Filled.Cloud
        else -> Icons.Filled.Insights
    }
}
