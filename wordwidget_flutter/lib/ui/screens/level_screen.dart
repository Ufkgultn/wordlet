import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

class LevelScreen extends StatelessWidget {
  const LevelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scores = appState.progress.quizScores;

    return Scaffold(
      appBar: AppBar(title: const Text('My Level')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current level: ${appState.currentLevel.key}'),
            const SizedBox(height: 8),
            Text('Learned words: ${appState.progress.learnedWordIds.length}'),
            const SizedBox(height: 12),
            Text('Recent quiz scores: ${scores.isEmpty ? '-' : scores.join(', ')}'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pushNamed(context, '/level-test'),
              child: const Text('Take Level Test (70% to pass)'),
            ),
          ],
        ),
      ),
    );
  }
}
