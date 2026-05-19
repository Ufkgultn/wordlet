package com.example.wordwidget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class WordWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, widgetId)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val word = widgetData.getString("word", "word")
            val meaning = widgetData.getString("meaning", "anlam")
            val example = widgetData.getString("example", "example sentence")

            val views = RemoteViews(context.packageName, R.layout.word_widget_layout)
            views.setTextViewText(R.id.widgetWord, word)
            views.setTextViewText(R.id.widgetMeaning, meaning)
            views.setTextViewText(R.id.widgetExample, example)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
