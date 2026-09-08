import 'dart:convert';

/// A model-generated study page for ONE vocabulary word.
///
/// The definition is written in KOREAN — that's the whole point of the word
/// page: the learner reads the meaning in the language they're learning.
/// English survives only as a fallback gloss on each example sentence.
///
/// Persisted as JSON in the `word_details_v1` box (keyed by the word's id),
/// so re-opening a word is instant and works with the model server offline.
class WordDetail {
  const WordDetail({
    required this.hangul,
    required this.definitionKo,
    required this.examples,
    required this.generatedAt,
  });

  final String hangul;

  /// 뜻풀이 — the definition, in Korean.
  final String definitionKo;

  /// 예문 — example sentences.
  final List<DetailExample> examples;

  final DateTime generatedAt;

  /// Nothing worth showing — treated as "not generated yet".
  bool get isEmpty => definitionKo.trim().isEmpty && examples.isEmpty;

  factory WordDetail.fromJson(Map<String, dynamic> j, {String? hangul}) {
    return WordDetail(
      hangul: (j['hangul'] ?? hangul ?? '').toString().trim(),
      definitionKo:
          (j['definitionKo'] ?? j['definition'] ?? '').toString().trim(),
      examples: ((j['examples'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => DetailExample(
                korean: (e['korean'] ?? '').toString().trim(),
                romanization: (e['romanization'] ?? '').toString().trim(),
                english: (e['english'] ?? '').toString().trim(),
              ))
          .where((e) => e.korean.isNotEmpty)
          .toList(),
      generatedAt: DateTime.tryParse((j['generatedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'hangul': hangul,
        'definitionKo': definitionKo,
        'examples': [
          for (final e in examples)
            {
              'korean': e.korean,
              'romanization': e.romanization,
              'english': e.english,
            },
        ],
        'generatedAt': generatedAt.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  /// Tolerant decode — a corrupt or older cache entry reads as null rather
  /// than throwing on a screen build.
  static WordDetail? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WordDetail.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

class DetailExample {
  const DetailExample({
    required this.korean,
    required this.romanization,
    required this.english,
  });

  final String korean;
  final String romanization;
  final String english;
}
