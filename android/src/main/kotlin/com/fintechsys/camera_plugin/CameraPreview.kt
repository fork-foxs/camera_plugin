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
  private var useMaxResolution: Boolean
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
              ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
            )
          )
          .build()
      )
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .build()
      .also { useCase ->
        useCase.setAnalyzer(executor) { image ->
          plugin.sendFrame(toJpeg(image))
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
   val y = image.planes[0].buffer
    val u = image.planes[1].buffer
    val v = image.planes[2].buffer
    val ySize = y.remaining()
    val uSize = u.remaining()
    val vSize = v.remaining()

    val nv21 = ByteArray(ySize + uSize + vSize).apply {
      y.get(this, 0, ySize)
      v.get(this, ySize, vSize)
      u.get(this, ySize + vSize, uSize)
    }

    val yuv = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
    val out = ByteArrayOutputStream().apply {
      yuv.compressToJpeg(Rect(0, 0, image.width, image.height), quality, this)
    }
    val raw = out.toByteArray()
    val bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size)
    val rotated = Bitmap.createBitmap(
      bmp, 0, 0, bmp.width, bmp.height,
      Matrix().apply { postRotate(90f) },
      true
    )
    return ByteArrayOutputStream().also {
      rotated.compress(Bitmap.CompressFormat.JPEG, quality, it)
    }.toByteArray()
  }
}
