package com.arbenger.botler

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

// The quick-add widget: one tap opens Botler on the expense box (botler://quickadd). The widget shows no amounts: it only holds a button.
class QuickAddWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.quick_add_widget).apply {
                val pending = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("botler://quickadd")
                )
                setOnClickPendingIntent(R.id.quick_add_root, pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
