enum CefrLevel { a1, a2, b1, b2 }

extension CefrLevelX on CefrLevel {
  String get key => name.toUpperCase();

  CefrLevel? get next {
    switch (this) {
      case CefrLevel.a1:
        return CefrLevel.a2;
      case CefrLevel.a2:
        return CefrLevel.b1;
      case CefrLevel.b1:
        return CefrLevel.b2;
      case CefrLevel.b2:
        return null;
    }
  }

  static CefrLevel fromString(String value) {
    return CefrLevel.values.firstWhere(
      (l) => l.name.toUpperCase() == value.toUpperCase(),
      orElse: () => CefrLevel.a1,
    );
  }
}

class VocabWord {
  const VocabWord({
    required this.word,
    required this.meaningTr,
    required this.example,
    required this.imageUrl,
    required this.level,
    this.audioUrl,
  });

  final String word;
  final String meaningTr;
  final String example;
  final String imageUrl;
  final String? audioUrl;
  final CefrLevel level;

  factory VocabWord.fromJson(Map<String, dynamic> json) {
    return VocabWord(
      word: json['word'] as String,
      meaningTr: json['meaning'] as String,
      example: json['example'] as String,
      imageUrl: json['imageUrl'] as String,
      audioUrl: json['audioUrl'] as String?,
      level: CefrLevelX.fromString(json['level'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'meaning': meaningTr,
        'example': example,
        'imageUrl': imageUrl,
        'audioUrl': audioUrl,
        'level': level.key,
      };
}
