package com.fintechsys.camera_plugin

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.StreamConfigurationMap
import android.util.Size
import android.content.Context 
import android.view.View
import io.flutter.plugin.platform.PlatformView
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.CameraControl
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

class CameraPreview(
  private val plugin: CameraPlugin,
  private var width: Int,
  private var height: Int,
  private var quality: Int,
  private var useMaxResolution: Boolean,
  private var cameraType: String,
  private val frameFormat: String
) : PlatformView {

  private val previewView = PreviewView(plugin.activity)
  private val executor    = Executors.newSingleThreadExecutor()
  private var provider: ProcessCameraProvider? = null
  private var selector: CameraSelector           = CameraSelector.DEFAULT_BACK_CAMERA
  private var control: CameraControl?            = null
  private lateinit var previewUseCase: Preview
  private lateinit var analysisUseCase: ImageAnalysis

  init {
    plugin.registerCameraPreview(this)
    startCamera()
  }

  private fun startCamera() {
    ProcessCameraProvider.getInstance(plugin.activity).also { future ->
      future.addListener({
        provider = future.get()
        selector = chooseCamera()
        provider?.unbindAll()
        if (useMaxResolution) {
          getMaxSize(provider!!, selector).also {
            width = it.width; height = it.height
          }
        }
        buildPreviewUseCase()
        buildAnalysisUseCase()
        bindAll()
      }, ContextCompat.getMainExecutor(plugin.activity))
    }
  }

  private fun chooseCamera(): CameraSelector {
    when (cameraType) {
      "front" -> {
        return CameraSelector.DEFAULT_FRONT_CAMERA
      }
      "macroBack" -> {
        findMacroCameraId()?.let { macroId ->
          return CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .addCameraFilter { infos ->
              infos.filter { Camera2CameraInfo.from(it).cameraId == macroId }
            }
            .build()
        }
        return CameraSelector.DEFAULT_BACK_CAMERA
      }
      else -> {
        // Default to macro back camera behavior
        findMacroCameraId()?.let { macroId ->
          return CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_BACK)
            .addCameraFilter { infos ->
              infos.filter { Camera2CameraInfo.from(it).cameraId == macroId }
            }
            .build()
        }
        return CameraSelector.DEFAULT_BACK_CAMERA
      }
    }
  }

  private fun findMacroCameraId(): String? {
    val mgr = plugin.activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    var bestId: String? = null
    var maxFocus = 0f
    mgr.cameraIdList.forEach { id ->
      val chars = mgr.getCameraCharacteristics(id)
      if (chars.get(CameraCharacteristics.LENS_FACING) ==
          CameraCharacteristics.LENS_FACING_BACK
      ) {
        val focus = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
        if (focus > maxFocus) {
          maxFocus = focus
          bestId = id
        }
      }
    }
    return bestId
  }

  private fun getMaxSize(provider: ProcessCameraProvider, selector: CameraSelector): Size {
    val infos   = provider.availableCameraInfos
    val matched = selector.filter(infos)
    if (matched.isEmpty()) return Size(width, height)
    val chars = Camera2CameraInfo.extractCameraCharacteristics(matched[0])
    val map   = chars.get(
      CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP
    ) as? StreamConfigurationMap ?: return Size(width, height)
    return map.getOutputSizes(ImageFormat.YUV_420_888)
      .maxByOrNull { it.width.toLong() * it.height.toLong() }
      ?: Size(width, height)
  }

  private fun buildPreviewUseCase() {
    previewUseCase = Preview.Builder()
      .setResolutionSelector(
        ResolutionSelector.Builder()
          .setResolutionStrategy(
            ResolutionStrategy(
              Size(1280, 720),
              ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
            )
          )
          .build()
      )
      .build()
      .also { it.setSurfaceProvider(previewView.surfaceProvider) }
  }

  private fun buildAnalysisUseCase() {
    analysisUseCase = ImageAnalysis.Builder()
      .setResolutionSelector(
        ResolutionSelector.Builder()
          .setResolutionStrategy(
            ResolutionStrategy(
              Size(width, height),
                ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER
            )
          )
          .build()
      )
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .build()
      .also { useCase ->
        useCase.setAnalyzer(executor) { image ->
          val frameData = if (frameFormat == "yuv420888") {
            toYuv420888(image)
          } else {
            toJpeg(image)
          }
          plugin.sendFrame(frameData)
          image.close()
        }
      }
  }

  private fun bindAll() {
    provider?.bindToLifecycle(
      plugin.activity as LifecycleOwner,
      selector,
      previewUseCase,
      analysisUseCase
    )?.also { control = it.cameraControl }
  }

  fun changeAnalysisResolution(w: Int, h: Int, q: Int, useMax: Boolean) {
    width = w; height = h; quality = q; useMaxResolution = useMax
    provider?.let {
      it.unbind(analysisUseCase)
      buildAnalysisUseCase()
      bindAll()
    }
  }

  fun turnOnFlash()  = control?.enableTorch(true)
  fun turnOffFlash() = control?.enableTorch(false)

  override fun getView(): View = previewView

  override fun dispose() {
    provider?.unbindAll()
    executor.shutdown()
  }

 private fun toJpeg(image: ImageProxy): ByteArray {
    val nv21 = yuv420888ToNv21(image)

    val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
    val jpegOutput = ByteArrayOutputStream()
    yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), quality, jpegOutput)

    val jpegBytes = jpegOutput.toByteArray()
    val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)

    val rotatedBitmap = if (cameraType == "front") {
      // Rotate front camera images by -90 degrees
      Bitmap.createBitmap(
          bitmap, 0, 0, bitmap.width, bitmap.height,
          Matrix().apply { postRotate(-90f) },
          true
      )
    } else {
      // Rotate back camera images by 90 degrees
      Bitmap.createBitmap(
          bitmap, 0, 0, bitmap.width, bitmap.height,
          Matrix().apply { postRotate(90f) },
          true
      )
    }

    return ByteArrayOutputStream().also {
        rotatedBitmap.compress(Bitmap.CompressFormat.JPEG, quality, it)
    }.toByteArray()
}

private fun yuv420888ToNv21(image: ImageProxy): ByteArray {
    val width = image.width
    val height = image.height
    val ySize = width * height
    val uvSize = width * height / 2
    val nv21 = ByteArray(ySize + uvSize)

    val yBuffer = image.planes[0].buffer
    val uBuffer = image.planes[1].buffer
    val vBuffer = image.planes[2].buffer

    val yRowStride = image.planes[0].rowStride
    val uRowStride = image.planes[1].rowStride
    val vRowStride = image.planes[2].rowStride
    val uPixelStride = image.planes[1].pixelStride
    val vPixelStride = image.planes[2].pixelStride

    // Copy Y channel
    var pos = 0
    for (row in 0 until height) {
        yBuffer.position(row * yRowStride)
        yBuffer.get(nv21, pos, width)
        pos += width
    }

    // Interleave V and U into NV21 format (VU order)
    var offset = ySize
    val chromaHeight = height / 2
    val chromaWidth = width / 2

    for (row in 0 until chromaHeight) {
        val vRowStart = row * vRowStride
        val uRowStart = row * uRowStride
        for (col in 0 until chromaWidth) {
            val vIndex = vRowStart + col * vPixelStride
            val uIndex = uRowStart + col * uPixelStride
            nv21[offset++] = vBuffer.get(vIndex) // V
            nv21[offset++] = uBuffer.get(uIndex) // U
        }
    }

    return nv21
}

private fun toYuv420888(image: ImageProxy): ByteArray {
    val width = image.width
    val height = image.height
    val ySize = width * height
    val uvSize = width * height / 4  // U and V planes are each 1/4 the size of Y
    
    val yBuffer = image.planes[0].buffer.duplicate()
    val uBuffer = image.planes[1].buffer.duplicate()
    val vBuffer = image.planes[2].buffer.duplicate()
    
    val yRowStride = image.planes[0].rowStride
    val uRowStride = image.planes[1].rowStride
    val vRowStride = image.planes[2].rowStride
    val uPixelStride = image.planes[1].pixelStride
    val vPixelStride = image.planes[2].pixelStride
    
    // Create output array: Y plane + U plane + V plane
    val output = ByteArray(ySize + uvSize * 2)
    
    // Copy Y plane
    var pos = 0
    for (row in 0 until height) {
        yBuffer.position(row * yRowStride)
        yBuffer.get(output, pos, width)
        pos += width
    }
    
    // Copy U plane
    val uHeight = height / 2
    val uWidth = width / 2
    for (row in 0 until uHeight) {
        val uRowStart = row * uRowStride
        for (col in 0 until uWidth) {
            val uIndex = uRowStart + col * uPixelStride
            uBuffer.position(uIndex)
            output[pos++] = uBuffer.get()
        }
    }
    
    // Copy V plane
    val vHeight = height / 2
    val vWidth = width / 2
    for (row in 0 until vHeight) {
        val vRowStart = row * vRowStride
        for (col in 0 until vWidth) {
            val vIndex = vRowStart + col * vPixelStride
            vBuffer.position(vIndex)
            output[pos++] = vBuffer.get()
        }
    }
    
    return output
}

}
