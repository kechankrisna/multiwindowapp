package com.example.multiwindowapp

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Manages a secondary Flutter engine that renders on the second physical display.
 *
 * Architecture:
 *   Main FlutterEngine (MainActivity)
 *     MethodChannel("second_display")  ← Dart calls arrive here
 *       SecondDisplayPlugin bridges to →
 *     Second FlutterEngine (sub_screen_entry.dart → subScreenMain())
 *       MethodChannel("sub_screen_commands")  ← state pushed to sub-screen Dart
 *
 * Optimisations:
 *  - Second engine is created lazily only when a Presentation display is detected.
 *  - FlutterEngineCache prevents double-initialisation.
 *  - initSecondDisplay() is guarded by `if (subEngine != null) return`.
 *  - FlutterView.detachFromFlutterEngine() is called before engine destroy to
 *    avoid use-after-free.
 */
class SecondDisplayPlugin(private val context: Context) : DisplayManager.DisplayListener {

    companion object {
        private const val CHANNEL = "second_display"
        private const val SUB_CHANNEL = "sub_screen_commands"
        private const val ENGINE_ID = "sub_screen_engine"
    }

    private val displayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    // All three are null until a secondary display is connected.
    private var subEngine: FlutterEngine? = null
    private var presentation: SecondDisplayPresentation? = null
    private var subChannel: MethodChannel? = null

    /**
     * Call once from [MainActivity.onCreate].
     * Registers the main MethodChannel and starts watching for display changes.
     */
    fun register(mainChannel: MethodChannel) {
        mainChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSecondDisplayAvailable" ->
                    result.success(getSecondDisplay() != null)

                "sendState" -> {
                    subChannel?.invokeMethod("updateState", call.arguments)
                    result.success(null)
                }

                "releaseSecondDisplay" -> {
                    releaseEngine()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        displayManager.registerDisplayListener(this, null)
        // Initialise immediately if a secondary display is already connected.
        getSecondDisplay()?.let { initSecondDisplay(it) }
    }

    /** Call from [MainActivity.onDestroy] to unregister listeners and free resources. */
    fun dispose() {
        displayManager.unregisterDisplayListener(this)
        releaseEngine()
    }

    // ── DisplayManager.DisplayListener ────────────────────────────────────────

    override fun onDisplayAdded(displayId: Int) {
        displayManager.getDisplay(displayId)?.let { initSecondDisplay(it) }
    }

    override fun onDisplayRemoved(displayId: Int) {
        releaseEngine()
    }

    override fun onDisplayChanged(displayId: Int) {
        // Geometry changes — no action needed for this demo.
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private fun getSecondDisplay(): Display? =
        displayManager
            .getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .firstOrNull()

    private fun initSecondDisplay(display: Display) {
        // Guard: never recreate the engine while it is already running.
        if (subEngine != null) return

        subEngine = FlutterEngine(context).also { engine ->
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "subScreenMain"
                )
            )
            // Cache prevents a second call to this method from re-creating the engine.
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            subChannel = MethodChannel(engine.dartExecutor.binaryMessenger, SUB_CHANNEL)
        }

        presentation = SecondDisplayPresentation(context, display, subEngine!!)
            .also { it.show() }
    }

    private fun releaseEngine() {
        // Detach view before destroying the engine to prevent use-after-free.
        presentation?.detach()
        presentation?.dismiss()
        presentation = null

        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        subEngine?.destroy()
        subEngine = null
        subChannel = null
    }
}

/**
 * An Android [Presentation] window hosting a [FlutterView] backed by the
 * secondary [FlutterEngine]. Shown on the second physical display.
 */
class SecondDisplayPresentation(
    context: Context,
    display: Display,
    private val engine: FlutterEngine,
) : Presentation(context, display) {

    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        flutterView = FlutterView(context).also { view ->
            view.attachToFlutterEngine(engine)
            setContentView(view)
        }
    }

    /** Detach the [FlutterView] from the engine before [dismiss] / engine destroy. */
    fun detach() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
    }
}
