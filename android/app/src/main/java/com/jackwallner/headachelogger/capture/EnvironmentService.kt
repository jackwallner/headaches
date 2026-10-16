package com.jackwallner.headachelogger.capture

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.jackwallner.headachelogger.data.CachedLocation
import com.jackwallner.headachelogger.data.HeadacheSettings
import com.jackwallner.headachelogger.model.CaptureSourceStatus
import com.jackwallner.headachelogger.model.EnvironmentCaptureResult
import com.jackwallner.headachelogger.model.OpenMeteo
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Weather, air quality and place for one moment. A fake stands in for tests and screenshots. */
interface EnvironmentSource {
    suspend fun capture(at: Instant): EnvironmentCaptureResult
    fun hasPermission(): Boolean
    fun authorizationSummary(): String
}

/**
 * Port of `EnvironmentService`: one coarse location fix, reverse geocoding on
 * device, then Open-Meteo weather and air quality for that hour. Only the
 * coordinates and the date go to Open-Meteo; there is no account or key.
 */
class EnvironmentService(
    private val context: Context,
    private val settings: HeadacheSettings,
) : EnvironmentSource {
    private val locationManager: LocationManager? = context.getSystemService(LocationManager::class.java)

    override fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun servicesEnabled(): Boolean = locationManager?.let(LocationManagerCompat::isLocationEnabled) == true

    override fun authorizationSummary(): String = when {
        !servicesEnabled() -> "Off"
        hasPermission() -> "Allowed"
        settings.declinedLocation -> "Not allowed"
        else -> "Not yet asked"
    }

    override suspend fun capture(at: Instant): EnvironmentCaptureResult {
        if (settings.declinedLocation && !hasPermission()) {
            return unavailable("Location was turned off during setup. Allow location for this app in Android Settings to add weather and place context.")
        }
        if (!servicesEnabled()) return unavailable("Location services are turned off for this device.")
        if (!hasPermission()) return unavailable("Location permission is required for weather and place context.")
        val location = requestLocation()
            ?: return EnvironmentCaptureResult(CaptureSourceStatus.FAILED, "Could not determine your location.", null)
        settings.cachedLocation = CachedLocation(location.latitude, location.longitude, Instant.now())
        return fetch(location, at)
    }

    private suspend fun fetch(location: Location, at: Instant): EnvironmentCaptureResult = coroutineScope {
        val lat = location.latitude
        val lon = location.longitude
        val day = at.atZone(ZoneId.systemDefault()).toLocalDate()
        val place = async { reverseGeocode(location) }
        val air = async { Http.get(OpenMeteo.airQualityUrl(lat, lon, day))?.let { OpenMeteo.parseAirQuality(it, at) } }
        val weather = Http.get(OpenMeteo.hourlySlotUrl(OpenMeteo.FORECAST, lat, lon, day))?.let { OpenMeteo.parseHourlySlot(it, at) }
            ?: Http.get(OpenMeteo.hourlySlotUrl(OpenMeteo.ARCHIVE, lat, lon, day))?.let { OpenMeteo.parseHourlySlot(it, at) }
            ?: Http.get(OpenMeteo.currentUrl(lat, lon))?.let { OpenMeteo.parseCurrent(it, Instant.now()) }
        val (locality, region) = place.await()
        if (weather == null) {
            air.cancel()
            return@coroutineScope EnvironmentCaptureResult(
                CaptureSourceStatus.FAILED,
                "Couldn't reach the weather service. Check your connection and retry.",
                null,
            )
        }
        val altitude = if (location.hasAltitude()) location.altitude else null
        OpenMeteo.snapshot(locality, region, altitude, weather, air.await())
    }

    @SuppressLint("MissingPermission")
    private suspend fun requestLocation(): Location? {
        val lm = locationManager ?: return null
        val providers = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.PASSIVE_PROVIDER)
        }.filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
        val fresh = providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .filter { System.currentTimeMillis() - it.time < 10 * 60_000 }
            .maxByOrNull { it.time }
        if (fresh != null) return fresh
        val provider = providers.firstOrNull { it != LocationManager.PASSIVE_PROVIDER } ?: return null
        return withTimeoutOrNull(15_000) {
            suspendCancellableCoroutine { cont ->
                val signal = CancellationSignal()
                cont.invokeOnCancellation { signal.cancel() }
                runCatching {
                    LocationManagerCompat.getCurrentLocation(lm, provider, signal, ContextCompat.getMainExecutor(context)) { loc ->
                        if (cont.isActive) cont.resume(loc)
                    }
                }.onFailure { if (cont.isActive) cont.resume(null) }
            }
        } ?: providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
    }

    @Suppress("DEPRECATION")
    private suspend fun reverseGeocode(location: Location): Pair<String?, String?> {
        if (!Geocoder.isPresent()) return null to null
        val geocoder = Geocoder(context, Locale.getDefault())
        val address = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            withTimeoutOrNull(8_000) {
                suspendCancellableCoroutine { cont ->
                    geocoder.getFromLocation(location.latitude, location.longitude, 1, object : Geocoder.GeocodeListener {
                        override fun onGeocode(addresses: MutableList<android.location.Address>) {
                            if (cont.isActive) cont.resume(addresses.firstOrNull())
                        }

                        override fun onError(errorMessage: String?) {
                            if (cont.isActive) cont.resume(null)
                        }
                    })
                }
            }
        } else {
            withContext(Dispatchers.IO) {
                runCatching { geocoder.getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull() }.getOrNull()
            }
        }
        return address?.locality to (address?.adminArea?.let(::regionCode))
    }

    /** iOS reports US states as two-letter codes ("WA"); Android gives full names. */
    private fun regionCode(admin: String): String = US_STATES[admin] ?: admin

    private fun unavailable(message: String) = EnvironmentCaptureResult(CaptureSourceStatus.UNAVAILABLE, message, null)

    private companion object {
        val US_STATES = mapOf(
            "Alabama" to "AL", "Alaska" to "AK", "Arizona" to "AZ", "Arkansas" to "AR", "California" to "CA",
            "Colorado" to "CO", "Connecticut" to "CT", "Delaware" to "DE", "District of Columbia" to "DC", "Florida" to "FL",
            "Georgia" to "GA", "Hawaii" to "HI", "Idaho" to "ID", "Illinois" to "IL", "Indiana" to "IN", "Iowa" to "IA",
            "Kansas" to "KS", "Kentucky" to "KY", "Louisiana" to "LA", "Maine" to "ME", "Maryland" to "MD",
            "Massachusetts" to "MA", "Michigan" to "MI", "Minnesota" to "MN", "Mississippi" to "MS", "Missouri" to "MO",
            "Montana" to "MT", "Nebraska" to "NE", "Nevada" to "NV", "New Hampshire" to "NH", "New Jersey" to "NJ",
            "New Mexico" to "NM", "New York" to "NY", "North Carolina" to "NC", "North Dakota" to "ND", "Ohio" to "OH",
            "Oklahoma" to "OK", "Oregon" to "OR", "Pennsylvania" to "PA", "Rhode Island" to "RI", "South Carolina" to "SC",
            "South Dakota" to "SD", "Tennessee" to "TN", "Texas" to "TX", "Utah" to "UT", "Vermont" to "VT",
            "Virginia" to "VA", "Washington" to "WA", "West Virginia" to "WV", "Wisconsin" to "WI", "Wyoming" to "WY",
        )
    }
}
