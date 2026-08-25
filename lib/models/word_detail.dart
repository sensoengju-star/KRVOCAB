import 'dart:convert';

/// A model-generated study page for ONE vocabulary word.
///
/// Every explanatory field is written in KOREAN — that's the whole point of
/// the word page: the learner reads the meaning, the nuance and the sentence
/// notes in the language they're learning. English survives only as a
/// fallback gloss on each example sentence.
///
/// Persisted as JSON in the `word_details_v1` box (keyed by the word's id),
/// so re-opening a word is instant and works with the model server offline.
class WordDetail {
  const WordDetail({
    required this.hangul,
    required this.definitionKo,
    required this.nuanceKo,
    required this.related,
    required this.examples,
    required this.generatedAt,
  });

  final String hangul;

  /// 뜻풀이 — the definition, in Korean.
  final String definitionKo;

  /// 쓰임 · 뉘앙스 — when and how the word is used, in Korean.
  final String nuanceKo;

  /// 관련 어휘 — related words with a short Korean note each.
  final List<RelatedWord> related;

  /// 예문 — example sentences, each with a Korean explanation.
  final List<DetailExample> examples;

  final DateTime generatedAt;

  /// Nothing worth showing — treated as "not generated yet".
  bool get isEmpty => definitionKo.trim().isEmpty && examples.isEmpty;

  factory WordDetail.fromJson(Map<String, dynamic> j, {String? hangul}) {
    return WordDetail(
      hangul: (j['hangul'] ?? hangul ?? '').toString().trim(),
      definitionKo:
          (j['definitionKo'] ?? j['definition'] ?? '').toString().trim(),
      nuanceKo: (j['nuanceKo'] ?? j['nuance'] ?? '').toString().trim(),
      related: ((j['related'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => RelatedWord(
                word: (e['word'] ?? '').toString().trim(),
                noteKo: (e['noteKo'] ?? e['note'] ?? '').toString().trim(),
              ))
          .where((r) => r.word.isNotEmpty)
          .toList(),
      examples: ((j['examples'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => DetailExample(
                korean: (e['korean'] ?? '').toString().trim(),
                romanization: (e['romanization'] ?? '').toString().trim(),
                english: (e['english'] ?? '').toString().trim(),
                explanationKo:
                    (e['explanationKo'] ?? e['explanation'] ?? '')
                        .toString()
                        .trim(),
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
        'nuanceKo': nuanceKo,
        'related': [
          for (final r in related) {'word': r.word, 'noteKo': r.noteKo},
        ],
        'examples': [
          for (final e in examples)
            {
              'korean': e.korean,
              'romanization': e.romanization,
              'english': e.english,
              'explanationKo': e.explanationKo,
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

class RelatedWord {
  const RelatedWord({required this.word, required this.noteKo});
  final String word;
  final String noteKo;
}

class DetailExample {
  const DetailExample({
    required this.korean,
    required this.romanization,
    required this.english,
    required this.explanationKo,
  });

  final String korean;
  final String romanization;
  final String english;

  /// Why the sentence works — grammar, particles, nuance — in Korean.
  final String explanationKo;
}
