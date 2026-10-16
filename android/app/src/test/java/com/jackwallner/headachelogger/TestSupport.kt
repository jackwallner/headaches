package com.jackwallner.headachelogger

import com.jackwallner.headachelogger.model.HeadacheEvent
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** iOS `makeEvent(daysAgo:hour:)`: that many days back, at the given hour on the hour. */
fun makeEvent(daysAgo: Int, hour: Int, zone: ZoneId = ZoneId.systemDefault()): HeadacheEvent {
    val ts = LocalDate.now(zone).minusDays(daysAgo.toLong()).atTime(LocalTime.of(hour, 0)).atZone(zone).toInstant()
    return HeadacheEvent(ts, zone)
}

fun epoch(seconds: Long): Instant = Instant.ofEpochSecond(seconds)
