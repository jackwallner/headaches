package com.jackwallner.headachelogger.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Ports `ReviewPromptTracker`'s rules: ask from launch 2, 30-day cooldown, only the review page ends the asks. */
class ReviewPromptTrackerTest {
    private val day = 86_400_000L
    private var now = 1_800_000_000_000L
    private val tracker = ReviewPromptTracker(InMemoryStore()) { now }

    private fun launches(count: Int) = repeat(count) { tracker.recordAppLaunch() }

    @Test fun asksFromTheSecondLaunch() {
        launches(2)
        assertTrue(tracker.canRequestReview(true))
    }

    @Test fun neverAsksInTheFirstSession() {
        launches(1)
        assertFalse(tracker.canRequestReview(true))
    }

    @Test fun requiresFinishedSetup() {
        launches(9)
        assertFalse(tracker.canRequestReview(false))
    }

    @Test fun waitsOutTheCooldown() {
        launches(9)
        tracker.markShown()
        now += 29 * day
        assertFalse(tracker.canRequestReview(true))
        now += 2 * day
        assertTrue(tracker.canRequestReview(true))
    }

    @Test fun openingTheReviewPageEndsTheAsks() {
        launches(9)
        tracker.markOpenedWriteReview()
        now += 400 * day
        assertFalse(tracker.canRequestReview(true))
    }

    @Test fun feedbackDoesNotStopTheAsks() {
        launches(9)
        tracker.markFeedbackSubmitted()
        now += 31 * day
        assertTrue(tracker.canRequestReview(true))
    }

    @Test fun feedbackAfterTheReviewPageKeepsTheAsksEnded() {
        launches(9)
        tracker.markOpenedWriteReview()
        tracker.markFeedbackSubmitted()
        assertEquals(ReviewOutcome.OPENED_WRITE_REVIEW, tracker.outcome)
    }

    @Test fun aCompleteLogQueuesOneAsk() {
        launches(2)
        assertFalse(tracker.shouldRequestAfterPositiveMoment(true))
        tracker.recordPositiveMoment()
        assertTrue(tracker.shouldRequestAfterPositiveMoment(true))
        tracker.markShown()
        assertFalse(tracker.shouldRequestAfterPositiveMoment(true))
        assertEquals(1, tracker.positiveMomentCount)
    }
}
