import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final word = appState.todayWord;

    return Scaffold(
      appBar: AppBar(title: const Text('WordWidget')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today\'s Word',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: word == null
                    ? const Text('No words found for this level.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            word.word,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text('TR: ${word.meaningTr}'),
                          const SizedBox(height: 8),
                          Text(word.example),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => context.read<AppState>().changeWord(),
                            child: const Text('Change Word'),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => Navigator.pushNamed(context, '/learned'),
                  child: const Text('Review Words'),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.pushNamed(context, '/quiz'),
                  child: const Text('Start Quiz'),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.pushNamed(context, '/level'),
                  child: const Text('My Level'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
