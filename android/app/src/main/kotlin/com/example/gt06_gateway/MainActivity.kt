package com.example.gt06_gateway

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SERVICE_CHANNEL = "com.example.gt06_gateway/service"
    private val NAV_CHANNEL = "com.example.gt06_gateway/navigation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Channel para serviço de foreground
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        ForegroundService.startService(this)
                        result.success(true)
                    }
                    "stopForegroundService" -> {
                        ForegroundService.stopService(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // Channel para minimizar app
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAV_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "minimizeApp" -> {
                        minimizeApp()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun minimizeApp() {
        moveTaskToBack(true)
    }
}