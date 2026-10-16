package com.jackwallner.headachelogger

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.jackwallner.headachelogger.ui.Links
import com.jackwallner.headachelogger.ui.openUrl
import com.jackwallner.headachelogger.ui.theme.HeadacheTheme
import com.jackwallner.headachelogger.ui.theme.PrimaryButton
import com.jackwallner.headachelogger.ui.theme.TextAction
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette

/**
 * Health Connect opens this from its permission screen ("Privacy policy") and,
 * on Android 14 and later, from Settings > Health Connect > App permissions.
 * It says what the one permission is for, in plain words, and nothing else.
 */
class HealthRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            HeadacheTheme {
                val context = LocalContext.current
                Column(
                    Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding()
                        .verticalScroll(rememberScrollState()).padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text("How One Tap Headache Tracker uses Health Connect", style = Type.title3, color = palette.textPrimary)
                    Text(
                        "When you log a headache, the app reads last night's sleep sessions from Health Connect and saves how long you slept and when you woke with that log. Patterns compare your sleep on headache days with other days.",
                        style = Type.body, color = palette.textPrimary,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text("Sleep", style = Type.headline, color = palette.textPrimary)
                        Text("Optional. Sleep duration and wake time for the night before each log.", style = Type.subhead, color = palette.textSecondary)
                    }
                    Text(
                        "This access is read-only and stays on your device. The app never writes to Health Connect, never sells or shares this data, and has no account or server for it. Logging works the same without it.",
                        style = Type.body, color = palette.textSecondary,
                    )
                    PrimaryButton("Privacy Policy", onClick = { context.openUrl(Links.PRIVACY) })
                    TextAction("Close", onClick = { finish() })
                }
            }
        }
    }
}
