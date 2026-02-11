package com.example.gt06_gateway

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.gt06_gateway/service"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
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
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}