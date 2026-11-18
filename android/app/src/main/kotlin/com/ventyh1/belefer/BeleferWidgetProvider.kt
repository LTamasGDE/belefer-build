package com.ventyh1.belefer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Kezdőképernyő-widget: a hónap egyenlege, bevétele, kiadása és a következő
 * esedékes tétel; gyorsrögzítés és blokkfotózás egy koppintással.
 *
 * Az adatokat az alkalmazás írja (home_widget, `belefer_*` kulcsok).
 */
class BeleferWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.belefer_widget)
            val month = widgetData.getString("belefer_month", null)
            if (month == null) {
                views.setTextViewText(R.id.widget_month, "Belefér")
                views.setTextViewText(R.id.widget_balance, "Nyisd meg az appot")
                views.setTextViewText(R.id.widget_income, "")
                views.setTextViewText(R.id.widget_expense, "")
                views.setViewVisibility(R.id.widget_next, View.GONE)
            } else {
                val negative = widgetData.getString("belefer_negative", "0") == "1"
                views.setTextViewText(R.id.widget_month, "Belefér · $month")
                views.setTextViewText(
                    R.id.widget_balance,
                    widgetData.getString("belefer_balance", "") ?: "",
                )
                views.setTextColor(
                    R.id.widget_balance,
                    if (negative) Color.parseColor("#FFFF8178") else Color.parseColor("#FFF6F0E5"),
                )
                views.setTextViewText(
                    R.id.widget_income,
                    "↓ " + (widgetData.getString("belefer_income", "") ?: ""),
                )
                views.setTextViewText(
                    R.id.widget_expense,
                    "↑ " + (widgetData.getString("belefer_expense", "") ?: ""),
                )
                val next = widgetData.getString("belefer_next", "") ?: ""
                if (next.isEmpty()) {
                    views.setViewVisibility(R.id.widget_next, View.GONE)
                } else {
                    views.setViewVisibility(R.id.widget_next, View.VISIBLE)
                    views.setTextViewText(R.id.widget_next, "Következő: $next")
                }
            }
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("belefer://attekintes"),
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_quick,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("belefer://gyors"),
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_scan,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("belefer://blokk"),
                ),
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
