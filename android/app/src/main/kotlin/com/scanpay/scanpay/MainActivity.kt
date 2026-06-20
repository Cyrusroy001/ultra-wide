package com.scanpay.scanpay

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var controller: CameraController? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val cam = CameraController(applicationContext, flutterEngine.renderer)
        controller = cam
        cam.onBarcode = { value -> eventSink?.success(value) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scanpay/camera")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "enumerate" -> result.success(cam.enumerate())
                        "start" -> {
                            val id = call.argument<String>("cameraId")!!
                            result.success(cam.start(id))
                        }
                        "stop" -> {
                            cam.stop()
                            result.success(null)
                        }
                        "torch" -> {
                            cam.setTorch(call.argument<Boolean>("on")!!)
                            result.success(null)
                        }
                        "zoom" -> {
                            cam.setZoom(call.argument<Double>("value")!!)
                            result.success(null)
                        }
                        "focus" -> {
                            cam.focusAt(
                                call.argument<Double>("x")!!,
                                call.argument<Double>("y")!!,
                            )
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("camera_error", e.message, null)
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "scanpay/barcodes")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onDestroy() {
        controller?.stop()
        super.onDestroy()
    }
}
