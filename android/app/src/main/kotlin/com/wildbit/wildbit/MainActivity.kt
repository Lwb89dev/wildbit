package com.wildbit.wildbit

import android.content.Context
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Fragment activity is required by Amber's NIP-55 activity-result flow.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GNSS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "primeAssistanceData" -> result.success(primeAssistanceData())
                    "isLocationEnabled" -> result.success(isLocationEnabled())
                    "lastKnownLocation" -> result.success(lastKnownLocation())
                    "availableStorageBytes" -> result.success(availableStorageBytes())
                    else -> result.notImplemented()
                }
            }
    }

    private fun availableStorageBytes(): Long {
        return runCatching { StatFs(filesDir.path).availableBytes }.getOrDefault(-1L)
    }

    private fun primeAssistanceData(): Boolean {
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return false
        val commands = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            listOf("force_psds_injection", "force_time_injection")
        } else {
            listOf("force_xtra_injection", "force_time_injection")
        }
        return commands.fold(false) { accepted, command ->
            runCatching {
                manager.sendExtraCommand(LocationManager.GPS_PROVIDER, command, null)
            }.getOrDefault(false) || accepted
        }
    }

    private fun isLocationEnabled(): Boolean {
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return false
        return runCatching {
            manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        }.getOrDefault(false)
    }

    // NETWORK_PROVIDER's cache refreshes far more often than GPS_PROVIDER's
    // (cell/Wi-Fi geolocation needs no satellite lock), so it is almost always
    // the newer of the two. Picking "most recent" therefore almost always
    // picked the coarse network fix over a still-usable, far more precise GPS
    // one — a fixed, direction-consistent offset from the real position (not
    // random jitter), because it is biased toward whichever cell tower/Wi-Fi
    // AP is nearest, which does not change while standing in one spot.
    private val maxCacheAgeMs = 5 * 60 * 1000L

    private fun lastKnownLocation(): Map<String, Any?>? {
        Log.d("WildBitGNSS", "lastKnownLocation requested")
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        val now = System.currentTimeMillis()
        val candidates = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull { provider ->
                val value = runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
                Log.d("WildBitGNSS", "$provider cached=${value != null} time=${value?.time ?: 0} accuracy=${value?.accuracy ?: -1}")
                value
            }
        if (candidates.isEmpty()) {
            Log.d("WildBitGNSS", "no cached location")
            return null
        }
        // Prefer accuracy over recency among fixes still worth trusting; only
        // fall back to a stale one (still better than nothing) if every
        // candidate has aged out.
        val fresh = candidates.filter { now - it.time <= maxCacheAgeMs }
        val location = (fresh.ifEmpty { candidates }).minByOrNull { it.accuracy }!!
        Log.d("WildBitGNSS", "using lat=${location.latitude} lon=${location.longitude} accuracy=${location.accuracy}")
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "timestamp" to location.time,
            "accuracy" to location.accuracy.toDouble(),
            "altitude" to location.altitude,
            "bearing" to location.bearing.toDouble(),
            "speed" to location.speed.toDouble(),
        )
    }

    private companion object {
        const val GNSS_CHANNEL = "app.wildbit/gnss"
    }
}
