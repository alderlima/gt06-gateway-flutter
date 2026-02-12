package com.example.gt06_gateway

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val SERVICE_CHANNEL = "com.example.gt06_gateway/service"
    private val NAV_CHANNEL = "com.example.gt06_gateway/navigation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Canal para foreground service
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL).setMethodCallHandler {
            call, result ->
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

        // Canal para navegação (botão voltar)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAV_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "moveToBackground" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}