# WordWidget (Flutter)

WordWidget is a vocabulary learning app with home and lock screen widgets. It teaches English words with Turkish meanings, examples, and optional pronunciation.

## Features

- CEFR vocabulary levels: A1, A2, B1, B2
- Widget-driven word learning flow
- Home screen: Today's word + quick actions
- Learned words tracker
- Quiz system (word->meaning and meaning->word)
- Level progression with pass threshold (70%)
- Local persistence for progress and scores
- Dark mode support
- API enrichment hooks for pronunciation/examples

## Architecture

- `lib/core`: entities/models and common definitions
- `lib/data`: local repositories for words and progress
- `lib/services`: integrations (widgets, dictionary API)
- `lib/state`: app state management with `ChangeNotifier`
- `lib/ui`: screens and reusable UI components

This keeps UI, logic, and data access separated.

## Setup

1. Install Flutter (stable channel).
2. From this folder run:
   - `flutter pub get`
   - `flutter create .` (if platform folders are incomplete on your machine)
3. Run app:
   - iOS: `flutter run -d ios`
   - Android: `flutter run -d android`

## Widget Setup

### Flutter bridge
The app uses [`home_widget`](https://pub.dev/packages/home_widget) to share data and trigger widget refreshes.

### iOS WidgetKit
- Place Swift files from `ios/WidgetExtension` into an iOS widget extension target.
- Use the same App Group in app + extension.
- Update `group.com.example.wordwidget` in both targets.

### Android AppWidget
- Add files from `android/app/src/main/...` into your Android app module.
- Register receiver in `AndroidManifest.xml`.
- Ensure package name matches your real app ID.

## Dictionary API (Optional)
`DictionaryService` includes an online enrichment method using a free dictionary endpoint. If API data is unavailable, local JSON data is used.

## Testing checklist

- Change word from app updates widget
- Mark words learned and confirm persistence after restart
- Pass/fail level test updates unlocked level correctly
- Quiz score is tracked and shown on level screen
- Dark mode visuals are readable
