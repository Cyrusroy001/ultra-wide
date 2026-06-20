package com.scanpay.scanpay

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import io.flutter.view.TextureRegistry

/**
 * Pure Camera2 driver. We open the requested *physical* camera id directly,
 * because that is the only reliable way to reach the ultrawide on devices where
 * the higher-level abstractions (and `mobile_scanner`'s "wide") bind to the
 * dead main lens. Preview goes to a Flutter [Texture]; an [ImageReader] feeds
 * ML Kit for QR decoding.
 */
class CameraController(
    private val context: Context,
    private val textures: TextureRegistry,
) {
    private val cameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null
    private var bgThread: HandlerThread? = null
    private var bgHandler: Handler? = null

    private var hasFlash = false
    private var sensorOrientation = 0
    private var torchOn = false
    private var zoomRatio = 1f
    private var processing = false

    private val scanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build(),
    )

    /** Called on the main thread (ML Kit's default executor) for each QR. */
    var onBarcode: ((String) -> Unit)? = null

    fun enumerate(): List<Map<String, Any>> {
        return cameraManager.cameraIdList.map { id ->
            val ch = cameraManager.getCameraCharacteristics(id)
            val facing = ch.get(CameraCharacteristics.LENS_FACING)
            val isBack = facing == CameraCharacteristics.LENS_FACING_BACK
            val focals = ch.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            val minFocal = (focals?.minOrNull() ?: 0f).toDouble()
            val flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
            val afModes = ch.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
                ?: IntArray(0)
            val af = afModes.any { it != CameraMetadata.CONTROL_AF_MODE_OFF }
            val maxZoom = (ch.get(
                CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM,
            ) ?: 1f).toDouble()
            mapOf(
                "id" to id,
                "isBackFacing" to isBack,
                "minFocalLengthMm" to minFocal,
                "hasFlash" to flash,
                "hasAutofocus" to af,
                "maxZoom" to maxZoom,
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun start(cameraId: String): Long {
        stop()
        startBg()

        val ch = cameraManager.getCameraCharacteristics(cameraId)
        sensorOrientation = ch.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        hasFlash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
        val map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val previewSize = chooseSize(map?.getOutputSizes(SurfaceTexture::class.java))
        val analysisSize = chooseSize(map?.getOutputSizes(ImageFormat.YUV_420_888))

        val entry = textures.createSurfaceTexture()
        textureEntry = entry
        val st = entry.surfaceTexture()
        st.setDefaultBufferSize(previewSize.width, previewSize.height)
        val pSurface = Surface(st)
        previewSurface = pSurface

        val reader = ImageReader.newInstance(
            analysisSize.width, analysisSize.height, ImageFormat.YUV_420_888, 2,
        )
        reader.setOnImageAvailableListener({ r -> onFrame(r) }, bgHandler)
        imageReader = reader

        cameraManager.openCamera(
            cameraId,
            object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    device = camera
                    createSession(camera, listOf(pSurface, reader.surface))
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    device = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    device = null
                }
            },
            bgHandler,
        )

        // Texture id is valid immediately; frames arrive once the session starts.
        return entry.id()
    }

    @Suppress("DEPRECATION")
    private fun createSession(camera: CameraDevice, surfaces: List<Surface>) {
        camera.createCaptureSession(
            surfaces,
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    session = s
                    startRepeating()
                }

                override fun onConfigureFailed(s: CameraCaptureSession) {}
            },
            bgHandler,
        )
    }

    private fun startRepeating() {
        val camera = device ?: return
        val s = session ?: return
        val preview = previewSurface ?: return
        val analysis = imageReader?.surface ?: return
        val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
        builder.addTarget(preview)
        builder.addTarget(analysis)
        builder.set(
            CaptureRequest.CONTROL_AF_MODE,
            CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
        )
        if (torchOn && hasFlash) {
            builder.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.set(CaptureRequest.CONTROL_ZOOM_RATIO, zoomRatio)
        }
        s.setRepeatingRequest(builder.build(), null, bgHandler)
    }

    private fun onFrame(reader: ImageReader) {
        val image = reader.acquireLatestImage() ?: return
        if (processing) {
            image.close()
            return
        }
        processing = true
        val input = InputImage.fromMediaImage(image, sensorOrientation)
        scanner.process(input)
            .addOnSuccessListener { barcodes ->
                for (b in barcodes) {
                    b.rawValue?.let { onBarcode?.invoke(it) }
                }
            }
            .addOnCompleteListener {
                image.close()
                processing = false
            }
    }

    fun setTorch(on: Boolean) {
        torchOn = on
        startRepeating()
    }

    fun setZoom(value: Double) {
        zoomRatio = value.toFloat()
        startRepeating()
    }

    @Suppress("UNUSED_PARAMETER")
    fun focusAt(x: Double, y: Double) {
        // Ultrawide modules are typically fixed-focus; no-op for the probe.
    }

    fun stop() {
        runCatching { session?.close() }
        session = null
        runCatching { device?.close() }
        device = null
        runCatching { imageReader?.close() }
        imageReader = null
        runCatching { previewSurface?.release() }
        previewSurface = null
        runCatching { textureEntry?.release() }
        textureEntry = null
        stopBg()
    }

    private fun chooseSize(sizes: Array<Size>?): Size {
        if (sizes == null || sizes.isEmpty()) return Size(1280, 720)
        val target = 1280 * 720
        return sizes.minByOrNull {
            kotlin.math.abs(it.width * it.height - target)
        } ?: sizes[0]
    }

    private fun startBg() {
        val t = HandlerThread("scanpay-camera").also { it.start() }
        bgThread = t
        bgHandler = Handler(t.looper)
    }

    private fun stopBg() {
        bgThread?.quitSafely()
        bgThread = null
        bgHandler = null
    }
}
