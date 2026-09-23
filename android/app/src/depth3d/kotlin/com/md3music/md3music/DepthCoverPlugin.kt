package com.md3music.md3music

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.FloatBuffer
import java.util.ArrayList
import java.util.HashSet
import java.util.concurrent.Executors

/**
 * Depth Anything V2 ViT-S 推理 + 封面三层切割（背景/中景/前景，带 alpha）。
 *
 * 通道名 "com.md3music.md3music/depth_cover"，方法：
 * - isModelLoaded() -> Boolean
 * - loadModel(modelPath) -> Boolean | error("LOAD_FAILED", ...)
 * - generate(sourcePath, sourceBytes?, outDir, key) -> {layers:[3 绝对路径]} | null(同 key 在途) | error(...)
 *
 * 输出文件固定为 layer0.png / layer1.png / layer2.png（与 Dart 侧 DepthCoverCache 约定一致）。
 */
object DepthCoverPlugin {
    private const val CHANNEL = "com.md3music.md3music/depth_cover"
    private const val TAG = "DepthCover"
    private const val DEPTH_SIZE = 518 // 模型输入固定 518x518 深度网格
    // ImageNet 归一化常量（与 fabio-sim/Depth-Anything-ONNX infer.py 一致）
    private val MEAN = floatArrayOf(0.485f, 0.456f, 0.406f)
    private val STD = floatArrayOf(0.229f, 0.224f, 0.225f)
    // 深度带（0=远/背景, 1=近/前景），相邻带重叠 + 羽化避免硬边
    private val BANDS = arrayOf(
        floatArrayOf(0.00f, 0.40f), // layer0 背景
        floatArrayOf(0.35f, 0.70f), // layer1 中景
        floatArrayOf(0.65f, 1.00f), // layer2 前景
    )
    private const val FEATHER = 0.10f // 归一化羽化带宽

    // 模型以资产形式内置 APK（不再运行时下载）：首次 loadModel 时提取到应用目录
    private const val MODEL_ASSET = "models/depth_anything_v2_vits_fp16.onnx"
    private const val MODEL_BYTES = 49642442L // 上游 fp16 资产字节数，用于提取完整性校验

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var session: OrtSession? = null
    private var env: OrtEnvironment? = null
    private val inFlight = HashSet<String>()
    private var hostActivity: Activity? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        hostActivity = activity
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isModelLoaded" -> result.success(session != null)
                "loadModel" -> {
                    // 优先用显式 modelPath（测试/调试）；缺省从 APK 资产提取到应用目录后加载
                    val explicitPath = call.argument<String>("modelPath")
                    val assetPath = call.argument<String>("modelAsset") ?: MODEL_ASSET
                    Log.d(TAG, "loadModel begin: explicit=$explicitPath asset=$assetPath")
                    executor.execute {
                        var extracted: File? = null
                        try {
                            env = OrtEnvironment.getEnvironment()
                            session?.close()
                            val path = explicitPath
                                ?: extractModelAsset(hostActivity!!, assetPath).also { extracted = File(it) }
                            session = env!!.createSession(
                                File(path).readBytes(),
                                OrtSession.SessionOptions().apply { setIntraOpNumThreads(4) },
                            )
                            Log.d(TAG, "loadModel OK")
                            mainHandler.post { result.success(true) }
                        } catch (e: Exception) {
                            // 提取产物损坏时删除半成品，允许下次重试
                            if (explicitPath == null) extracted?.delete()
                            Log.e(TAG, "loadModel FAILED", e)
                            mainHandler.post { result.error("LOAD_FAILED", e.message, null) }
                        }
                    }
                }
                "generate" -> {
                    val sourcePath = call.argument<String>("sourcePath")!!
                    val sourceBytes = call.argument<ByteArray>("sourceBytes")
                    val outDir = call.argument<String>("outDir")!!
                    val key = call.argument<String>("key")!!
                    val s = session
                    if (s == null) {
                        result.error("MODEL_NOT_LOADED", "call loadModel first", null)
                        return@setMethodCallHandler
                    }
                    // 单飞行守卫：记账语义为「已成功完成」；在途直接返回 null，失败路径会移除以便重试
                    if (!inFlight.add(key)) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            Log.d(TAG, "generate begin: key=$key src=$sourcePath exists=${File(sourcePath).exists()} outDir=$outDir")
                            val paths = generate(s, sourcePath, sourceBytes, outDir, key)
                            Log.d(TAG, "generate OK: $paths")
                            mainHandler.post { result.success(paths) }
                        } catch (e: Exception) {
                            Log.e(TAG, "generate FAILED", e)
                            mainHandler.post { result.error("GENERATE_FAILED", e.message, null) }
                        } finally {
                            inFlight.remove(key)
                        }
                    }
                }
                "generateDepth" -> {
                    val sourcePath = call.argument<String>("sourcePath")!!
                    val outDir = call.argument<String>("outDir")!!
                    val key = call.argument<String>("key")!!
                    val s = session
                    if (s == null) {
                        result.error("MODEL_NOT_LOADED", "call loadModel first", null)
                        return@setMethodCallHandler
                    }
                    if (!inFlight.add(key)) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            Log.d(TAG, "generateDepth begin: key=$key src=$sourcePath")
                            val src = BitmapFactory.decodeFile(sourcePath)
                                ?: throw IllegalStateException("cannot decode cover")
                            val norm = normalize(infer(s, src))
                            val std = depthStd(norm)
                            src.recycle()
                            // 灰度 8-bit PNG（ShengChao DepthEngine.swift:111-132 同构）：
                            // 用 ARGB 位图承载灰度（R=G=B=gray, A=255），避免 ALPHA_8 无法 compress
                            val size = DEPTH_SIZE
                            val pixels = IntArray(size * size)
                            for (i in pixels.indices) {
                                val g = (norm[i] * 255f).toInt().coerceIn(0, 255)
                                pixels[i] = 0xFF000000.toInt() or (g shl 16) or (g shl 8) or g
                            }
                            val gray = Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
                            val out = File(outDir).apply { mkdirs() }
                            val f = File(out, "depth.png")
                            FileOutputStream(f).use { gray.compress(Bitmap.CompressFormat.PNG, 100, it) }
                            gray.recycle()
                            Log.d(TAG, "generateDepth OK: ${f.absolutePath} std=$std")
                            mainHandler.post { result.success(mapOf("depth" to f.absolutePath, "depthStd" to std)) }
                        } catch (e: Exception) {
                            Log.e(TAG, "generateDepth FAILED", e)
                            mainHandler.post { result.error("GENERATE_FAILED", e.message, null) }
                        } finally {
                            inFlight.remove(key)
                        }
                    }
                }
                // 原生 Toast：3D 封面降级提示（Dart 侧无法可靠弹出系统 toast）
                "showToast" -> {
                    val msg = call.argument<String>("message") ?: ""
                    mainHandler.post {
                        try {
                            Toast.makeText(hostActivity, msg, Toast.LENGTH_LONG).show()
                        } catch (t: Throwable) {
                            Log.w(TAG, "showToast failed: $t")
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 从 APK 资产提取模型到应用目录（`files/depth_model/<文件名>`）。
     * 已存在且字节数匹配则直接复用；提取先写 .part 再 rename（原子落盘），
     * 大小不符视为损坏并抛错（调用方负责删除半成品以便重试）。
     */
    private fun extractModelAsset(activity: Activity, assetPath: String): String {
        val target = File(activity.filesDir, "depth_model/${assetPath.substringAfterLast('/')}")
        if (target.exists() && target.length() == MODEL_BYTES) {
            return target.absolutePath
        }
        val part = File(target.parentFile, "${target.name}.part")
        activity.assets.open(assetPath).use { input ->
            FileOutputStream(part).use { output -> input.copyTo(output, 1 shl 20) }
        }
        if (part.length() != MODEL_BYTES) {
            val actual = part.length()
            part.delete()
            throw IllegalStateException("asset extract size mismatch: expect=$MODEL_BYTES actual=$actual")
        }
        if (target.exists()) target.delete()
        if (!part.renameTo(target)) {
            throw IllegalStateException("rename failed: ${part.absolutePath}")
        }
        Log.d(TAG, "extractModelAsset OK: ${target.absolutePath}")
        return target.absolutePath
    }

    private fun generate(
        session: OrtSession,
        sourcePath: String,
        sourceBytes: ByteArray?,
        outDir: String,
        key: String,
    ): Map<String, Any> {
        val src = BitmapFactory.decodeFile(sourcePath)
            ?: (if (sourceBytes != null) BitmapFactory.decodeByteArray(sourceBytes, 0, sourceBytes.size) else null)
            ?: throw IllegalStateException("cannot decode cover")
        val out = File(outDir).apply { mkdirs() }

        // 1) 推理 + min-max 归一化到 0..1（值越大越近）
        val norm = normalize(infer(session, src))

        // 2) 深度带切割：layer0=远(背景) layer2=近(前景)，平滑羽化避免硬边
        val paths = ArrayList<String>(3)
        for ((li, band) in BANDS.withIndex()) {
            val layer = splitLayer(src, norm, band[0], band[1])
            val f = File(out, "layer$li.png") // 修正：固定文件名 layer{i}.png
            FileOutputStream(f).use { layer.compress(Bitmap.CompressFormat.PNG, 100, it) }
            paths.add(f.absolutePath)
            layer.recycle()
        }
        src.recycle()
        return mapOf("layers" to paths)
    }

    /** min-max 归一化到 0..1（值越大越近）。 */
    private fun normalize(depth: FloatArray): FloatArray {
        var min = Float.MAX_VALUE
        var max = -Float.MAX_VALUE
        for (v in depth) {
            if (v < min) min = v
            if (v > max) max = v
        }
        val range = (max - min).coerceAtLeast(1e-6f)
        return FloatArray(depth.size) { (depth[it] - min) / range }
    }

    /** 深度图标准差（stride 采样，ShengChao computeDepthStd 同款）。 */
    private fun depthStd(norm: FloatArray): Float {
        var sum = 0f
        var sumSq = 0f
        var n = 0f
        var i = 0
        while (i < norm.size) {
            val v = norm[i]
            sum += v
            sumSq += v * v
            n += 1f
            i += 4
        }
        if (n == 0f) return 0.18f
        val mean = sum / n
        val variance = (sumSq / n - mean * mean).coerceAtLeast(0f)
        return kotlin.math.sqrt(variance)
    }

    /**
     * 深度在 [lo,hi] 带内的像素保留，带外按 [FEATHER] 线性羽化为透明。
     * 输出保持封面原分辨率；norm 为推理分辨率(DEPTH_SIZE x DEPTH_SIZE)的摊平结果，
     * 按 (x,y) 遍历 src 时把坐标最近邻映射回深度网格取深度。
     */
    private fun splitLayer(src: Bitmap, norm: FloatArray, lo: Float, hi: Float): Bitmap {
        val w = src.width
        val h = src.height
        val pixels = IntArray(w * h)
        src.getPixels(pixels, 0, w, 0, 0, w, h)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val i = y * w + x
                val dx = (x * DEPTH_SIZE / w).coerceAtMost(DEPTH_SIZE - 1)
                val dy = (y * DEPTH_SIZE / h).coerceAtMost(DEPTH_SIZE - 1)
                val d = norm[dy * DEPTH_SIZE + dx]
                val a = when {
                    d < lo - FEATHER || d > hi + FEATHER -> 0f
                    d < lo -> (d - (lo - FEATHER)) / FEATHER
                    d > hi -> ((hi + FEATHER) - d) / FEATHER
                    else -> 1f
                }
                if (a <= 0f) {
                    pixels[i] = Color.TRANSPARENT
                } else if (a < 1f) {
                    pixels[i] = (pixels[i] and 0x00FFFFFF) or ((a * 255f).toInt() shl 24)
                }
            }
        }
        return Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
    }

    private fun infer(session: OrtSession, src: Bitmap): FloatArray {
        val scaled = Bitmap.createScaledBitmap(src, DEPTH_SIZE, DEPTH_SIZE, true)
        try {
            val pixels = IntArray(DEPTH_SIZE * DEPTH_SIZE)
            scaled.getPixels(pixels, 0, DEPTH_SIZE, 0, 0, DEPTH_SIZE, DEPTH_SIZE)
            // NCHW float 输入
            val data = FloatArray(3 * DEPTH_SIZE * DEPTH_SIZE)
            for (c in 0..2) {
                val plane = c * DEPTH_SIZE * DEPTH_SIZE
                for (i in pixels.indices) {
                    val px = pixels[i]
                    val v = when (c) {
                        0 -> (px shr 16 and 0xFF) / 255f
                        1 -> (px shr 8 and 0xFF) / 255f
                        else -> (px and 0xFF) / 255f
                    }
                    data[plane + i] = (v - MEAN[c]) / STD[c]
                }
            }
            val shape = longArrayOf(1, 3, DEPTH_SIZE.toLong(), DEPTH_SIZE.toLong())
            val e = env ?: OrtEnvironment.getEnvironment().also { env = it }
            val inputName = session.inputNames.first() // 运行时取输入名
            OnnxTensor.createTensor(e, FloatBuffer.wrap(data), shape).use { tensor ->
                session.run(mapOf(inputName to tensor)).use { out ->
                    val outTensor = out[0] as OnnxTensor
                    // 运行时读取真实输出形状，数据摊平为 FloatArray（兼容 (1,1,H,W) 与 (1,H,W)）
                    val realShape = outTensor.info.shape
                    Log.d("DepthCover", "output shape=${realShape.contentToString()}")
                    val fb = outTensor.floatBuffer
                    val flat = FloatArray(fb.remaining())
                    fb.get(flat)
                    return flat
                }
            }
            throw IllegalStateException("unreachable")
        } finally {
            scaled.recycle()
        }
    }
}
