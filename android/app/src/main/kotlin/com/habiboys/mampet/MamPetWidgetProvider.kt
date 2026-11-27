package com.habiboys.mampet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.widget.RemoteViews

class MamPetWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateSingleWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_PET_INTERACT) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val nextIdx = (prefs.getInt("pet_mood_index", 0) + 1) % MOOD_QUOTES.size
            prefs.edit().putInt("pet_mood_index", nextIdx).apply()
            updateAllWidgets(context)
        }
    }

    companion object {
        const val PREFS_NAME = "mampet_home_widget"
        const val ACTION_PET_INTERACT = "com.habiboys.mampet.ACTION_PET_INTERACT"

        private val MOOD_QUOTES = arrayOf(
            "Yuk catat makan hari ini!",
            "Hehe geli! Elus lagi dong ♥",
            "Makan enak apa kita hari ini?",
            "Semangat! Ayo isi FoodDex!",
            "Yeay, main bareng terus ya!"
        )

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, MamPetWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids != null && ids.isNotEmpty()) {
                for (id in ids) {
                    updateSingleWidget(context, manager, id)
                }
            }
        }

        private fun updateSingleWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val name = prefs.getString("pet_name", "Foxili") ?: "Foxili"
            val level = prefs.getInt("pet_level", 1)
            val phase = prefs.getString("pet_phase", "Baby") ?: "Baby"
            val assetPath = prefs.getString("pet_asset", "assets/monsters/fox/baby.png")
                ?: "assets/monsters/fox/baby.png"
            val xpPercent = prefs.getInt("pet_xp_percent", 0).coerceIn(0, 100)
            val bond = prefs.getInt("pet_bond", 0)
            val moodIdx = prefs.getInt("pet_mood_index", 0).coerceIn(0, MOOD_QUOTES.lastIndex)
            val reduceMotion = prefs.getBoolean("reduce_motion", false)

            val views = RemoteViews(context.packageName, R.layout.mampet_pet_widget)
            views.setTextViewText(R.id.widget_pet_name, name)
            views.setTextViewText(R.id.widget_pet_level, "Lv $level")
            views.setTextViewText(R.id.widget_pet_speech, MOOD_QUOTES[moodIdx])
            views.setTextViewText(R.id.widget_pet_meta, "$phase • ♥ $bond/100")
            views.setProgressBar(R.id.widget_xp_bar, 100, xpPercent, false)

            // Decode pet sprite from Flutter's bundled assets
            val baseBitmap = loadFlutterAssetBitmap(context, assetPath)
            if (baseBitmap != null) {
                val frameIds = intArrayOf(
                    R.id.pet_frame_0,
                    R.id.pet_frame_1,
                    R.id.pet_frame_2,
                    R.id.pet_frame_3
                )
                for (i in frameIds.indices) {
                    val frameBmp = if (reduceMotion) {
                        renderPetFrame(baseBitmap, 0f, 0f, 0f, 1.0f, showHeart = false, showSparkle = false)
                    } else {
                        when (i) {
                            0 -> renderPetFrame(baseBitmap, dx = -12f, dy = -4f, degrees = -4.5f, scale = 0.99f, showHeart = false, showSparkle = false)
                            1 -> renderPetFrame(baseBitmap, dx = 0f, dy = -16f, degrees = 0f, scale = 1.04f, showHeart = false, showSparkle = true)
                            2 -> renderPetFrame(baseBitmap, dx = 12f, dy = -4f, degrees = 4.5f, scale = 0.99f, showHeart = false, showSparkle = false)
                            else -> renderPetFrame(baseBitmap, dx = 0f, dy = -6f, degrees = -1.5f, scale = 1.01f, showHeart = true, showSparkle = false)
                        }
                    }
                    views.setImageViewBitmap(frameIds[i], frameBmp)
                }
                baseBitmap.recycle()
            }

            // Tap pet -> cycle playful mood speech bubble & refresh animation!
            val petTapIntent = Intent(context, MamPetWidgetProvider::class.java).apply {
                action = ACTION_PET_INTERACT
            }
            val petPendingIntent = PendingIntent.getBroadcast(
                context,
                appWidgetId + 1000,
                petTapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.pet_stage_container, petPendingIntent)

            // Tap card / CTA -> open MamPet app
            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openPendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, openPendingIntent)
            views.setOnClickPendingIntent(R.id.widget_open_cta, openPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun loadFlutterAssetBitmap(context: Context, assetPath: String): Bitmap? {
            return try {
                val flutterKey = "flutter_assets/$assetPath"
                context.assets.open(flutterKey).use { stream ->
                    BitmapFactory.decodeStream(stream)
                }
            } catch (_: Exception) {
                try {
                    context.assets.open("flutter_assets/assets/branding/mampet_logo.png").use { stream ->
                        BitmapFactory.decodeStream(stream)
                    }
                } catch (_: Exception) {
                    null
                }
            }
        }

        private fun renderPetFrame(
            source: Bitmap,
            dx: Float,
            dy: Float,
            degrees: Float,
            scale: Float,
            showHeart: Boolean,
            showSparkle: Boolean
        ): Bitmap {
            val canvasSize = 220
            val out = Bitmap.createBitmap(canvasSize, canvasSize, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)

            // Soft cozy ground shadow oval
            val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.argb(34, 45, 32, 27)
            }
            val shadowShrink = if (dy < -10f) 0.82f else 1.0f
            val shadowW = 110f * shadowShrink
            val shadowCx = canvasSize / 2f + dx * 0.7f
            canvas.drawOval(
                RectF(shadowCx - shadowW / 2f, 186f, shadowCx + shadowW / 2f, 206f),
                shadowPaint
            )

            // Draw scaled + tilted + hopped pet
            val targetSize = 166f * scale
            val sx = targetSize / source.width.toFloat()
            val sy = targetSize / source.height.toFloat()
            val matrix = Matrix().apply {
                postScale(sx, sy)
                postTranslate(-targetSize / 2f, -targetSize / 2f)
                postRotate(degrees)
                postTranslate(canvasSize / 2f + dx, canvasSize / 2f + 10f + dy)
            }
            val bmpPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            canvas.drawBitmap(source, matrix, bmpPaint)

            // Cute golden sparkle star on jump frame
            if (showSparkle) {
                val sparkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#F5A623")
                }
                canvas.drawCircle(176f, 38f, 9f, sparkPaint)
                canvas.drawCircle(192f, 56f, 5f, sparkPaint)
            }

            // Cute pink floating mini heart on happy frame
            if (showHeart) {
                val heartPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#F43F5E")
                    textSize = 34f
                    textAlign = Paint.Align.CENTER
                }
                canvas.drawText("♥", 174f, 44f, heartPaint)
            }

            return out
        }
    }
}
