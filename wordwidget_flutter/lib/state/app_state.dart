import 'dart:math';

import 'package:flutter/material.dart';

import '../core/models/user_progress.dart';
import '../core/models/vocab_word.dart';
import '../data/local_word_repository.dart';
import '../data/progress_repository.dart';
import '../services/widget_service.dart';

class AppState extends ChangeNotifier {
  AppState(
    this._wordRepository,
    this._progressRepository,
    this._widgetService,
  );

  final LocalWordRepository _wordRepository;
  final ProgressRepository _progressRepository;
  final WidgetService _widgetService;

  final Random _random = Random();

  UserProgress _progress = UserProgress.initial();
  List<VocabWord> _allWords = const [];
  VocabWord? _todayWord;
  bool _isLoading = true;

  bool get isLoading => _isLoading;
  UserProgress get progress => _progress;
  VocabWord? get todayWord => _todayWord;
  CefrLevel get currentLevel => _progress.currentLevel;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    await _widgetService.init();
    _allWords = await _wordRepository.getAllWords();
    _progress = await _progressRepository.load();

    _todayWord = _resolveTodayWord();
    if (_todayWord != null) {
      await _widgetService.syncWord(_todayWord!);
    }

    _isLoading = false;
    notifyListeners();
  }

  List<VocabWord> wordsForCurrentLevel() {
    return _allWords.where((w) => w.level == currentLevel).toList();
  }

  List<VocabWord> learnedWords() {
    return _allWords.where((w) => _progress.learnedWordIds.contains(w.word)).toList();
  }

  Future<void> changeWord() async {
    final words = wordsForCurrentLevel();
    if (words.isEmpty) return;

    VocabWord next = words[_random.nextInt(words.length)];
    if (_todayWord != null && words.length > 1) {
      while (next.word == _todayWord!.word) {
        next = words[_random.nextInt(words.length)];
      }
    }

    _todayWord = next;
    _progress = _progress.copyWith(todayWord: next.word);
    await _progressRepository.save(_progress);
    await _widgetService.syncWord(next);
    notifyListeners();
  }

  Future<void> markLearned(String word, bool learned) async {
    final newSet = Set<String>.from(_progress.learnedWordIds);
    if (learned) {
      newSet.add(word);
    } else {
      newSet.remove(word);
    }
    _progress = _progress.copyWith(learnedWordIds: newSet);
    await _progressRepository.save(_progress);
    notifyListeners();
  }

  Future<void> addQuizScore(int percent) async {
    final scores = List<int>.from(_progress.quizScores)..add(percent);
    _progress = _progress.copyWith(quizScores: scores);
    await _progressRepository.save(_progress);
    notifyListeners();
  }

  Future<bool> submitLevelTest(int percent) async {
    if (percent < 70) {
      await addQuizScore(percent);
      return false;
    }

    final next = currentLevel.next;
    await addQuizScore(percent);
    if (next == null) return true;

    _progress = _progress.copyWith(currentLevel: next, todayWord: null);
    await _progressRepository.save(_progress);
    await changeWord();
    return true;
  }

  VocabWord? _resolveTodayWord() {
    if (_progress.todayWord != null) {
      for (final w in _allWords) {
        if (w.word == _progress.todayWord) return w;
      }
    }

    final words = wordsForCurrentLevel();
    if (words.isEmpty) return null;
    return words[_random.nextInt(words.length)];
  }
}
