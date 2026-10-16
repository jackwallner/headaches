package com.jackwallner.headachelogger.capture

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A plain GET with the iOS request timeouts; null on any failure or non-2xx status. */
object Http {
    suspend fun get(url: String, timeoutMs: Int = 8_000): String? = withContext(Dispatchers.IO) {
        runCatching {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.setRequestProperty("Accept", "application/json")
            try {
                if (conn.responseCode !in 200..299) null else conn.inputStream.bufferedReader().use { it.readText() }
            } finally {
                conn.disconnect()
            }
        }.getOrNull()
    }
}
