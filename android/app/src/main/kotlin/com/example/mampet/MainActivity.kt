package com.example.mampet

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val widgetChannelName = "com.mampet.app/home_widget"
    private val shareChannelName = "com.mampet.app/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updatePetWidget" -> {
                        val prefs = getSharedPreferences(
                            MamPetWidgetProvider.PREFS_NAME,
                            Context.MODE_PRIVATE
                        )
                        val editor = prefs.edit()
                        call.argument<String>("name")?.let { editor.putString("pet_name", it) }
                        call.argument<Int>("level")?.let { editor.putInt("pet_level", it) }
                        call.argument<String>("phase")?.let { editor.putString("pet_phase", it) }
                        call.argument<String>("assetPath")?.let { editor.putString("pet_asset", it) }
                        call.argument<Int>("xpPercent")?.let { editor.putInt("pet_xp_percent", it) }
                        call.argument<Int>("bond")?.let { editor.putInt("pet_bond", it) }
                        call.argument<Boolean>("reduceMotion")?.let {
                            editor.putBoolean("reduce_motion", it)
                        }
                        editor.apply()

                        MamPetWidgetProvider.updateAllWidgets(applicationContext)
                        result.success(true)
                    }

                    "requestPinWidget" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val appWidgetManager = AppWidgetManager.getInstance(applicationContext)
                            val provider = ComponentName(
                                applicationContext,
                                MamPetWidgetProvider::class.java
                            )
                            if (appWidgetManager.isRequestPinAppWidgetSupported) {
                                val pinned = appWidgetManager.requestPinAppWidget(provider, null, null)
                                result.success(pinned)
                            } else {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareToWhatsApp" -> {
                        val text = call.argument<String>("text") ?: ""
                        val photoPath = call.argument<String>("photoPath")
                        val opened = tryLaunchWhatsApp(text, photoPath)
                        result.success(opened)
                    }

                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun findWhatsAppPackage(): String? {
        val candidates = listOf("com.whatsapp", "com.whatsapp.w4b")
        for (pkg in candidates) {
            try {
                packageManager.getPackageInfo(pkg, 0)
                return pkg
            } catch (_: Exception) {
                // Not installed
            }
        }
        return null
    }

    private fun tryLaunchWhatsApp(text: String, photoPath: String?): Boolean {
        val waPkg = findWhatsAppPackage() ?: return false
        return try {
            val intent = Intent(Intent.ACTION_SEND)
            intent.setPackage(waPkg)
            intent.putExtra(Intent.EXTRA_TEXT, text)

            if (!photoPath.isNullOrBlank()) {
                val file = File(photoPath)
                if (file.exists()) {
                    val uri = FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.mampet_fileprovider",
                        file
                    )
                    intent.type = "image/*"
                    intent.putExtra(Intent.EXTRA_STREAM, uri)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } else {
                    intent.type = "text/plain"
                }
            } else {
                intent.type = "text/plain"
            }

            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
