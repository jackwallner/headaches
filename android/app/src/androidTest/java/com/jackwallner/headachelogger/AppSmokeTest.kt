package com.jackwallner.headachelogger

import android.content.Context
import android.content.Intent
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** First run, one-tap logging and the Headache Pro paid boundary, driven through the debug launch extras. */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class AppSmokeTest {
    @get:Rule val compose = createEmptyComposeRule()
    private var scenario: ActivityScenario<MainActivity>? = null

    private fun launch(vararg extras: Pair<String, Any>) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("resetAll", true)
            .putExtra("appearance", "light")
        extras.forEach { (key, value) ->
            when (value) {
                is Boolean -> intent.putExtra(key, value)
                is String -> intent.putExtra(key, value)
            }
        }
        scenario = ActivityScenario.launch(intent)
    }

    private fun waitForText(text: String) = compose.waitUntilAtLeastOneExists(hasText(text), 15_000)
    private fun waitForTag(tag: String) = compose.waitUntilAtLeastOneExists(hasTestTag(tag), 15_000)

    @After fun tearDown() { scenario?.close() }

    @Test fun firstRunWelcomeMovesToHealthConnect() {
        launch()
        waitForText("One Tap Headache Tracker")
        compose.onNodeWithText("Get Started").performClick()
        waitForText("Health Connect")
        compose.onAllNodes(hasText("Health Connect")).onFirst().assertIsDisplayed()
    }

    @Test fun oneTapLogsAHeadacheOnTheFreeTier() {
        launch("completeSetup" to true, "fakeContext" to true, "noPromos" to true, "tab" to "home")
        waitForTag("logHeadacheButton")
        compose.onNodeWithTag("logHeadacheButton").performClick()
        waitForTag("latestEventCard")
        compose.onNodeWithTag("latestEventCard").assertIsDisplayed()
    }

    @Test fun historyListsSeededEntries() {
        launch("completeSetup" to true, "seedDemo" to true, "noPromos" to true, "tab" to "history")
        waitForTag("historyView")
        waitForTag("historyEventRow")
    }

    @Test fun freePatternsShowLockedTeaserAndOpenThePaywall() {
        launch("completeSetup" to true, "seedDemo" to true, "previewStore" to true, "noPromos" to true, "tab" to "patterns")
        waitForText("See what triggers your headaches")
        compose.onNodeWithTag("patternsSeePlans").performClick()
        waitForTag("paywall")
        compose.onNodeWithText("Know before the headache hits").assertIsDisplayed()
        compose.onNodeWithTag("plan_yearly").assertIsDisplayed()
    }

    @Test fun proPatternsDropTheTeaser() {
        launch("completeSetup" to true, "seedDemo" to true, "demoPro" to true, "fakeContext" to true, "noPromos" to true, "tab" to "patterns")
        waitForTag("riskCard")
        assertEquals(0, compose.onAllNodes(hasText("See what triggers your headaches")).fetchSemanticsNodes().size)
    }

    @Test fun paywallCtaFollowsTheSelectedPlan() {
        launch("completeSetup" to true, "previewStore" to true, "noPromos" to true, "sheet" to "paywall")
        waitForTag("paywall")
        waitForText("Start My Free Trial")
        compose.onNodeWithTag("plan_lifetime").performClick()
        waitForText("Unlock Lifetime")
        compose.onNodeWithText("One-time payment. No subscription.").assertIsDisplayed()
    }

    @Test fun trialSheetLeadsWithTheTrialLength() {
        launch("completeSetup" to true, "previewStore" to true, "noPromos" to true, "sheet" to "trial")
        waitForText("7 days of Pro, free.")
        compose.onNodeWithTag("trialCta").assertIsDisplayed()
        compose.onNodeWithText("See all plans").performClick()
        waitForTag("paywall")
    }

    @Test fun settingsKeepsTheMedicalDisclaimerAndRestore() {
        launch("completeSetup" to true, "noPromos" to true, "tab" to "settings")
        waitForText("Restore Purchases")
        compose.onNodeWithText("Restore Purchases").assertIsDisplayed()
        compose.onAllNodes(hasText("It does not diagnose, treat, or prevent any condition.", substring = true)).onFirst().performScrollTo().assertIsDisplayed()
    }
}
