import 'package:home_widget/home_widget.dart';

import '../core/models/vocab_word.dart';

class WidgetService {
  static const appGroupId = 'group.com.example.wordwidget';
  static const iOSWidgetName = 'WordWidgetExtension';
  static const androidWidgetQualifiedName =
      'com.example.wordwidget.WordWidgetProvider';

  Future<void> init() async {
    await HomeWidget.setAppGroupId(appGroupId);
  }

  Future<void> syncWord(VocabWord word) async {
    await HomeWidget.saveWidgetData<String>('word', word.word);
    await HomeWidget.saveWidgetData<String>('meaning', word.meaningTr);
    await HomeWidget.saveWidgetData<String>('example', word.example);
    await HomeWidget.saveWidgetData<String>('imageUrl', word.imageUrl);
    await HomeWidget.saveWidgetData<String>('audioUrl', word.audioUrl ?? '');

    await HomeWidget.updateWidget(
      iOSName: iOSWidgetName,
      androidName: androidWidgetQualifiedName,
    );
  }
}
