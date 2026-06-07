package com.defendra.defendra

import android.os.Handler
import android.os.Looper
import org.tensorflow.lite.Interpreter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors

/**
 * Exposes CPU-only LiteRT inference over the "com.defendra/ml" method channel.
 *
 * Uses the Java Interpreter API which does NOT auto-apply XNNPACK (unlike the
 * C API used by flutter_litert). The C API unconditionally applies the built-in
 * XNNPACK delegate during TfLiteInterpreterCreate; XNNPACK then claims the
 * embedding lookup op, copies its weights internally, and sets tensor 120's
 * data.raw = nullptr — causing "Input tensor 120 lacks data" at every invoke.
 * The Java API creates a bare CPU interpreter with no delegates unless you
 * explicitly add them.
 */
class MlInferenceChannel(messenger: BinaryMessenger) {
    companion object {
        const val CHANNEL = "com.defendra/ml"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var interpreter: Interpreter? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(::onCall)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadModel" -> bg(result) {
                val path = call.arguments as String
                interpreter?.close()
                val opts = Interpreter.Options().apply { numThreads = 4 }
                interpreter = Interpreter(File(path), opts)
                null
            }

            "infer" -> bg(result) {
                val interp = interpreter
                    ?: error("Model not loaded — call loadModel first")
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as Map<String, Any>
                val ids  = args["ids"]  as LongArray
                val mask = args["mask"] as LongArray
                val seqLen = ids.size

                val idsBuf  = longBuf(ids)
                val maskBuf = longBuf(mask)
                val outBuf  = ByteBuffer.allocateDirect(4 * 4).order(ByteOrder.nativeOrder())

                interp.runForMultipleInputsOutputs(
                    arrayOf<Any>(idsBuf, maskBuf),
                    mapOf(0 to outBuf),
                )

                outBuf.rewind()
                val fb = outBuf.asFloatBuffer()
                listOf(
                    fb.get().toDouble(),
                    fb.get().toDouble(),
                    fb.get().toDouble(),
                    fb.get().toDouble(),
                )
            }

            "close" -> bg(result) {
                interpreter?.close()
                interpreter = null
                null
            }

            else -> result.notImplemented()
        }
    }

    private fun longBuf(data: LongArray): ByteBuffer {
        val buf = ByteBuffer.allocateDirect(data.size * 8).order(ByteOrder.nativeOrder())
        buf.asLongBuffer().put(data)
        buf.rewind()
        return buf
    }

    private fun bg(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("ML_ERROR", e.message, null) }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        interpreter?.close()
        interpreter = null
    }
}
