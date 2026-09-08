import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocab_word.dart';
import 'storage_service.dart';

/// Picks up words captured on the phone and files them into the collection.
///
/// The phone writes a JSON file into a cloud-synced folder; the sync client
/// puts it on this disk; this reads it. Maldari itself never talks to a cloud
/// service, which is the whole point of the design — no account, no OAuth, no
/// API key on the desktop, nothing to keep running.
///
/// A file is consumed exactly once: it is moved into `processed/` only after
/// its words are in the box, so a crash mid-import means the file is simply
/// picked up again next launch.
class InboxService {
  InboxService._();
  static final InboxService instance = InboxService._();

  static const _kFolder = 'inbox_folder';

  /// Where Google Drive for desktop mounts by default. Only a starting point —
  /// the real path is whatever the user sets in Settings.
  static const defaultFolder = r'G:\My Drive\Maldari\inbox';

  Future<String?> folder() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kFolder)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setFolder(String path) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFolder, path.trim());
  }

  Future<void> clearFolder() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFolder);
  }

  /// Reads every `*.json` in the inbox and adds the words it doesn't already
  /// have. Safe to call as often as you like — importing the same file twice
  /// adds nothing, and neither does a word already in the collection.
  Future<InboxResult> importNow() async {
    final path = await folder();
    if (path == null) {
      return const InboxResult(configured: false);
    }

    final dir = Directory(path);
    if (!dir.existsSync()) {
      return InboxResult(
        errors: ['Folder not found: $path'],
      );
    }

    final files = <File>[
      for (final e in dir.listSync())
        if (e is File && e.path.toLowerCase().endsWith('.json')) e,
    ]..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) return const InboxResult();

    final box = StorageService.instance.box;
    // Dedupe on the same key the merge tool uses, so an import can't create
    // the duplicates that tool exists to clean up.
    final known = <String>{
      for (final w in box.values) w.hangul.trim().toLowerCase(),
    };

    var added = 0;
    var skipped = 0;
    var handled = 0;
    final errors = <String>[];

    for (final file in files) {
      List<Map<String, dynamic>> entries;
      try {
        entries = _parse(await file.readAsString());
      } catch (e) {
        // Most often a file still syncing — leave it alone and try again on
        // the next run rather than importing half of it.
        errors.add('${_name(file)}: ${_short(e)}');
        continue;
      }

      var wroteAny = false;
      for (final entry in entries) {
        final hangul = (entry['hangul'] ?? '').toString().trim();
        if (hangul.isEmpty) continue;
        final key = hangul.toLowerCase();
        if (!known.add(key)) {
          skipped++;
          continue;
        }
        try {
          final word = _wordFrom(entry, hangul);
          await box.put(word.id, word);
          added++;
          wroteAny = true;
        } catch (e) {
          known.remove(key);
          errors.add('$hangul: ${_short(e)}');
        }
      }

      // Only retire the file once its words are actually in the box.
      if (wroteAny || entries.isNotEmpty) {
        final moved = await _archive(file, dir);
        if (moved) handled++;
      }
    }

    // Words that just landed must survive a crash a second later, not in 400
    // milliseconds' time.
    if (added > 0) await StorageService.instance.flushAll();

    return InboxResult(
      added: added,
      skipped: skipped,
      files: handled,
      errors: errors,
    );
  }

  /// Accepts either a bare array or `{"words": [...]}`, since a shortcut is
  /// easy to build either way and neither is worth failing over.
  List<Map<String, dynamic>> _parse(String raw) {
    final decoded = jsonDecode(raw);
    final list = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['words'] as List? ?? const []) : const []);
    return [
      for (final e in list)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  VocabWord _wordFrom(Map<String, dynamic> e, String hangul) {
    final pos = (e['partOfSpeech'] ?? '').toString().trim();
    final status = (e['status'] ?? '').toString().trim().toLowerCase();

    return VocabWord(
      // Same shape the add sheet uses, with a suffix so a batch landing in the
      // same millisecond can't collide.
      id: 'w-${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      hangul: hangul,
      romanization: (e['romanization'] ?? '').toString().trim(),
      englishMeaning: (e['englishMeaning'] ?? e['english'] ?? '')
          .toString()
          .trim(),
      partOfSpeech:
          PartsOfSpeech.all.contains(pos) ? pos : PartsOfSpeech.noun,
      politeForm: (e['politeForm'] ?? '').toString().trim(),
      dateAdded: DateTime.now(),
      status: status == 'reinforcement' || status == 'reinforced'
          ? WordStatus.reinforcement
          : WordStatus.learning,
    );
  }

  int _seq = 0;

  /// Moves a consumed file into `processed/`. Never deletes: the same rule the
  /// rest of the app follows, and a mis-parsed import is recoverable by hand.
  Future<bool> _archive(File file, Directory dir) async {
    try {
      final done = Directory('${dir.path}${Platform.pathSeparator}processed');
      if (!done.existsSync()) done.createSync(recursive: true);
      var target = '${done.path}${Platform.pathSeparator}${_name(file)}';
      if (File(target).existsSync()) {
        target = '$target.${DateTime.now().millisecondsSinceEpoch}';
      }
      await file.rename(target);
      return true;
    } catch (e) {
      // A file the sync client still holds open stays put and is skipped next
      // time by the hangul dedupe, so nothing is imported twice.
      debugPrint('[InboxService] could not archive ${_name(file)}: $e');
      return false;
    }
  }

  static String _name(File f) => f.path.split(Platform.pathSeparator).last;

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

@immutable
class InboxResult {
  const InboxResult({
    this.added = 0,
    this.skipped = 0,
    this.files = 0,
    this.errors = const [],
    this.configured = true,
  });

  /// Words written to the collection.
  final int added;

  /// Words the collection already had.
  final int skipped;

  /// Files consumed and moved to `processed/`.
  final int files;

  final List<String> errors;

  /// False when no inbox folder has been set yet.
  final bool configured;

  bool get changedAnything => added > 0;
  bool get isEmpty => added == 0 && skipped == 0 && errors.isEmpty;

  String get summary {
    if (!configured) return 'No inbox folder set.';
    if (isEmpty) return 'Nothing new in the inbox.';
    final parts = <String>[
      if (added > 0) '$added added',
      if (skipped > 0) '$skipped already known',
      if (errors.isNotEmpty) '${errors.length} problem'
          '${errors.length == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }
}
