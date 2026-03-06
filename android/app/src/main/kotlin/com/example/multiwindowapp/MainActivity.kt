package com.example.multiwindowapp

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var secondDisplayPlugin: SecondDisplayPlugin

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        secondDisplayPlugin = SecondDisplayPlugin(applicationContext)
        secondDisplayPlugin.register(
            MethodChannel(
                flutterEngine!!.dartExecutor.binaryMessenger,
                "second_display"
            )
        )
    }

    override fun onDestroy() {
        secondDisplayPlugin.dispose()
        super.onDestroy()
    }
}
