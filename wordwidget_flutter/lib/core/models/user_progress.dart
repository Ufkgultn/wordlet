import 'dart:convert';

import 'vocab_word.dart';

class UserProgress {
  UserProgress({
    required this.currentLevel,
    required this.learnedWordIds,
    required this.quizScores,
    this.todayWord,
  });

  final CefrLevel currentLevel;
  final Set<String> learnedWordIds;
  final List<int> quizScores;
  final String? todayWord;

  UserProgress copyWith({
    CefrLevel? currentLevel,
    Set<String>? learnedWordIds,
    List<int>? quizScores,
    String? todayWord,
  }) {
    return UserProgress(
      currentLevel: currentLevel ?? this.currentLevel,
      learnedWordIds: learnedWordIds ?? this.learnedWordIds,
      quizScores: quizScores ?? this.quizScores,
      todayWord: todayWord ?? this.todayWord,
    );
  }

  Map<String, dynamic> toMap() => {
        'currentLevel': currentLevel.key,
        'learnedWordIds': learnedWordIds.toList(),
        'quizScores': quizScores,
        'todayWord': todayWord,
      };

  factory UserProgress.fromMap(Map<String, dynamic> map) {
    return UserProgress(
      currentLevel: CefrLevelX.fromString((map['currentLevel'] as String?) ?? 'A1'),
      learnedWordIds: Set<String>.from((map['learnedWordIds'] as List?) ?? const []),
      quizScores: List<int>.from((map['quizScores'] as List?) ?? const []),
      todayWord: map['todayWord'] as String?,
    );
  }

  String toRaw() => jsonEncode(toMap());

  factory UserProgress.fromRaw(String raw) =>
      UserProgress.fromMap(jsonDecode(raw) as Map<String, dynamic>);

  static UserProgress initial() {
    return UserProgress(
      currentLevel: CefrLevel.a1,
      learnedWordIds: <String>{},
      quizScores: <int>[],
    );
  }
}
