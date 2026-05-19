# Widget Integration Notes

## Android

1. Register provider in `android/app/src/main/AndroidManifest.xml`:

```xml
<receiver
    android:name=".WordWidgetProvider"
    android:exported="false">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/word_widget_info" />
</receiver>
```

2. Ensure package matches your app package.
3. Add `home_widget` initialization in Flutter (already done in `WidgetService`).

## iOS

1. Create a Widget Extension target.
2. Add `ios/WidgetExtension/WordWidget.swift` content into extension target.
3. Configure both app and extension with App Group:
   - `group.com.example.wordwidget`
4. Keep widget kind name aligned with Flutter update call:
   - `WordWidgetExtension`

## Data keys

Flutter writes these keys to shared storage:
- `word`
- `meaning`
- `example`
- `imageUrl`
- `audioUrl`
