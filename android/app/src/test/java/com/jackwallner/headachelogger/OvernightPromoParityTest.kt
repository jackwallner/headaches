package com.jackwallner.headachelogger

import com.jackwallner.headachelogger.billing.ConversionCopy
import com.jackwallner.headachelogger.capture.CaptureCoordinator
import com.jackwallner.headachelogger.capture.DeviceStateReader
import com.jackwallner.headachelogger.capture.EnvironmentSource
import com.jackwallner.headachelogger.capture.HealthAccess
import com.jackwallner.headachelogger.capture.HealthSource
import com.jackwallner.headachelogger.data.EventStore
import com.jackwallner.headachelogger.data.InMemoryStore
import com.jackwallner.headachelogger.data.MemoryTextFile
import com.jackwallner.headachelogger.data.ReviewPromptTracker
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.EnvironmentCaptureResult
import com.jackwallner.headachelogger.model.HealthCaptureResult
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.InsightsEngine
import com.jackwallner.headachelogger.model.PartOfDay
import com.jackwallner.headachelogger.model.PersonalSignalProfile
import com.jackwallner.headachelogger.model.ProMilestone
import com.jackwallner.headachelogger.model.SleepIntervalMerge
import com.jackwallner.headachelogger.model.mostCommon
import com.jackwallner.headachelogger.ui.screens.signalStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Ports of the milestone, review gate, retry, copy and tie-break guards in iOS `OvernightFindingsTests`. */
class OvernightPromoParityTest {
    @Before fun locale() = Locale.setDefault(Locale.US)

    private fun milestone(count: Int, isPro: Boolean = false, elsewhere: Boolean = false, s3: Boolean = false, s5: Boolean = false, s10: Boolean = false) =
        ProMilestone.active(count, isPro, elsewhere, s3, s5, s10)

    // F1

    @Test fun milestoneCardStaysAfterItClaimsTheSession() {
        // The card's own claim is not "claimed elsewhere", so it stays on screen.
        assertEquals(ProMilestone.TEN, milestone(10))
        // A trial offer that already fired still owns the session.
        assertNull(milestone(10, elsewhere = true))
        assertNull(milestone(10, isPro = true))
    }

    @Test fun retiredTopMilestoneDoesNotBringBackALowerOne() {
        assertNull(milestone(12, s10 = true))
        assertEquals(ProMilestone.FIVE, milestone(6, s3 = true))
        assertNull(milestone(2))
    }

    @Test fun milestoneCopyIsDescriptive() {
        ProMilestone.entries.forEach { assertFalse(it.detail, it.detail.contains("trigger", ignoreCase = true)) }
    }

    @Test fun homeIsClearForTheRatingAskWithOnlySheetsBlocking() {
        assertTrue(ReviewPromptTracker.isHomeClear(true, true, false, false))
        assertFalse(ReviewPromptTracker.isHomeClear(true, true, true, false))
        assertFalse(ReviewPromptTracker.isHomeClear(true, false, false, false))
        assertFalse(ReviewPromptTracker.isHomeClear(false, true, false, false))
        assertFalse(ReviewPromptTracker.isHomeClear(true, true, false, true))
    }

    // F12

    private class FakeHealth : HealthSource {
        override suspend fun access() = HealthAccess.READY
        override suspend fun capture(at: Instant) = HealthCaptureResult(CaptureSourceStatus.UNAVAILABLE, "none", null)
        override suspend fun sleepHoursForNightBefore(day: LocalDate): Double? = null
    }

    private class FakeEnvironment : EnvironmentSource {
        override suspend fun capture(at: Instant) = EnvironmentCaptureResult(CaptureSourceStatus.UNAVAILABLE, "none", null)
        override fun hasPermission() = false
        override fun authorizationSummary() = "Not yet asked"
    }

    @Test fun retryDoesNotCountAsANewLog() {
        val store = EventStore(MemoryTextFile())
        val capture = CaptureCoordinator(
            store, FakeHealth(), FakeEnvironment(), ReviewPromptTracker(InMemoryStore()), DeviceStateReader { }, CoroutineScope(Dispatchers.Unconfined),
        )
        assertTrue(capture.captureHeadache())
        assertFalse(capture.isCapturing)
        assertFalse("a fresh tap is not a retry", capture.currentRunIsRetry)
        val id = capture.lastCapturedEventId!!
        capture.retryCapture(id)
        assertTrue("the retry must not bring back Logged and Undo", capture.currentRunIsRetry)
        assertEquals(id, capture.lastCapturedEventId)
        assertTrue(capture.captureHeadache())
        assertFalse(capture.currentRunIsRetry)
    }

    // F4 helper, F9

    @Test fun asleepSecondsIsTheUnionOfRawSegments() {
        val t = Instant.ofEpochSecond(1_790_000_000)
        val a = SleepIntervalMerge.Interval(t, t.plusSeconds(3600))
        val b = SleepIntervalMerge.Interval(t.plusSeconds(1800), t.plusSeconds(5400))
        val c = SleepIntervalMerge.Interval(t.plusSeconds(7200), t.plusSeconds(10_800))
        assertEquals(5400.0 + 3600.0, SleepIntervalMerge.asleepSeconds(listOf(a, b, c)), 0.001)
    }

    @Test fun sleepTitleFollowsTheBand() {
        assertEquals("Long sleep: 8h+", InsightsEngine.sleepBandTitle("8h+", 8.0, 48.0))
        assertEquals("Short sleep: <5h", InsightsEngine.sleepBandTitle("<5h", 0.0, 5.0))
        assertEquals("Short sleep: 5–6h", InsightsEngine.sleepBandTitle("5–6h", 5.0, 6.0))
        assertEquals("Sleep: 7–8h", InsightsEngine.sleepBandTitle("7–8h", 7.0, 8.0))
    }

    // F8

    @Test fun mostCommonTiesGoToTheFirstKeyInOrder() {
        val counts = mapOf(3 to 2, 1 to 2, 6 to 1)
        assertEquals(1, counts.mostCommon((1..7).toList())?.first)
        assertEquals(1, linkedMapOf(1 to 2, 3 to 2).mostCommon((1..7).toList())?.first)
        assertNull(emptyMap<Int, Int>().mostCommon((1..7).toList()))
        val parts = mapOf(PartOfDay.MORNING to 2, PartOfDay.OVERNIGHT to 2)
        assertEquals(PartOfDay.OVERNIGHT, parts.mostCommon(PartOfDay.entries)?.first)
    }

    @Test fun mostCommonTimeIsStableOnTies() {
        // Two overnight, two morning and one afternoon log: the tie goes to the case declared first.
        val hours = listOf(8, 2, 9, 3, 14)
        val events = hours.mapIndexed { i, hour ->
            HeadacheEvent(LocalDate.of(2026, 10, 1).plusDays(i * 2L).atTime(hour, 0).toInstant(ZoneOffset.UTC), ZoneOffset.UTC)
        }
        listOf(events, events.reversed()).forEach {
            val titles = InsightsEngine.summarize(it, emptyList(), locale = Locale.US).insights.map { i -> i.title }.filter { t -> t.startsWith("Most common time") }
            assertEquals(listOf("Most common time: Overnight"), titles)
        }
    }

    // F14, F5

    @Test fun relativeRiskReadsAsHowMuchMoreLikely() {
        val signal = PersonalSignalProfile(totalDays = 30, conditionDays = 8, headacheConditionDays = 5, relativeRisk = 2.5, isSupported = true)
        assertEquals("2.5× more likely • 5 of 8 days", signalStatus(signal))
    }

    @Test fun restoreSaysWhyWhenNothingCameBack() {
        assertNull(ConversionCopy.restoreMessage(isPro = true, lastError = null))
        assertEquals(ConversionCopy.NO_PURCHASE_FOUND, ConversionCopy.restoreMessage(false, null))
        assertEquals("Couldn't reach Google Play.", ConversionCopy.restoreMessage(false, "Couldn't reach Google Play."))
        assertNotNull(ConversionCopy.restoreMessage(false, ""))
    }
}
