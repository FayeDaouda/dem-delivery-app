package sn.dem.demapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                "dem_orders",
                "Courses DEM",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Nouvelles courses, acceptations, livraisons"
                enableVibration(true)
                enableLights(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dem/config")
            .setMethodCallHandler { call, result ->
                if (call.method == "getMapsApiKey") {
                    result.success(BuildConfig.MAPS_HTTP_API_KEY)
                } else {
                    result.notImplemented()
                }
            }
    }
}
