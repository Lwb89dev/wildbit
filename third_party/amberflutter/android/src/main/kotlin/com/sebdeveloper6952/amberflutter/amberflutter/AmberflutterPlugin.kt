package com.sebdeveloper6952.amberflutter.amberflutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ProviderInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.sebdeveloper6952.amberflutter.amberflutter.models.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** AmberflutterPlugin */
class AmberflutterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var _channel : MethodChannel
  private lateinit var _context : Context
  private var _activity: Activity? = null
  private var _activityBinding: ActivityPluginBinding? = null

  /// The Dart call waiting for Amber's activity result, if any.
  private var _pendingResult: MethodChannel.Result? = null

  private val _intentRequestCode = 0

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    _channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.sebdeveloper6952.amberflutter")
    _channel.setMethodCallHandler(this)
    _context = flutterPluginBinding.applicationContext
  }

  fun isPackageInstalled(context: Context, target: String): Boolean {
    return try {
      context.packageManager.getPackageInfo(target, 0)
      true
    } catch (e: PackageManager.NameNotFoundException) {
      false
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == nostrsignerUri) {
      val paramsMap = call.arguments as? HashMap<*, *>
      if (paramsMap == null) {
        result.error("invalid_arguments", "Missing signer request", null)
        return
      }

      val requestType = paramsMap[intentExtraKeyType] as? String ?: ""
      val currentUser = paramsMap[intentExtraKeyCurrentUser] as? String ?: ""
      val pubKey = paramsMap[intentExtraKeyPubKey] as? String ?: ""
      val id = paramsMap[intentExtraKeyId] as? String ?: ""
      val uriData = paramsMap[intentExtraKeyUriData] as? String ?: ""
      val permissions = paramsMap[intentExtraKeyPermissions] as? String ?: ""

      val data = getDataFromContentResolver(
        requestType.uppercase(),
        arrayOf(uriData, pubKey, currentUser),
        _context,
      )
      if (!data.isNullOrEmpty()) {
        result.success(data)
        return
      }

      val activity = _activity
      if (activity == null) {
        result.error("no_activity", "No foreground activity to start Amber", null)
        return
      }

      val intent = Intent(
        Intent.ACTION_VIEW,
        Uri.parse(
          "$nostrsignerUri:$uriData"
        )
      )
      // Only Amber may receive the request: an implicit `nostrsigner:`
      // intent can be claimed by any installed app, and the URI carries the
      // payload in clear (for nip44_encrypt, the database key itself).
      intent.setPackage(amberPackageName)

      intent.putExtra(intentExtraKeyType, requestType)
      intent.putExtra(intentExtraKeyCurrentUser, currentUser)
      intent.putExtra(intentExtraKeyPubKey, pubKey)
      intent.putExtra(intentExtraKeyId, id)
      intent.putExtra(intentExtraKeyPermissions, permissions)

      // A previous request still waiting for Amber can no longer be matched
      // to a result; answer it as cancelled instead of leaving it hanging.
      _pendingResult?.success(HashMap<String, String?>())
      _pendingResult = MethodResultWrapper(result)
      try {
        activity.startActivityForResult(
          intent,
          _intentRequestCode
        )
      } catch (e: ActivityNotFoundException) {
        _pendingResult = null
        result.error("signer_unavailable", "Amber is not installed", null)
      }
    } else if (call.method == "isAppInstalled") {
        val paramsMap = call.arguments as? HashMap<*, *>
        val packageName = paramsMap?.get("packageName") as? String
        if (packageName == null) {
            result.error("invalid_arguments", "Missing package name", null)
            return
        }
        result.success(isPackageInstalled(_context, packageName))
    } else {
      result.notImplemented()
    }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, intent: Intent?): Boolean {
    if (requestCode != _intentRequestCode) return false
    val pending = _pendingResult ?: return true
    _pendingResult = null
    val dataMap: HashMap<String, String?> = HashMap()
    if (resultCode == Activity.RESULT_OK && intent != null) {
      // Recent NIP-55 signers name the signature extra `result`.
      val signature = intent.getStringExtra(intentExtraKeySignature)
        ?: intent.getStringExtra(intentExtraKeyResult)
      if (signature != null) dataMap[intentExtraKeySignature] = signature
      intent.getStringExtra(intentExtraKeyId)?.let { dataMap[intentExtraKeyId] = it }
      intent.getStringExtra(intentExtraKeyEvent)?.let { dataMap[intentExtraKeyEvent] = it }
    }
    // An empty map is how the Dart side recognises a cancelled request. Not
    // answering a cancelled or failed result left the caller waiting forever.
    pending.success(dataMap)
    return true
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    _channel.setMethodCallHandler(null)
  }

  override fun onDetachedFromActivity() {
    _activityBinding?.removeActivityResultListener(this)
    _activityBinding = null
    _activity = null
    // The activity that would receive Amber's answer is gone for good.
    _pendingResult?.success(HashMap<String, String?>())
    _pendingResult = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    attachTo(binding)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    attachTo(binding)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    // Keep a pending request: the recreated activity receives Amber's result.
    _activityBinding?.removeActivityResultListener(this)
    _activityBinding = null
    _activity = null
  }

  private fun attachTo(binding: ActivityPluginBinding) {
    _activity = binding.activity
    _activityBinding = binding
    binding.addActivityResultListener(this)
  }

  /*
    Code taken from: https://github.com/0xchat-app/nostr-dart/blob/main/android/src/main/kotlin/com/oxchat/nostrcore/ChatcorePlugin.kt
   */
  private fun getDataFromContentResolver(
    type: String,
    uriData: Array<out String>,
    context: Context,
  ): HashMap<String, String?>? {
    val authority = "${amberPackageName}.$type"
    // Content provider authorities are first come, first served: without
    // Amber installed, another app could register this one and receive the
    // request payload. Only query the provider when Amber owns it.
    if (providerFor(context, authority)?.packageName != amberPackageName) {
      return null
    }
    try {
      context.contentResolver.query(
        Uri.parse("content://$authority"),
        uriData,
        null,
        null,
        null
      ).use {
        if (it == null || !it.moveToFirst()) return null
        val dataMap: HashMap<String, String?> = HashMap()
        val signatureIndex = it.getColumnIndex(intentExtraKeySignature)
          .takeIf { index -> index >= 0 }
          ?: it.getColumnIndex(intentExtraKeyResult)
        if (signatureIndex >= 0) {
          dataMap[intentExtraKeySignature] = it.getString(signatureIndex)
        }
        val eventIndex = it.getColumnIndex(intentExtraKeyEvent)
        if (eventIndex >= 0) {
          dataMap[intentExtraKeyEvent] = it.getString(eventIndex)
        }
        return dataMap
      }
    } catch (e: Exception) {
      return null
    }
  }

  private fun providerFor(context: Context, authority: String): ProviderInfo? {
    val packageManager = context.packageManager
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      packageManager.resolveContentProvider(
        authority,
        PackageManager.ComponentInfoFlags.of(0),
      )
    } else {
      @Suppress("DEPRECATION")
      packageManager.resolveContentProvider(authority, 0)
    }
  }
}


private class MethodResultWrapper internal constructor(result: MethodChannel.Result) :
  MethodChannel.Result {
  private val methodResult: MethodChannel.Result
  private val handler: Handler

  init {
    methodResult = result
    handler = Handler(Looper.getMainLooper())
  }

  override fun success(result: Any?) {
    handler.post { methodResult.success(result) }
  }

  override fun error(
    errorCode: String, errorMessage: String?, errorDetails: Any?
  ) {
    handler.post { methodResult.error(errorCode, errorMessage, errorDetails) }
  }

  override fun notImplemented() {
    handler.post { methodResult.notImplemented() }
  }
}
