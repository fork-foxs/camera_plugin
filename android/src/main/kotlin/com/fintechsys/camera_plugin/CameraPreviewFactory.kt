package com.fintechsys.camera_plugin

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CameraPreviewFactory(
  private val plugin: CameraPlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

  override fun create(context: Context, id: Int, args: Any?): PlatformView {
    @Suppress("UNCHECKED_CAST")
    val params = args as? Map<String, Any>
    val w      = params?.get("resolutionWidth")  as? Int     ?: 720
    val h      = params?.get("resolutionHeight") as? Int     ?: 420
    val q      = params?.get("resolutionQuality")as? Int     ?: 100
    val useMax = params?.get("maxResolution")    as? Boolean ?: false
    val camType = params?.get("cameraType")      as? String   ?: "macroBack"
    return CameraPreview(plugin, w, h, q, useMax, camType)
  }
}
