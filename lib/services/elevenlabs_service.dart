import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ElevenLabs text-to-speech.
///
/// The API key is entered by the user in Settings and lives only in
/// SharedPreferences on this machine. It is NEVER written to source, to a
/// file inside the repository, or to any log — this project is a public
/// repo, and a committed key is a leaked key within minutes.
///
/// Every clip is cached on disk by (text, voice, model), so re-listening to a
/// story costs nothing and works offline. Stories change rarely and get
/// replayed often, which makes the cache do most of the work.
class ElevenLabsService {
  ElevenLabsService._();
  static final ElevenLabsService instance = ElevenLabsService._();

  static const _kApiKey = 'eleven_api_key';
  static const _kVoiceId = 'eleven_voice_id';
  static const _kModelId = 'eleven_model_id';

  /// A stock ElevenLabs voice, used until the user picks their own. Any voice
  /// can speak Korean when paired with a multilingual model.
  static const defaultVoiceId = '21m00Tcm4TlvDq8ikWAM';

  /// Korean-capable models, best-quality first.
  static const models = <String, String>{
    'eleven_multilingual_v2': 'Multilingual v2 — best quality',
    'eleven_flash_v2_5': 'Flash v2.5 — faster, cheaper',
  };

  static const _base = 'https://api.elevenlabs.io/v1';

  Directory? _cacheDir;

  Future<String?> apiKey() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_kApiKey)?.trim();
    return (k == null || k.isEmpty) ? null : k;
  }

  Future<bool> get isConfigured async => (await apiKey()) != null;

  Future<String> voiceId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kVoiceId)?.trim();
    return (v == null || v.isEmpty) ? defaultVoiceId : v;
  }

  Future<String> modelId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kModelId) ?? models.keys.first;
  }

  Future<void> save({String? apiKey, String? voiceId, String? modelId}) async {
    final p = await SharedPreferences.getInstance();
    if (apiKey != null) await p.setString(_kApiKey, apiKey.trim());
    if (voiceId != null) await p.setString(_kVoiceId, voiceId.trim());
    if (modelId != null) await p.setString(_kModelId, modelId);
  }

  Future<void> clearKey() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kApiKey);
  }

  /// Voices on the account. Requires the key to carry `voices_read`; a
  /// TTS-only key returns a permission error, which is why the UI also
  /// accepts a voice id typed by hand.
  Future<List<({String id, String name})>> listVoices() async {
    final key = await apiKey();
    if (key == null) throw const ElevenLabsException('No API key saved.');

    final res = await http.get(
      Uri.parse('$_base/voices'),
      headers: {'xi-api-key': key},
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw ElevenLabsException(_readError(res));
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final voices = (decoded['voices'] as List?) ?? const [];
    return [
      for (final v in voices.whereType<Map>())
        (
          id: (v['voice_id'] ?? '').toString(),
          name: (v['name'] ?? 'unnamed').toString(),
        ),
    ].where((v) => v.id.isNotEmpty).toList();
  }

  /// Path to an MP3 of [text], synthesizing it only if it isn't cached.
  Future<File> audioFor(String text) async {
    final key = await apiKey();
    if (key == null) throw const ElevenLabsException('No API key saved.');

    final voice = await voiceId();
    final model = await modelId();
    final file = await _cacheFile(text, voice, model);
    if (await file.exists() && await file.length() > 0) return file;

    final res = await http
        .post(
          Uri.parse('$_base/text-to-speech/$voice'),
          headers: {
            'xi-api-key': key,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          body: jsonEncode({'text': text, 'model_id': model}),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode != 200) {
      throw ElevenLabsException(_readError(res));
    }
    if (res.bodyBytes.isEmpty) {
      throw const ElevenLabsException('ElevenLabs returned empty audio.');
    }

    // Write to a temp name first, then rename: a clip interrupted mid-write
    // must never be left behind as a valid-looking cache entry.
    final tmp = File('${file.path}.part');
    await tmp.writeAsBytes(res.bodyBytes, flush: true);
    await tmp.rename(file.path);
    return file;
  }

  /// Synthesizes a short phrase purely to check the key works.
  Future<void> testKey() async => audioFor('안녕하세요');

  Future<Directory> _dir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}narration_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  Future<File> _cacheFile(String text, String voice, String model) async {
    final dir = await _dir();
    final digest = sha1.convert(utf8.encode('$voice|$model|$text')).toString();
    return File('${dir.path}${Platform.pathSeparator}$digest.mp3');
  }

  /// Total bytes held by the clip cache — shown in Settings.
  Future<int> cacheSize() async {
    try {
      final dir = await _dir();
      var total = 0;
      await for (final f in dir.list()) {
        if (f is File) total += await f.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearCache() async {
    try {
      final dir = await _dir();
      await for (final f in dir.list()) {
        if (f is File) await f.delete();
      }
    } catch (e) {
      _log('clearCache failed: $e');
    }
  }

  /// Pulls the human-readable half out of an ElevenLabs error body.
  String _readError(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final detail = decoded['detail'];
      if (detail is Map) {
        final msg = detail['message'] ?? detail['status'];
        if (msg != null) return '$msg (HTTP ${res.statusCode})';
      }
      if (detail is String) return '$detail (HTTP ${res.statusCode})';
    } catch (_) {}
    return 'ElevenLabs returned HTTP ${res.statusCode}.';
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ElevenLabs] $msg');
    }
  }
}

class ElevenLabsException implements Exception {
  const ElevenLabsException(this.message);
  final String message;
  @override
  String toString() => message;
}
