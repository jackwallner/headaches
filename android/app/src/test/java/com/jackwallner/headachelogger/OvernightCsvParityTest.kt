package com.jackwallner.headachelogger

import com.jackwallner.headachelogger.model.EventCsv
import com.jackwallner.headachelogger.model.HeadacheEvent
import com.jackwallner.headachelogger.model.ImportStrategy
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of the CSV round-trip guard in iOS `OvernightFindingsTests` (F7). */
class OvernightCsvParityTest {
    private val la = ZoneId.of("America/Los_Angeles")

    @Test fun csvRoundTripKeepsNotes() {
        val notes = listOf("- nausea, then aura", "Felt \"foggy\" before it started", "+1 day after the move", "@work again", "=HYPERLINK(1)", "plain")
        val events = notes.mapIndexed { i, text ->
            HeadacheEvent(Instant.ofEpochSecond(1_790_000_000L + i * 86_400L), la).apply { userNotes = text }
        }
        val rows = EventCsv.parse(EventCsv.export(events))
        val imported = mutableListOf<HeadacheEvent>()
        EventCsv.importInto(imported, rows, ImportStrategy.SKIP_EXISTING, la)
        assertEquals(notes.size, imported.size)
        assertEquals(notes, imported.sortedBy { it.timestamp }.map { it.userNotes })
        assertNotNull(rows.first()["user_notes"])
        assertTrue(rows.map { it["user_notes"] }.containsAll(notes))
    }
}
