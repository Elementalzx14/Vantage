package com.retrostream.vantage

import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.OnLifecycleEvent


class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {
    
    var keyListener: ((KeyEvent) -> Boolean)? = null
    var motionListener: ((MotionEvent) -> Boolean)? = null

    override fun registerInputDeviceListener(listener: InputManager.InputDeviceListener, handler: Handler?) {
        val inputManager = getSystemService(Context.INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyListener = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionListener = handler
    }

    private val CHANNEL = "com.retrostream.vantage/emulator"
    private var isMappingMode: Boolean = false

    companion object {
        var retroView: com.swordfish.libretrodroid.GLRetroView? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.retrostream.vantage/retro_view",
            RetroViewFactory(this)
        )

        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launch" -> {
                        val romPath    = call.argument<String>("romPath")    ?: return@setMethodCallHandler result.error("MISSING", "romPath required", null)
                        val corePath   = call.argument<String>("corePath")   ?: return@setMethodCallHandler result.error("MISSING", "corePath required", null)
                        val systemPath = call.argument<String>("systemPath")
                        
                        result.success(null)
                    }
                    "getAbi" -> {
                        result.success(android.os.Build.CPU_ABI)
                    }
                    "pause"  -> { retroView?.onPause(); result.success(null) }
                    "resume" -> { retroView?.onResume(); result.success(null) }
                    "reset"  -> { retroView?.reset(); result.success(null) }
                    "getAspectRatio" -> {
                        result.success(4.0 / 3.0)
                    }
                    "saveState" -> {
                        val data = retroView?.serializeState()
                        result.success(data)
                    }
                    "loadState" -> {
                        val data = call.argument<ByteArray>("state")
                        if (data != null && data.isNotEmpty()) {
                            retroView?.unserializeState(data)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "setVolume" -> {
                        
                        val volume = call.arguments as? Double ?: 1.0
                        retroView?.audioEnabled = volume > 0.0
                        result.success(null)
                    }
                    "setFastForward" -> {
                        
                        val enabled = call.arguments as? Boolean ?: false
                        retroView?.frameSpeed = if (enabled) 2 else 1
                        result.success(null)
                    }
                    "setSlowMotion" -> {
                        
                        
                        result.success(null)
                    }
                    "setAnalog" -> {
                        
                        val index = call.argument<Int>("index") ?: 0
                        val id    = call.argument<Int>("id")    ?: 0
                        val value = call.argument<Int>("value") ?: 0
                        val normalized = value / 32767f
                        val source = if (index == 0)
                            com.swordfish.libretrodroid.GLRetroView.MOTION_SOURCE_ANALOG_LEFT
                        else
                            com.swordfish.libretrodroid.GLRetroView.MOTION_SOURCE_ANALOG_RIGHT
                        
                        if (id == 0) {
                            retroView?.sendMotionEvent(source, normalized, 0f, 0)
                        } else {
                            retroView?.sendMotionEvent(source, 0f, normalized, 0)
                        }
                        result.success(null)
                    }
                    "serializeState" -> {
                        val data = retroView?.serializeState()
                        result.success(data)
                    }
                    "unserializeState" -> {
                        val data = call.argument<ByteArray>("data") ?: return@setMethodCallHandler result.error("MISSING","data required",null)
                        retroView?.unserializeState(data)
                        result.success(null)
                    }
                    "keyDown" -> {
                        val keyCode = call.argument<Int>("keyCode") ?: 0
                        retroView?.sendKeyEvent(KeyEvent.ACTION_DOWN, keyCode)
                        result.success(null)
                    }
                    "keyUp" -> {
                        val keyCode = call.argument<Int>("keyCode") ?: 0
                        retroView?.sendKeyEvent(KeyEvent.ACTION_UP, keyCode)
                        result.success(null)
                    }
                    "httpGet" -> {
                        val url   = call.argument<String>("url") ?: return@setMethodCallHandler result.error("MISSING","url",null)
                        val token = call.argument<String>("token") ?: ""
                        Thread {
                            try {
                                val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                                conn.setRequestProperty("Authorization", "MediaBrowser Token=\"\$token\"")
                                if (conn.responseCode == 404) { result.success(null); return@Thread }
                                val bytes = conn.inputStream.readBytes()
                                result.success(bytes)
                            } catch (e: Exception) { result.error("HTTP_ERROR", e.message, null) }
                        }.start()
                    }
                    "httpPost" -> {
                        val url         = call.argument<String>("url") ?: return@setMethodCallHandler result.error("MISSING","url",null)
                        val token       = call.argument<String>("token") ?: ""
                        val data        = call.argument<ByteArray>("data") ?: ByteArray(0)
                        val contentType = call.argument<String>("contentType") ?: "application/octet-stream"
                        Thread {
                            try {
                                val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                                conn.requestMethod = "POST"
                                conn.setRequestProperty("Authorization", "MediaBrowser Token=\"\$token\"")
                                conn.setRequestProperty("Content-Type", contentType)
                                conn.doOutput = true
                                conn.outputStream.write(data)
                                if (conn.responseCode !in 200..299) throw Exception("HTTP \${conn.responseCode}")
                                result.success(null)
                            } catch (e: Exception) { result.error("HTTP_ERROR", e.message, null) }
                        }.start()
                    }
                    "setMappingMode" -> {
                        val mode = call.argument<Boolean>("mode") ?: false
                        isMappingMode = mode
                        result.success(null)
                    }
                    "resetMappingMode" -> {
                        isMappingMode = false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isNavKey = when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_ENTER -> true
            else -> false
        }

        if (isNavKey) {
            return super.dispatchKeyEvent(event)
        }

        val handled = keyListener?.invoke(event) ?: false
        return if (handled) true else super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val handled = motionListener?.invoke(event) ?: false
        if (handled) return true
        return super.dispatchGenericMotionEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (!isMappingMode && retroView?.onKeyDown(keyCode, event) == true) return true
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (!isMappingMode && retroView?.onKeyUp(keyCode, event) == true) return true
        return super.onKeyUp(keyCode, event)
    }
}




class RetroViewFactory(private val activity: android.app.Activity) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<String, Any?>
        val romPath = params?.get("romPath") as? String ?: ""
        val corePath = params?.get("corePath") as? String ?: ""
        val systemPath = params?.get("systemPath") as? String
        
        android.util.Log.d("VantageNative", "Creating RetroView with ROM: $romPath, Core: $corePath")
        
        return RetroViewWrapper(context, activity, romPath, corePath, systemPath)
    }
}

class SimpleLifecycleOwner : androidx.lifecycle.LifecycleOwner {
    private val lifecycleRegistry = androidx.lifecycle.LifecycleRegistry(this)
    
    override val lifecycle: androidx.lifecycle.Lifecycle
        get() = lifecycleRegistry
    
    fun handleLifecycleEvent(event: androidx.lifecycle.Lifecycle.Event) {
        lifecycleRegistry.handleLifecycleEvent(event)
    }
}

class RetroViewWrapper(
    private val context: Context,
    private val activity: android.app.Activity,
    private val romPath: String,
    private val corePath: String,
    private val systemPath: String?
) : PlatformView {

    private val customLifecycleOwner = SimpleLifecycleOwner()
    private var activityLifecycleObserver: androidx.lifecycle.LifecycleObserver? = null

    private val internalRetroView: com.swordfish.libretrodroid.GLRetroView by lazy {
        val savesDir = java.io.File(activity.filesDir, "saves").also { it.mkdirs() }
        val coreName = java.io.File(corePath).nameWithoutExtension
        
        try {
            activity.filesDir.walkTopDown().forEach {
                if (it.isFile) {
                    android.util.Log.d("VantageFiles", "Found file: ${it.absolutePath} (size: ${it.length()})")
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("VantageFiles", "Failed to walk filesDir", e)
        }
        
        val optFiles = listOf(
            java.io.File(savesDir, "$coreName.opt"),
            java.io.File(activity.filesDir, "$coreName.opt"),
            java.io.File(savesDir, "${coreName.replace("_android", "")}.opt"),
            java.io.File(activity.filesDir, "${coreName.replace("_android", "")}.opt")
        )
        
        val optContent = """
            mupen64plus-EnableFBEmulation = "False"
            mupen64plus-next-EnableFBEmulation = "False"
            mupen64plus-rdp-plugin = "gliden64"
            mupen64plus-next-rdp-plugin = "gliden64"
            mupen64plus-rsp-plugin = "hle"
            mupen64plus-next-rsp-plugin = "hle"
            mupen64plus-aspect = "4:3"
            mupen64plus-next-aspect = "4:3"
            mupen64plus-GLideN64Format = "RGBA8888"
            mupen64plus-next-GLideN64Format = "RGBA8888"
            mupen64plus-CopyDepthToRDRAM = "Software"
            mupen64plus-next-CopyDepthToRDRAM = "Software"
            mupen64plus-CopyColorToRDRAM = "Off"
            mupen64plus-next-CopyColorToRDRAM = "Off"
            mupen64plus-ThreadedRenderer = "False"
            mupen64plus-next-ThreadedRenderer = "False"
        """.trimIndent()
        
        for (optFile in optFiles) {
            try {
                optFile.writeText(optContent)
                android.util.Log.d("VantageNative", "Successfully wrote libretro opt file: ${optFile.absolutePath}")
            } catch (e: Exception) {
                android.util.Log.e("VantageNative", "Failed to write opt file: ${optFile.absolutePath}", e)
            }
        }

        try {
            android.util.Log.d("VantageReflection", "--- GLRetroViewData Fields ---")
            com.swordfish.libretrodroid.GLRetroViewData::class.java.declaredFields.forEach {
                android.util.Log.d("VantageReflection", "Field: ${it.name} (${it.type})")
            }
            android.util.Log.d("VantageReflection", "--- GLRetroViewData Methods ---")
            com.swordfish.libretrodroid.GLRetroViewData::class.java.declaredMethods.forEach {
                android.util.Log.d("VantageReflection", "Method: ${it.name} -> ${it.returnType}")
            }
            android.util.Log.d("VantageReflection", "--- GLRetroView Fields ---")
            com.swordfish.libretrodroid.GLRetroView::class.java.declaredFields.forEach {
                android.util.Log.d("VantageReflection", "Field: ${it.name} (${it.type})")
            }
        } catch (e: Exception) {
            android.util.Log.e("VantageReflection", "Reflection failed", e)
        }

        val data = com.swordfish.libretrodroid.GLRetroViewData(context).apply {
            coreFilePath    = corePath
            gameFilePath    = romPath
            shader          = com.swordfish.libretrodroid.ShaderConfig.Sharp
            systemDirectory = systemPath ?: java.io.File(activity.filesDir, "system").also { it.mkdirs() }.absolutePath
            savesDirectory  = savesDir.absolutePath
            skipDuplicateFrames = false
        }
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            activity.runOnUiThread {
                try {
                    activity.window?.apply {
                        val layoutParams = attributes
                        layoutParams.preferredRefreshRate = 60.0f
                        attributes = layoutParams
                    }
                    android.util.Log.d("VantageNative", "Successfully requested 60Hz display refresh rate")
                } catch (e: Exception) {
                    android.util.Log.e("VantageNative", "Failed to request 60Hz refresh rate", e)
                }
            }
        }
        
        val view = com.swordfish.libretrodroid.GLRetroView(context, data)
        view.setZOrderMediaOverlay(true)
        view.layoutParams = android.widget.FrameLayout.LayoutParams(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.Gravity.CENTER
        )
        
        view.isFocusable = false
        view.isFocusableInTouchMode = false
        
        MainActivity.retroView = view

        customLifecycleOwner.lifecycle.addObserver(view)
        
        customLifecycleOwner.handleLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_CREATE)
        
        try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            val openGLESVersion = if (activityManager.deviceConfigurationInfo.reqGlEsVersion >= 0x30000) 3 else 2
            
            val shaderConstructor = Class.forName("com.swordfish.libretrodroid.GLRetroShader")
                .getConstructor(Int::class.javaPrimitiveType, java.util.Map::class.java)
            val shaderConfig = shaderConstructor.newInstance(com.swordfish.libretrodroid.LibretroDroid.SHADER_SHARP, emptyMap<String, String>())
            
            val createMethod = com.swordfish.libretrodroid.LibretroDroid::class.java.getDeclaredMethod(
                "create",
                Int::class.javaPrimitiveType,
                String::class.java,
                String::class.java,
                String::class.java,
                Array<com.swordfish.libretrodroid.Variable>::class.java,
                Class.forName("com.swordfish.libretrodroid.GLRetroShader"),
                Float::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
                Class.forName("com.swordfish.libretrodroid.ImmersiveMode"),
                String::class.java
            )
            
            createMethod.invoke(
                null,
                openGLESVersion,
                data.coreFilePath,
                data.systemDirectory,
                data.savesDirectory,
                data.variables,
                shaderConfig,
                60.0f,
                data.preferLowLatencyAudio,
                data.gameVirtualFiles.isNotEmpty(),
                data.enableMicrophone,
                data.skipDuplicateFrames,
                data.immersiveMode,
                java.util.Locale.getDefault().language
            )
            android.util.Log.d("VantageNative", "Successfully forced LibretroDroid to initialize with 60.0Hz timing override")
        } catch (e: Exception) {
            android.util.Log.e("VantageNative", "Failed to force 60Hz LibretroDroid override", e)
        }

        customLifecycleOwner.handleLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_RESUME)

        val observer = object : androidx.lifecycle.LifecycleObserver {
            @androidx.lifecycle.OnLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_PAUSE)
            fun onPause() {
                customLifecycleOwner.handleLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_PAUSE)
            }
            
            @androidx.lifecycle.OnLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_RESUME)
            fun onResume() {
                customLifecycleOwner.handleLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_RESUME)
            }
        }
        activityLifecycleObserver = observer
        if (activity is androidx.lifecycle.LifecycleOwner) {
            activity.lifecycle.addObserver(observer)
        }

        view
    }

    override fun getView(): android.view.View = internalRetroView
    override fun dispose() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            activity.runOnUiThread {
                try {
                    activity.window?.apply {
                        val layoutParams = attributes
                        layoutParams.preferredRefreshRate = 0.0f
                        attributes = layoutParams
                    }
                    android.util.Log.d("VantageNative", "Successfully restored default system display refresh rate")
                } catch (e: Exception) {
                    android.util.Log.e("VantageNative", "Failed to restore display refresh rate", e)
                }
            }
        }
        
        activityLifecycleObserver?.let { observer ->
            if (activity is androidx.lifecycle.LifecycleOwner) {
                activity.lifecycle.removeObserver(observer)
            }
            activityLifecycleObserver = null
        }
        
        try {
            val field = com.swordfish.libretrodroid.GLRetroView::class.java.getDeclaredField("isEmulationReady")
            field.isAccessible = true
            field.set(internalRetroView, false)
        } catch (e: Exception) {
            android.util.Log.e("VantageNative", "Reflection failed to force stop emulation frames", e)
        }
        
        customLifecycleOwner.handleLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_PAUSE)
        
        customLifecycleOwner.handleLifecycleEvent(androidx.lifecycle.Lifecycle.Event.ON_DESTROY)
        customLifecycleOwner.lifecycle.removeObserver(internalRetroView)
        
        if (MainActivity.retroView == internalRetroView) {
            MainActivity.retroView = null
        }
    }
}

