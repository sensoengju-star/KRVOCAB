import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Turns a bare list of Korean words into full vocabulary entries.
///
/// This is the one place the app calls a cloud model, and it exists so the
/// phone doesn't have to: capture on the phone is a plain list of words, and
/// the definitions are filled in here on import.
///
/// The API key is entered by the user in Settings and lives only in
/// SharedPreferences on this machine — never in source, never in a file inside
/// the repository, never in a log. This project is a public repo, and a
/// committed key is a leaked key within minutes.
class ClaudeService {
  ClaudeService._();
  static final ClaudeService instance = ClaudeService._();

  static const _kApiKey = 'claude_api_key';
  static const _kModel = 'claude_model';

  /// Cheap and more than good enough for dictionary work. Exact string, no
  /// date suffix.
  static const defaultModel = 'claude-sonnet-5';

  static const models = <String, String>{
    'claude-sonnet-5': 'Sonnet 5 — balanced (recommended)',
    'claude-opus-5': 'Opus 5 — best definitions, ~2.5× the cost',
    'claude-haiku-4-5': 'Haiku 4.5 — cheapest',
  };

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  /// How many words to define in one request. Small enough that a failure
  /// costs little and a slow reply doesn't look like a hang.
  static const int batchSize = 25;

  Future<String?> apiKey() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_kApiKey)?.trim();
    return (k == null || k.isEmpty) ? null : k;
  }

  Future<bool> get isConfigured async => (await apiKey()) != null;

  Future<String> model() async {
    final p = await SharedPreferences.getInstance();
    final m = p.getString(_kModel)?.trim();
    return (m == null || m.isEmpty) ? defaultModel : m;
  }

  Future<void> save({String? apiKey, String? model}) async {
    final p = await SharedPreferences.getInstance();
    if (apiKey != null) await p.setString(_kApiKey, apiKey.trim());
    if (model != null) await p.setString(_kModel, model.trim());
  }

  Future<void> clearKey() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kApiKey);
  }

  /// The JSON shape the model is constrained to return. Structured outputs
  /// mean there is no prose to strip and no parsing to get wrong — an
  /// unrecognised part of speech simply cannot come back.
  static Map<String, dynamic> get _schema => {
        'type': 'object',
        'properties': {
          'words': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                // The word EXACTLY as it was typed, echoed back so the caller
                // can match the answer to the question. Without it a
                // correction is unmatchable: the reply comes back under a
                // spelling the caller never sent.
                'input': {'type': 'string'},
                'hangul': {'type': 'string'},
                'romanization': {'type': 'string'},
                'englishMeaning': {'type': 'string'},
                'partOfSpeech': {
                  'type': 'string',
                  'enum': [
                    'noun',
                    'verb',
                    'descriptive_verb',
                    'adverb',
                    'particle',
                    'expression',
                  ],
                },
                'politeForm': {'type': 'string'},
              },
              'required': [
                'input',
                'hangul',
                'romanization',
                'englishMeaning',
                'partOfSpeech',
                'politeForm',
              ],
              'additionalProperties': false,
            },
          },
        },
        'required': ['words'],
        'additionalProperties': false,
      };

  static const _system =
      'You are a Korean dictionary for a TOPIK I-II learner. The words come '
      'from someone typing quickly on a phone, so treat every one as possibly '
      'mistyped.\n\n'
      'For each word given, return:\n'
      '- input: the word EXACTLY as it was given to you, character for '
      'character, even when it is wrong. This is how your answer is matched '
      'back to the question, so it must never be cleaned up or corrected.\n'
      '- hangul: the correct dictionary form. Fix obvious typos (a wrong or '
      'missing jamo, a doubled character) to the nearest real Korean word, and '
      'convert a conjugated form to its dictionary form — 갔어요 becomes 가다. '
      'If the word is already correct, repeat it unchanged. Never invent a '
      'word: if you cannot tell what was meant, return the input as-is and '
      'give it the best meaning you can.\n'
      '- romanization: revised romanization of hangul.\n'
      '- englishMeaning: a short gloss.\n'
      '- partOfSpeech: one of the listed values.\n'
      '- politeForm: the present polite 해요체 form for verbs and descriptive '
      'verbs only; an empty string for everything else.\n\n'
      'Return exactly one entry per word given, in the same order.';

  /// Defines [words], in batches. Returns one map per word, using the same
  /// field names as [VocabWord] so the caller can construct directly.
  ///
  /// Throws [ClaudeException] with the API's own message on failure — the
  /// caller surfaces it rather than silently importing bare words.
  Future<List<Map<String, dynamic>>> define(List<String> words) async {
    final key = await apiKey();
    if (key == null) throw const ClaudeException('No API key saved.');
    if (words.isEmpty) return const [];

    final chosen = await model();
    final out = <Map<String, dynamic>>[];

    for (var i = 0; i < words.length; i += batchSize) {
      final end =
          (i + batchSize) > words.length ? words.length : (i + batchSize);
      out.addAll(await _defineBatch(words.sublist(i, end), key, chosen));
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _defineBatch(
    List<String> words,
    String key,
    String model,
  ) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 16000,
              // A dictionary lookup has nothing to reason about, and thinking
              // tokens bill as output. Disabling it also guarantees a single
              // text block in the reply.
              'thinking': {'type': 'disabled'},
              'system': _system,
              'messages': [
                {'role': 'user', 'content': 'WORDS:\n${words.join('\n')}'}
              ],
              'output_config': {
                'format': {'type': 'json_schema', 'schema': _schema},
              },
            }),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw ClaudeException('Could not reach the API: $e');
    }

    if (res.statusCode != 200) {
      throw ClaudeException(_readError(res));
    }

    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      // A refusal comes back as HTTP 200 with no usable content — check before
      // reading the blocks.
      if (decoded['stop_reason'] == 'refusal') {
        throw const ClaudeException('The model declined this request.');
      }
      final blocks = (decoded['content'] as List?) ?? const [];
      final text = blocks
          .whereType<Map>()
          .firstWhere((b) => b['type'] == 'text', orElse: () => const {})['text']
          ?.toString();
      if (text == null || text.trim().isEmpty) {
        throw const ClaudeException('The API returned no text.');
      }
      final payload = jsonDecode(text);
      final list = (payload is Map ? payload['words'] as List? : null) ??
          (payload is List ? payload : const []);
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } on ClaudeException {
      rethrow;
    } catch (e) {
      throw ClaudeException('Could not read the reply: $e');
    }
  }

  /// A one-word round trip, for the Test button in Settings. Deliberately a
  /// misspelling: it proves the key, the model AND that correction is working.
  Future<String> test() async {
    final result = await define(['안뇽하세요']);
    if (result.isEmpty) throw const ClaudeException('Empty reply.');
    final w = result.first;
    final typed = (w['input'] ?? '').toString().trim();
    final fixed = (w['hangul'] ?? '').toString().trim();
    final gloss = (w['englishMeaning'] ?? '').toString().trim();
    // Show the correction when it happened: it proves the typo-fixing works,
    // not just that the key does.
    return typed.isNotEmpty && typed != fixed
        ? 'corrected $typed → $fixed ($gloss)'
        : '$fixed — $gloss';
  }

  String _readError(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final message = decoded['error']?['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return 'HTTP ${res.statusCode}: $message';
      }
    } catch (_) {}
    return switch (res.statusCode) {
      401 => 'Key rejected (401) — check it in Settings.',
      429 => 'Rate limited (429) — try again shortly.',
      _ => 'HTTP ${res.statusCode}.',
    };
  }
}

class ClaudeException implements Exception {
  const ClaudeException(this.message);
  final String message;
  @override
  String toString() => message;
}
