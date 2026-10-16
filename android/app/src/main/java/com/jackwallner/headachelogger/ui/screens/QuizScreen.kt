package com.jackwallner.headachelogger.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.headachelogger.AppGraph
import com.jackwallner.headachelogger.data.QuizStore
import com.jackwallner.headachelogger.model.QuizQuestions
import com.jackwallner.headachelogger.ui.theme.Brand
import com.jackwallner.headachelogger.ui.theme.PrimaryButton
import com.jackwallner.headachelogger.ui.theme.TextAction
import com.jackwallner.headachelogger.ui.theme.TopBar
import com.jackwallner.headachelogger.ui.theme.Type
import com.jackwallner.headachelogger.ui.theme.palette
import com.jackwallner.headachelogger.ui.theme.tappable

/** Port of `HeadacheQuizView`: six questions, a skip confirmation and a thank-you step. */
@Composable
fun QuizScreen(graph: AppGraph, onClose: () -> Unit) {
    val quiz = graph.quiz
    var step by remember { mutableIntStateOf(0) }
    var skipping by remember { mutableStateOf(false) }
    val total = QuizQuestions.all.size
    fun complete() {
        quiz.setCompleted(true)
        onClose()
    }
    QuizFrame(title = null) {
        when {
            skipping -> {
                MessageStep(
                    Icons.AutoMirrored.Filled.HelpOutline, palette.textSecondary, "Skip the Quiz?",
                    "Answering these helps Patterns highlight the triggers most relevant to your headaches. You can always come back later from Settings.",
                )
                PrimaryButton("Go Back to Questions", { skipping = false }, brush = SolidColor(Brand.primary))
                TextAction("Skip for Now", ::complete, modifier = Modifier.fillMaxWidth(), style = Type.subhead)
            }
            step < total -> {
                QuestionStep(quiz, step)
                PrimaryButton(
                    if (step < total - 1) "Next" else "Finish",
                    { if (step < total - 1) step += 1 else complete() },
                    brush = SolidColor(Brand.primary), modifier = Modifier.testTag("quizNext"),
                )
                TextAction("Skip All Questions", { skipping = true }, modifier = Modifier.fillMaxWidth(), style = Type.subhead)
            }
            else -> Unit
        }
    }
}

/** Port of `HeadacheQuizRetakeView`, opened from Settings with the saved answers selected. */
@Composable
fun QuizRetakeScreen(graph: AppGraph, onClose: () -> Unit) {
    val quiz = graph.quiz
    var step by remember { mutableIntStateOf(0) }
    val total = QuizQuestions.all.size
    QuizFrame(title = "Pattern Quiz", onBack = onClose) {
        if (step < total) {
            QuestionStep(quiz, step)
            PrimaryButton(
                if (step < total - 1) "Next" else "Done",
                {
                    if (step < total - 1) step += 1
                    else {
                        quiz.setCompleted(true)
                        onClose()
                    }
                },
                brush = SolidColor(Brand.primary), modifier = Modifier.testTag("quizNext"),
            )
        } else {
            MessageStep(Icons.Filled.CheckCircle, Brand.primary, "Answers Updated", "Thanks! Your answers help us improve future versions of Patterns.")
            PrimaryButton("Done", onClose, brush = SolidColor(Brand.primary))
        }
    }
}

@Composable
private fun QuizFrame(title: String?, onBack: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().background(palette.background).windowInsetsPadding(WindowInsets.navigationBars).testTag("quiz")) {
        if (title != null && onBack != null) TopBar(title, leading = "Back" to onBack)
        else Spacer(Modifier.windowInsetsPadding(WindowInsets.statusBars))
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            content = content,
        )
    }
}

@Composable
private fun ColumnScope.QuestionStep(quiz: QuizStore, step: Int) {
    val q = QuizQuestions.all[step]
    val total = QuizQuestions.all.size
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Step ${step + 1} of $total", style = Type.subhead, color = palette.textSecondary)
        LinearProgressIndicator(
            progress = { (step + 1f) / total }, color = Brand.primary, trackColor = palette.separator.copy(alpha = 0.3f),
            strokeCap = StrokeCap.Round, gapSize = 0.dp, drawStopIndicator = {}, modifier = Modifier.fillMaxWidth(),
        )
    }
    Text(q.question, style = Type.title3.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Bold), color = palette.textPrimary, modifier = Modifier.padding(top = 8.dp))
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        q.options.forEach { option ->
            val selected = quiz.answer(q.id) == option
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                    .background(if (selected) Brand.primary.copy(alpha = 0.08f) else palette.card)
                    .tappable(option, role = Role.RadioButton) { quiz.saveAnswer(q.id, option) }
                    .heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(option, style = Type.body, color = palette.textPrimary, modifier = Modifier.weight(1f))
                if (selected) Icon(Icons.Filled.CheckCircle, null, tint = Brand.primary, modifier = Modifier.size(22.dp))
            }
        }
    }
    Spacer(Modifier.weight(1f))
}

@Composable
private fun ColumnScope.MessageStep(icon: ImageVector, tint: androidx.compose.ui.graphics.Color, title: String, body: String) {
    Spacer(Modifier.weight(1f))
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(52.dp))
        Text(title, style = Type.title2, color = palette.textPrimary, textAlign = TextAlign.Center)
        Text(body, style = Type.body, color = palette.textSecondary, textAlign = TextAlign.Center)
    }
    Spacer(Modifier.weight(1f))
}
