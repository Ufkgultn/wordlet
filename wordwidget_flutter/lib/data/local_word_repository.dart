import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/models/vocab_word.dart';

class LocalWordRepository {
  List<VocabWord>? _cache;

  Future<List<VocabWord>> getAllWords() async {
    if (_cache != null) return _cache!;

    final raw = await rootBundle.loadString('assets/words/words.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    _cache = decoded
        .map((e) => VocabWord.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
    return _cache!;
  }

  Future<List<VocabWord>> getWordsByLevel(CefrLevel level) async {
    final all = await getAllWords();
    return all.where((w) => w.level == level).toList(growable: false);
  }

  Future<VocabWord?> findByWord(String word) async {
    final all = await getAllWords();
    for (final item in all) {
      if (item.word.toLowerCase() == word.toLowerCase()) return item;
    }
    return null;
  }
}
