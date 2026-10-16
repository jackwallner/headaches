package com.jackwallner.headachelogger.widget

import android.content.Context
import android.content.Intent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import com.jackwallner.headachelogger.HeadacheApplication
import com.jackwallner.headachelogger.MainActivity
import com.jackwallner.headachelogger.R
import com.jackwallner.headachelogger.data.HeadacheSettings
import com.jackwallner.headachelogger.data.SharedPreferencesStore
import com.jackwallner.headachelogger.data.WidgetQuickLog
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.EnvironmentCaptureResult
import com.jackwallner.headachelogger.model.HealthCaptureResult
import com.jackwallner.headachelogger.model.HeadacheEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Port of `LogHeadacheWidget`: one tap logs, "Logged" shows for ten seconds, context fills in when the app opens. */
class HeadacheWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val lastLogged = SharedPreferencesStore(context).getLong(com.jackwallner.headachelogger.data.StorageKey.WIDGET_LAST_LOGGED_AT)
        val confirming = lastLogged > 0 && System.currentTimeMillis() < lastLogged + CONFIRM_WINDOW_MS
        provideContent { Content(confirming) }
    }

    @androidx.compose.runtime.Composable
    private fun Content(confirming: Boolean) {
        val white = ColorProvider(Color.White, Color.White)
        Column(
            GlanceModifier.fillMaxSize().background(ColorProvider(BACKGROUND, BACKGROUND)).padding(8.dp)
                .clickable(actionRunCallback<LogHeadacheAction>()),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Image(
                ImageProvider(if (confirming) R.drawable.ic_widget_check else R.drawable.ic_widget_head),
                contentDescription = null,
                modifier = GlanceModifier.size(32.dp),
            )
            Spacer(GlanceModifier.height(8.dp))
            Text(
                if (confirming) "Logged" else "Log headache",
                style = TextStyle(color = white, fontSize = 17.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center),
            )
        }
    }

    companion object {
        const val CONFIRM_WINDOW_MS = 10_000L
        private val BACKGROUND = Color(0xFF591F29)
    }
}

class HeadacheWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HeadacheWidget()
}

/** Port of `LogHeadacheIntent`: saves a quick log with the "open the app" sentinels. */
class LogHeadacheAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val app = context.applicationContext as? HeadacheApplication ?: return
        val settings: HeadacheSettings = app.graph.settings
        if (!settings.hasCompletedOnboarding) {
            context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        }
        withContext(Dispatchers.Main) {
            val event = HeadacheEvent()
            event.apply(HealthCaptureResult(CaptureSourceStatus.UNAVAILABLE, WidgetQuickLog.HEALTH_MESSAGE_PENDING, null))
            event.apply(EnvironmentCaptureResult(CaptureSourceStatus.UNAVAILABLE, WidgetQuickLog.ENVIRONMENT_MESSAGE_PENDING, null))
            event.finalizeCapture()
            app.graph.events.insert(event)
            settings.widgetLastLoggedAt = System.currentTimeMillis()
        }
        HeadacheWidget().updateAll(context)
        app.graph.scope.launch {
            delay(HeadacheWidget.CONFIRM_WINDOW_MS + 250)
            runCatching { HeadacheWidget().updateAll(context) }
        }
    }
}
