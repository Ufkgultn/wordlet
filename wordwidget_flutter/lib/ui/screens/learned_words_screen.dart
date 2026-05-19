import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

class LearnedWordsScreen extends StatelessWidget {
  const LearnedWordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final words = appState.wordsForCurrentLevel();

    return Scaffold(
      appBar: AppBar(title: const Text('Learned Words')),
      body: ListView.builder(
        itemCount: words.length,
        itemBuilder: (context, index) {
          final word = words[index];
          final learned = appState.progress.learnedWordIds.contains(word.word);
          return CheckboxListTile(
            value: learned,
            onChanged: (value) {
              context.read<AppState>().markLearned(word.word, value ?? false);
            },
            title: Text(word.word),
            subtitle: Text('${word.meaningTr} • ${word.example}'),
          );
        },
      ),
    );
  }
}
