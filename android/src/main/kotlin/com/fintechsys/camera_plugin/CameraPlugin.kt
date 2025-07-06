package com.fintechsys.camera_plugin

import android.app.Activity
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class CameraPlugin : FlutterPlugin, ActivityAware {
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel
  lateinit var activity: Activity
  private var preview: CameraPreview? = null
  private var sink: EventChannel.EventSink? = null
  private val handler = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(@NonNull binding: FlutterPluginBinding) {
    binding.platformViewRegistry
      .registerViewFactory("camera_preview", CameraPreviewFactory(this))

    eventChannel = EventChannel(binding.binaryMessenger, "camera_stream")
      .apply {
        setStreamHandler(object : EventChannel.StreamHandler {
          override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            sink = events
          }
          override fun onCancel(arguments: Any?) {
            sink = null
          }
        })
      }

    methodChannel = MethodChannel(binding.binaryMessenger, "camera_control")
      .apply {
        setMethodCallHandler { call, result ->
          when (call.method) {
            "turnOnFlash"   -> { preview?.turnOnFlash();   result.success(null) }
            "turnOffFlash"  -> { preview?.turnOffFlash();  result.success(null) }
            "disposeCamera" -> {
              preview?.dispose()
              sink = null
              result.success(null)
            }
            "changeResolution" -> {
              @Suppress("UNCHECKED_CAST")
              val args  = call.arguments as? Map<String, Any>
              val newW   = args?.get("resolutionWidth")  as? Int     ?: 720
              val newH   = args?.get("resolutionHeight") as? Int     ?: 420
              val newQ   = args?.get("resolutionQuality")as? Int     ?: 50
              val useMax = args?.get("maxResolution")    as? Boolean ?: false
              preview?.changeAnalysisResolution(newW, newH, newQ, useMax)
              result.success(null)
            }
            else -> result.notImplemented()
          }
        }
      }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }

  fun registerCameraPreview(p: CameraPreview) {
    preview = p
  }

  fun sendFrame(frame: ByteArray) {
    handler.post { sink?.success(frame) }
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }
  override fun onDetachedFromActivityForConfigChanges() = Unit
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }
  override fun onDetachedFromActivity() = Unit
}
