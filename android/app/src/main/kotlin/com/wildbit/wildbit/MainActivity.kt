package com.wildbit.wildbit

import android.content.Context
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
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
                    else -> result.notImplemented()
                }
            }
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

    private fun lastKnownLocation(): Map<String, Any?>? {
        Log.d("WildBitGNSS", "lastKnownLocation requested")
        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return null
        val candidates = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull { provider ->
                val value = runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
                Log.d("WildBitGNSS", "$provider cached=${value != null} time=${value?.time ?: 0}")
                value
            }
        val location = candidates
            .maxByOrNull { it.time }
            ?: run {
                Log.d("WildBitGNSS", "no cached location")
                return null
            }
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
