import 'dart:convert';

import 'package:http/http.dart' as http;

class DictionaryService {
  Future<String?> fetchPronunciationAudio(String word) async {
    final uri = Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word');
    final response = await http.get(uri);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as List<dynamic>;
    if (data.isEmpty) return null;

    final phonetics = (data.first['phonetics'] as List<dynamic>? ?? const []);
    for (final p in phonetics) {
      final audio = p['audio'] as String?;
      if (audio != null && audio.isNotEmpty) return audio;
    }
    return null;
  }
}
