import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vocab_word.dart';
import '../../state/app_state.dart';

class QuizQuestion {
  QuizQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.isLevelTest});

  final bool isLevelTest;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final Random _random = Random();
  late List<QuizQuestion> _questions;
  int _index = 0;
  int _correct = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final words = context.read<AppState>().wordsForCurrentLevel();
    _questions = _buildQuestions(words, widget.isLevelTest ? 10 : 5);
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return const Scaffold(body: Center(child: Text('Not enough words for quiz.')));
    }

    final current = _questions[_index];
    final progress = ((_index + 1) / _questions.length * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isLevelTest ? 'Level Test' : 'Quiz'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progress: $progress%'),
            const SizedBox(height: 8),
            Text(current.prompt, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...List.generate(current.options.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => _answer(i),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(current.options[i]),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _answer(int selected) async {
    if (selected == _questions[_index].correctIndex) _correct++;

    if (_index < _questions.length - 1) {
      setState(() => _index++);
      return;
    }

    final percent = ((_correct / _questions.length) * 100).round();
    final appState = context.read<AppState>();
    bool passed = true;

    if (widget.isLevelTest) {
      passed = await appState.submitLevelTest(percent);
    } else {
      await appState.addQuizScore(percent);
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.isLevelTest ? 'Level Test Result' : 'Quiz Result'),
        content: Text(
          widget.isLevelTest
              ? 'Score: $percent%. ${passed ? 'Passed! Next level unlocked.' : 'Failed. Need at least 70%.'}'
              : 'Score: $percent%',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  List<QuizQuestion> _buildQuestions(List<VocabWord> words, int count) {
    if (words.length < 4) return <QuizQuestion>[];

    final pool = List<VocabWord>.from(words)..shuffle(_random);
    final selected = pool.take(min(count, pool.length)).toList();

    return selected.map((word) {
      final askMeaning = _random.nextBool();
      final prompt = askMeaning
          ? 'What is the Turkish meaning of "${word.word}"?'
          : 'Which English word means "${word.meaningTr}"?';

      final options = <String>[];
      final correct = askMeaning ? word.meaningTr : word.word;
      options.add(correct);

      final distractors = List<VocabWord>.from(words)
        ..removeWhere((w) => w.word == word.word)
        ..shuffle(_random);

      for (final d in distractors.take(3)) {
        options.add(askMeaning ? d.meaningTr : d.word);
      }

      options.shuffle(_random);

      return QuizQuestion(
        prompt: prompt,
        options: options,
        correctIndex: options.indexOf(correct),
      );
    }).toList(growable: false);
  }
}
