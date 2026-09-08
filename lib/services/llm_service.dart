import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocab_word.dart';
import '../models/word_detail.dart';

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LlmConfig {
  LlmConfig({required this.endpoint, required this.modelAlias});
  final String endpoint;
  final String modelAlias;

  static const defaultEndpoint = 'http://127.0.0.1:8080/v1/chat/completions';
  static const defaultModelAlias = 'maldari-gemma';

  static Future<LlmConfig> load() async {
    final p = await SharedPreferences.getInstance();
    return LlmConfig(
      endpoint: p.getString('llm_endpoint') ?? defaultEndpoint,
      modelAlias: p.getString('llm_model_alias') ?? defaultModelAlias,
    );
  }

  static Future<void> save({String? endpoint, String? modelAlias}) async {
    final p = await SharedPreferences.getInstance();
    if (endpoint != null) await p.setString('llm_endpoint', endpoint);
    if (modelAlias != null) await p.setString('llm_model_alias', modelAlias);
  }
}

class LlmService {
  LlmService._();
  static final LlmService instance = LlmService._();

  static const _systemBase =
      'You are a Korean vocabulary tutor for learners at TOPIK I-II level '
      '(JLPT-equivalent for Korean). Respond ONLY with the requested JSON. '
      'Romanization is strictly Revised Romanization (e.g. "bap", "kim", '
      '"Hangukeo"), NEVER McCune-Reischauer ("pap", "Han\'gugŏ"). '
      'Verbs and descriptive verbs must use their DICTIONARY form ending in '
      '-다 (가다, 예쁘다 — not 가요/갑니다/예뻐요). Reject rough slang, '
      'archaic hanja-only forms, and 사투리 dialect.';

  /// Stream three example sentences for [word].
  /// Yields parsed chunks of `choices[0].delta.content` (or
  /// `delta.reasoning_content` as a fallback for Gemma quirks).
  Future<Stream<String>> generateExamples(String word) async {
    final config = await LlmConfig.load();

    final body = jsonEncode({
      'model': config.modelAlias,
      'stream': true,
      'temperature': 0.7,
      'max_tokens': 1200,
      // Gemma 3n otherwise burns the entire token budget on hidden reasoning,
      // leaving delta.content empty.
      'chat_template_kwargs': {'enable_thinking': false},
      'messages': [
        {
          'role': 'system',
          'content': '$_systemBase\n\n'
              'Produce exactly 3 short example sentences using the target word. '
              'Reply with a single JSON object of the shape: '
              '{"examples":[{"korean":"...","romanization":"...","english":"...",'
              '"breakdown":[{"word":"...","meaning":"..."}]}, ... ]}. '
              'The "korean" sentence MUST contain the target word verbatim.',
        },
        {
          'role': 'user',
          'content': 'Target word: "$word". Generate three TOPIK I-II level '
              'example sentences using this word in different contexts.',
        }
      ],
    });

    final request = http.Request('POST', Uri.parse(config.endpoint))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = body;

    final response = await request.send();
    if (response.statusCode != 200) {
      throw LlmException('Server returned ${response.statusCode}');
    }

    final controller = StreamController<String>();
    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    () async {
      try {
        await for (final line in lineStream) {
          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') break;
          try {
            final obj = jsonDecode(payload);
            final choices = obj['choices'];
            if (choices is List && choices.isNotEmpty) {
              final delta = choices[0]['delta'];
              if (delta is Map) {
                final content = delta['content'] ?? delta['reasoning_content'];
                if (content is String && content.isNotEmpty) {
                  controller.add(content);
                }
              }
            }
          } catch (_) {
            // ignore malformed lines
          }
        }
      } catch (e) {
        controller.addError(LlmException('Stream error: $e'));
      } finally {
        await controller.close();
      }
    }();

    return controller.stream;
  }

  /// Stream several short Korean stories that collectively weave in the
  /// supplied vocabulary [words]. Yields parsed chunks of
  /// `choices[0].delta.content` (or `delta.reasoning_content` for Gemma).
  ///
  /// The model is asked to return:
  /// {"stories":[{"title":"...","korean":"...","romanization":"...",
  ///   "english":"...","words_used":["...", ...]}, ... ]}
  Future<Stream<String>> generateStories(
    List<String> words, {
    int storyCount = 3,
  }) async {
    final config = await LlmConfig.load();

    // Keep the prompt within a sane context budget. With up to 1000 words we
    // can't feed them all, so cap the list the model has to weave in.
    const maxWords = 40;
    final pool = words.map((w) => w.trim()).where((w) => w.isNotEmpty).toList();
    final selected = pool.length > maxWords ? pool.sublist(0, maxWords) : pool;

    // Deterministically ASSIGN the words across the stories so every word has
    // an explicit home. "Use as many as possible" was treated as optional and
    // dropped words; requiring each story to use its assigned set guarantees
    // full coverage. Round-robin keeps the buckets even (25 words / 5 stories
    // = 5 each).
    final buckets = List.generate(storyCount, (_) => <String>[]);
    for (var i = 0; i < selected.length; i++) {
      buckets[i % storyCount].add(selected[i]);
    }
    final assignment = StringBuffer();
    for (var i = 0; i < storyCount; i++) {
      final ws = buckets[i].join(', ');
      assignment.writeln(
          'Story ${i + 1} MUST use ALL of these words: ${ws.isEmpty ? '(none assigned)' : ws}.');
    }

    final body = jsonEncode({
      'model': config.modelAlias,
      'stream': true,
      'temperature': 0.7,
      // Generous budget so the full JSON array of $storyCount stories isn't
      // truncated mid-stream (which would drop the later stories). Requires a
      // matching server context window (-c) — see LlmLauncher.
      'max_tokens': 6000,
      'chat_template_kwargs': {'enable_thinking': false},
      // NOTE: deliberately does NOT use _systemBase — that prompt forces verbs
      // into their -다 citation form, which makes the stories read like a word
      // list ("그는 가다") instead of natural prose.
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a Korean storyteller writing for TOPIK I-II learners. '
              'Write exactly $storyCount stories — no more, no fewer. You MUST '
              'output all $storyCount story objects in the JSON array; do not '
              'stop until every one is written. Each story is a full, engaging '
              'paragraph of about 6-10 sentences with a clear beginning, '
              'middle and end. Write in NATURAL Korean prose: conjugate and '
              'inflect every word properly for its place in the sentence — use '
              'a natural narrative style (e.g. past-tense 했어요/갔어요 or '
              'written 했다/갔다). NEVER leave a verb or adjective in its bare '
              '-다 dictionary/citation form (write "학교에 갔어요", never '
              '"학교에 가다"). '
              'CRITICAL: each story MUST include EVERY ONE of the target words '
              'assigned to it — do not skip, substitute, or omit any assigned '
              'word; just conjugate it naturally (e.g. 가다 → 갔어요, '
              '예쁘다 → 예뻤어요). Reply with a single JSON object of the shape: '
              '{"stories":[{"title":"...","korean":"...","english":"...",'
              '"used":[{"form":"...","word":"..."}, ...]}, ... ]}. The "korean" '
              'field is the full story in Hangul and "english" is a natural '
              'English translation. The "used" array MUST contain one entry '
              'per assigned word: "form" is the EXACT surface form as it '
              'literally appears in this story\'s "korean" text (the '
              'conjugated/inflected substring copied verbatim — e.g. "갔어요"), '
              'and "word" is the original assigned target word it came from '
              '(e.g. "가다"). Do NOT include '
              'romanization or any word breakdown.',
        },
        {
          'role': 'user',
          'content': 'Write $storyCount stories. Each story must use every '
              'word assigned to it below:\n\n'
              '${assignment.toString().trim()}',
        }
      ],
    });

    final request = http.Request('POST', Uri.parse(config.endpoint))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = body;

    final response = await request.send();
    if (response.statusCode != 200) {
      throw LlmException('Server returned ${response.statusCode}');
    }

    final controller = StreamController<String>();
    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    () async {
      try {
        await for (final line in lineStream) {
          if (line.isEmpty) continue;
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') break;
          try {
            final obj = jsonDecode(payload);
            final choices = obj['choices'];
            if (choices is List && choices.isNotEmpty) {
              final delta = choices[0]['delta'];
              if (delta is Map) {
                final content = delta['content'] ?? delta['reasoning_content'];
                if (content is String && content.isNotEmpty) {
                  controller.add(content);
                }
              }
            }
          } catch (_) {
            // ignore malformed lines
          }
        }
      } catch (e) {
        controller.addError(LlmException('Stream error: $e'));
      } finally {
        await controller.close();
      }
    }();

    return controller.stream;
  }

  /// Evaluate ONE learner-written sentence. Returns whether it was already
  /// correct plus the corrected, natural version — and NO other feedback.
  /// One-shot (non-streaming), low temperature. Throws [LlmException] on a
  /// server/parse failure.
  Future<({bool correct, String corrected})> correctSentence(
      String word, String sentence) async {
    final config = await LlmConfig.load();

    final body = jsonEncode({
      'model': config.modelAlias,
      'stream': false,
      'temperature': 0.3,
      'max_tokens': 400,
      'chat_template_kwargs': {'enable_thinking': false},
      // NOTE: deliberately does NOT use _systemBase — that prompt forces verbs
      // into their -다 dictionary form, which is correct for vocab entries but
      // WRONG for grading a learner's sentence (it would rewrite a perfectly
      // good 달라졌어요 into 달라졌다). Here we must preserve the learner's own
      // speech level.
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a Korean writing tutor for TOPIK I-II learners. The '
              'learner wrote one sentence using a target word. Return ONLY the '
              'corrected, natural-sounding version. Rules: '
              '(1) PRESERVE the learner\'s speech level / sentence ending '
              'exactly — if they wrote 해요체 (-아요/-어요) keep 해요체; if '
              '합니다체 keep 합니다체; if the plain 한다체 keep that. NEVER '
              'convert a conjugated polite ending into the -다 dictionary '
              'form. '
              '(2) Change ONLY genuine errors: grammar, particles, spelling, '
              'spacing, or clearly unnatural word choice. Make the minimum '
              'edits needed. '
              '(3) Keep the target word and the learner\'s intended meaning. '
              '(4) If the sentence is already correct, set "correct" to true '
              'and return it EXACTLY as written, unchanged. Otherwise set '
              '"correct" to false and return the fixed sentence. '
              '(5) Do NOT explain, comment, translate, label what was wrong, '
              'or add ANY other feedback. '
              'Reply with ONLY a JSON object: '
              '{"correct": true|false, "corrected":"..."}.',
        },
        {
          'role': 'user',
          'content': 'Target word: "$word". Sentence: $sentence',
        }
      ],
    });

    final response = await http
        .post(
          Uri.parse(config.endpoint),
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw LlmException('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final raw = decoded['choices']?[0]?['message']?['content'] as String?;
    if (raw == null) throw LlmException('Empty response.');

    final parsed = tryParseBuffer(raw);
    final corrected = (parsed?['corrected'] ?? '').toString().trim();
    if (corrected.isEmpty) {
      throw LlmException('Could not read the corrected sentence.');
    }
    // Trust the model's flag when present; otherwise infer from whether the
    // corrected text differs from what the learner wrote.
    final flag = parsed?['correct'];
    final isCorrect =
        flag is bool ? flag : corrected == sentence.trim();
    return (correct: isCorrect, corrected: corrected);
  }

  /// Parse a possibly-incomplete buffer that may contain a JSON array of
  /// objects partway through streaming. Returns whichever complete `stories`
  /// (or `examples`) objects can be extracted so far. Unlike [tryParseBuffer]
  /// this tolerates the closing `}` / `]` not having arrived yet.
  static List<Map<String, dynamic>> parsePartialArray(
    String raw,
    String key,
  ) {
    // Fast path: the whole object is complete.
    final whole = tryParseBuffer(raw);
    if (whole != null && whole[key] is List) {
      return (whole[key] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    // Slow path: scan for the array and pull out each balanced object.
    final keyIdx = raw.indexOf('"$key"');
    if (keyIdx == -1) return const [];
    final arrStart = raw.indexOf('[', keyIdx);
    if (arrStart == -1) return const [];

    final out = <Map<String, dynamic>>[];
    var depth = 0;
    var objStart = -1;
    var inString = false;
    var escaped = false;

    for (var i = arrStart + 1; i < raw.length; i++) {
      final c = raw[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') {
        if (depth == 0) objStart = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && objStart != -1) {
          final candidate = raw.substring(objStart, i + 1);
          try {
            final parsed = jsonDecode(candidate);
            if (parsed is Map<String, dynamic>) out.add(parsed);
          } catch (_) {}
          objStart = -1;
        }
      } else if (c == ']' && depth == 0) {
        break;
      }
    }
    return out;
  }

  /// One-shot auto-fill. Returns a map with keys: hangul, romanization,
  /// english, partOfSpeech. Throws [LlmException] if the model contradicts a
  /// user-set field (a tell-tale sign of hallucination).
  Future<Map<String, String>> autoFillWord({
    String? hangul,
    String? romanization,
    String? english,
  }) async {
    final config = await LlmConfig.load();

    final known = <String, String>{};
    if (hangul != null && hangul.trim().isNotEmpty) known['hangul'] = hangul.trim();
    if (romanization != null && romanization.trim().isNotEmpty) {
      known['romanization'] = romanization.trim();
    }
    if (english != null && english.trim().isNotEmpty) known['english'] = english.trim();

    if (known.isEmpty) {
      throw LlmException('No input to auto-fill from.');
    }

    final body = jsonEncode({
      'model': config.modelAlias,
      'stream': false,
      'temperature': 0.2,
      'max_tokens': 800,
      'chat_template_kwargs': {'enable_thinking': false},
      'messages': [
        {
          'role': 'system',
          'content': '$_systemBase\n\n'
              'You will be given partial fields for a Korean vocabulary entry. '
              'The given fields are CONSTRAINTS the response must satisfy — '
              'do NOT change them. Fill the missing fields consistently. '
              'For the "hangul" field, return the COMPLETE word including '
              'endings (e.g. "가다" not "가"). '
              'For "politeForm", give the standard present-tense polite form '
              '(해요체) of the word — e.g. 가다→"가요", 먹다→"먹어요", '
              '예쁘다→"예뻐요", 하다→"해요". For nouns or words where a polite '
              'verb form does not apply, return an empty string "". '
              'Return ONLY a JSON object: '
              '{"hangul":"...","romanization":"...","english":"...",'
              '"politeForm":"...",'
              '"partOfSpeech":"noun|verb|descriptive_verb|adverb|particle|expression"}.',
        },
        {
          'role': 'user',
          'content': 'Known fields (constraints): ${jsonEncode(known)}',
        }
      ],
    });

    final response = await http.post(
      Uri.parse(config.endpoint),
      headers: const {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw LlmException('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final raw = decoded['choices']?[0]?['message']?['content'] as String?;
    if (raw == null) throw LlmException('Empty response.');

    final parsed = tryParseBuffer(raw);
    if (parsed == null) {
      throw LlmException('Could not parse model response.');
    }

    final result = <String, String>{
      'hangul': (parsed['hangul'] ?? '').toString().trim(),
      'romanization': (parsed['romanization'] ?? '').toString().trim(),
      'english': (parsed['english'] ?? parsed['englishMeaning'] ?? '')
          .toString()
          .trim(),
      'politeForm':
          (parsed['politeForm'] ?? parsed['polite'] ?? '').toString().trim(),
      'partOfSpeech':
          (parsed['partOfSpeech'] ?? parsed['pos'] ?? '').toString().trim(),
    };

    // A present polite form only applies to verbs and descriptive verbs. For
    // anything else (nouns, adverbs, particles, expressions) force it empty,
    // even if the model invented one — e.g. the copula "문제예요" for the noun
    // 문제.
    final pos = result['partOfSpeech'];
    if (pos != PartsOfSpeech.verb && pos != PartsOfSpeech.descriptiveVerb) {
      result['politeForm'] = '';
    }

    // Hallucination check: if a user-set field came back changed, refuse.
    bool _diff(String? a, String? b) {
      if (a == null || a.trim().isEmpty) return false;
      return a.trim().toLowerCase() != (b ?? '').trim().toLowerCase();
    }

    if (_diff(known['hangul'], result['hangul']) ||
        _diff(known['romanization'], result['romanization']) ||
        _diff(known['english'], result['english'])) {
      throw LlmException(
          "The model couldn't find a match — try a clearer word.");
    }

    return result;
  }

  /// Extract the first complete JSON object from a possibly-incomplete buffer.
  /// Handles ```json fences, escapes, and quoted strings.
  static Map<String, dynamic>? tryParseBuffer(String raw) {
    var s = raw.trim();

    // Strip ```json ... ``` fences.
    if (s.startsWith('```')) {
      final firstNewline = s.indexOf('\n');
      if (firstNewline != -1) s = s.substring(firstNewline + 1);
      final closing = s.lastIndexOf('```');
      if (closing != -1) s = s.substring(0, closing);
      s = s.trim();
    }

    final start = s.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          final candidate = s.substring(start, i + 1);
          try {
            final parsed = jsonDecode(candidate);
            if (parsed is Map<String, dynamic>) return parsed;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// Every example sentence handed out this session, normalized for
  /// comparison. In memory only, deliberately: closing and reopening the app
  /// is the reset, which is exactly what a refresh should mean.
  final Set<String> _examplesThisSession = <String>{};

  /// The sentences already written for each word, verbatim, so the model can
  /// be shown what not to write again. Capped — a long avoid-list starts
  /// crowding out the actual instruction.
  final Map<String, List<String>> _examplesByWord = <String, List<String>>{};

  static const int _maxAvoidList = 6;

  /// Two sentences count as the same when only spacing or punctuation differs.
  static final RegExp _exampleNoise = RegExp(r'[\s.,!?~`-]');

  String _exampleKey(String s) =>
      s.toLowerCase().replaceAll(_exampleNoise, '');

  /// One example sentence for [word], used by the Review screen to reinforce
  /// a correct answer.
  ///
  /// No sentence is served twice in a session: earlier sentences for the word
  /// go into the prompt as an avoid-list, and anything that comes back
  /// matching one already seen is rejected and asked for again at a higher
  /// temperature. Returns null when three tries all come back repeats —
  /// better no sentence than the same one over again.
  Future<({String korean, String english, String usedForm})?>
      generateOneExample(String word) async {
    final config = await LlmConfig.load();
    final avoid = _examplesByWord[word] ?? const <String>[];

    // Rising temperature: the first ask stays predictable, and each repeat
    // buys variety with a little more freedom.
    const temperatures = [0.5, 0.85, 1.05];

    for (final temperature in temperatures) {
      final body = jsonEncode({
        'model': config.modelAlias,
        'stream': false,
        'temperature': temperature,
        // Room for a two-clause sentence plus its translation. The old 200
        // was only ever enough for the fragments this used to produce.
        'max_tokens': 420,
        'chat_template_kwargs': {'enable_thinking': false},
        // NOTE: deliberately does NOT use _systemBase — that prompt forces verbs
        // into their -다 dictionary form, which produces stilted, unnatural
        // example sentences (e.g. "그는 학교에 가다"). Here we want a natural,
        // properly-conjugated sentence.
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a Korean tutor for TOPIK I-II learners. Write ONE '
                'natural-sounding example sentence that uses the target word, '
                'conjugating or inflecting it naturally as the sentence '
                'requires — use the everyday polite 해요체 style (e.g. '
                '-아요/-어요). Do NOT leave a verb or adjective in its -다 '
                'dictionary form. Make it a FULL sentence with real context: '
                'about 12 to 20 어절, built from TWO clauses joined by a '
                'connective such as -고, -아서/-어서, -지만, -는데 or -(으)면. A '
                'three-word fragment teaches nothing about how the word is '
                'used. Keep every word in it at TOPIK I-II level. Reply with '
                'ONLY a JSON object: {"korean":"...","english":"...",'
                '"used":"..."}. The "used" field is the EXACT surface form of '
                'the target word as it literally appears in your "korean" '
                'sentence (the conjugated substring, copied verbatim — e.g. '
                'if you wrote "갔어요" put "갔어요").',
          },
          {
            'role': 'user',
            'content': avoid.isEmpty
                ? 'Target word: "$word".'
                : 'Target word: "$word".\n\nYou have already written the '
                    'sentences below for this word. Write a DIFFERENT one: a '
                    'new situation, a different subject, a different ending.\n'
                    '${avoid.map((s) => '- $s').join('\n')}',
          }
        ],
      });

      try {
        final response = await http
            .post(
              Uri.parse(config.endpoint),
              headers: const {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) return null;
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final raw = decoded['choices']?[0]?['message']?['content'] as String?;
        if (raw == null) return null;
        final parsed = tryParseBuffer(raw);
        if (parsed == null) continue;
        final ko = (parsed['korean'] ?? '').toString().trim();
        final en = (parsed['english'] ?? '').toString().trim();
        final used = (parsed['used'] ?? '').toString().trim();
        if (ko.isEmpty) continue;

        // add() is the duplicate check and the record in one move.
        if (!_examplesThisSession.add(_exampleKey(ko))) continue;

        final seen = _examplesByWord.putIfAbsent(word, () => <String>[]);
        seen.add(ko);
        if (seen.length > _maxAvoidList) seen.removeAt(0);

        return (korean: ko, english: en, usedForm: used);
      } catch (_) {
        // A transport failure won't fix itself on the next pass, and three
        // 30-second timeouts would leave the card waiting a minute and a half.
        return null;
      }
    }
    return null;
  }

  /// Build the full study page for ONE word — definition, nuance, related
  /// vocabulary and example sentences — with every explanation written in
  /// KOREAN. English survives only as a gloss under each example sentence.
  ///
  /// One-shot (non-streaming): the page is shown all at once and then cached,
  /// so a partial render buys nothing. Throws [LlmException] on failure.
  Future<WordDetail> generateWordDetail({
    required String hangul,
    String englishMeaning = '',
    String partOfSpeech = '',
    int exampleCount = 4,
  }) async {
    final config = await LlmConfig.load();

    final known = <String, String>{'hangul': hangul.trim()};
    if (englishMeaning.trim().isNotEmpty) {
      known['english'] = englishMeaning.trim();
    }
    if (partOfSpeech.trim().isNotEmpty) {
      known['partOfSpeech'] = partOfSpeech.trim();
    }

    final body = jsonEncode({
      'model': config.modelAlias,
      'stream': false,
      'temperature': 0.5,
      // Halved along with the schema: the page is now just a definition and
      // a handful of sentences.
      'max_tokens': 1200,
      'chat_template_kwargs': {'enable_thinking': false},
      // NOTE: deliberately does NOT use _systemBase — that prompt forces every
      // verb into its -다 citation form, which is right for a dictionary entry
      // but wrong inside example sentences ("그는 학교에 가다"). The dictionary
      // form is pinned below for the headword only.
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a Korean vocabulary tutor writing a dictionary-style '
                  'study page for a TOPIK I-II learner. '
                  'CRITICAL: the definition you write MUST be written IN '
                  'KOREAN (한국어), never in English. Use simple, clear '
                  'TOPIK I-II Korean in '
                  '해요체, short sentences, no rare vocabulary. The ONLY '
                  'English in your answer is the "english" field of each '
                  'example, which is a plain translation of that sentence. '
                  'Example sentences must be natural Korean with the target '
                  'word conjugated properly for its place in the sentence — '
                  'never leave a verb or adjective in its bare -다 dictionary '
                  'form inside a sentence. Each example\'s "korean" MUST '
                  'actually contain the target word (in whatever inflected '
                  'form it takes). Romanization is strictly Revised '
                  'Romanization ("bap", "hakgyo"), never McCune-Reischauer. '
                  'Reply with ONLY a single JSON object, no prose and no code '
                  'fences, of exactly this shape: '
                  '{"definitionKo":"...",'
                  '"examples":[{"korean":"...","romanization":"...",'
                  '"english":"..."}]}. '
                  '"definitionKo" is the meaning of the word explained in '
                  'Korean (1-2 sentences, like a 국어사전 뜻풀이). '
                  '"examples" contains exactly $exampleCount sentences of '
                  'increasing length. '
                  'Output NOTHING else — no usage notes, no related words, '
                  'no per-sentence commentary. '
                  'Write every JSON string on a single line: never put a raw '
                  'newline inside a string value.',
        },
        {
          'role': 'user',
          'content': 'Target word entry: ${jsonEncode(known)}. '
              'Write the Korean study page for "${hangul.trim()}".',
        }
      ],
    });

    final response = await http
        .post(
          Uri.parse(config.endpoint),
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 180));

    if (response.statusCode != 200) {
      throw LlmException('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final raw = decoded['choices']?[0]?['message']?['content'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      throw LlmException('Could not generate this word page.');
    }

    final parsed = tryParseBuffer(raw);
    if (parsed == null) {
      throw LlmException('Could not read the model response.');
    }

    final detail = WordDetail.fromJson(parsed, hangul: hangul.trim());
    if (detail.isEmpty) {
      throw LlmException(
          'The model returned an empty page — try generating again.');
    }
    return detail;
  }

  /// Generate a grammar explanation for [prompt]. Returns a title and a
  /// cleanly-formatted Markdown body following a fixed section template.
  /// One-shot; throws [LlmException] on failure.
  ///
  /// Returns PLAIN Markdown (not JSON): long multi-line bodies make local
  /// models emit raw newlines inside JSON strings, which is invalid JSON and
  /// fails to parse. Markdown text is parsed locally instead.
  Future<({String title, String body})> generateGrammar(String prompt) async {
    final config = await LlmConfig.load();
    final body = jsonEncode({
      'model': config.modelAlias,
      'stream': false,
      'temperature': 0.4,
      'max_tokens': 2200,
      'chat_template_kwargs': {'enable_thinking': false},
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a Korean grammar teacher for TOPIK I-II learners. '
              'Explain the requested grammar point clearly and simply in '
              'English, with natural Korean examples. Reply with ONLY Markdown '
              '(no JSON, no code fences, no preamble). Use EXACTLY this '
              'structure:\n'
              '# <short title including the Korean form, e.g. ~(으)면 — '
              'conditional "if">\n'
              '## In short\n'
              'one or two sentence summary.\n'
              '## How to form it\n'
              '- attachment / conjugation rules as "- " bullet points.\n'
              '## Examples\n'
              '- 한국어 예문  —  English translation\n'
              '(3-5 example bullets; each a natural Korean sentence using the '
              'grammar, then "  —  ", then its English translation.)\n'
              '## Notes\n'
              '- common mistakes or nuances as "- " bullet points.\n'
              'Keep it tight and beginner-friendly.\n\n'
              'CRITICAL: explain ONLY the exact grammar point requested. Every '
              'formation rule and EVERY example sentence must actually use '
              'that exact pattern/ending — never a related or similar form. '
              'For example, if asked about ~라면 (or ~이라면), every Korean '
              'example must contain ~라면/~이라면, NOT ~(으)면; if asked about '
              '~(으)면, every example must use ~(으)면, not ~라면. Do not mix '
              'patterns. Before finishing, check that each example literally '
              'contains the requested form.',
        },
        {
          'role': 'user',
          'content': 'Explain this Korean grammar point: $prompt',
        }
      ],
    });

    final response = await http
        .post(
          Uri.parse(config.endpoint),
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw LlmException('Server returned ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final raw = decoded['choices']?[0]?['message']?['content'] as String?;
    if (raw == null || raw.trim().isEmpty) {
      throw LlmException('Could not generate an explanation.');
    }

    var text = raw.trim();
    // Strip ``` / ```markdown fences if the model added them anyway.
    if (text.startsWith('```')) {
      final nl = text.indexOf('\n');
      if (nl != -1) text = text.substring(nl + 1);
      final close = text.lastIndexOf('```');
      if (close != -1) text = text.substring(0, close);
      text = text.trim();
    }

    // Pull the H1 title line ("# ...") out; the rest is the body.
    String title = '';
    final bodyLines = <String>[];
    for (final line in text.split('\n')) {
      final l = line.trimLeft();
      if (title.isEmpty &&
          l.startsWith('# ') &&
          !l.startsWith('## ')) {
        title = l.substring(2).trim();
      } else {
        bodyLines.add(line);
      }
    }
    var mdBody = bodyLines.join('\n').trim();
    if (mdBody.isEmpty) mdBody = text; // no recognizable title — keep it all
    if (mdBody.isEmpty) {
      throw LlmException('Could not generate an explanation.');
    }
    return (title: title.isEmpty ? prompt : title, body: mdBody);
  }

  Future<bool> ping() async {
    try {
      final config = await LlmConfig.load();
      final uri = Uri.parse(config.endpoint).replace(path: '/health');
      final res = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
