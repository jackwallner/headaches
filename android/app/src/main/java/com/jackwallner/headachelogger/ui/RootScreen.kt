package com.jackwallner.headachelogger.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.compositionLocalOf
import com.jackwallner.headachelogger.AppGraph

val LocalGraph = staticCompositionLocalOf<AppGraph> { error("No AppGraph provided") }
val LocalForeground = compositionLocalOf { 0 }

@Composable
fun RootScreen(graph: AppGraph) {
}
