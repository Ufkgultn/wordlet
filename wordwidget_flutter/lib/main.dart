import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/local_word_repository.dart';
import 'data/progress_repository.dart';
import 'services/widget_service.dart';
import 'state/app_state.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/learned_words_screen.dart';
import 'ui/screens/level_screen.dart';
import 'ui/screens/quiz_screen.dart';

void main() {
  runApp(const WordWidgetApp());
}

class WordWidgetApp extends StatelessWidget {
  const WordWidgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(
        LocalWordRepository(),
        ProgressRepository(),
        WidgetService(),
      )..init(),
      child: MaterialApp(
        title: 'WordWidget',
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        routes: {
          '/': (_) => const HomeScreen(),
          '/learned': (_) => const LearnedWordsScreen(),
          '/quiz': (_) => const QuizScreen(isLevelTest: false),
          '/level': (_) => const LevelScreen(),
          '/level-test': (_) => const QuizScreen(isLevelTest: true),
        },
      ),
    );
  }
}
