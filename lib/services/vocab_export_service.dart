import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocab_word.dart';
import 'inbox_service.dart';
import 'storage_service.dart';

/// Writes the collection into the synced folder so the phone can read it.
///
/// The inbox carries words INTO the app; this is the return leg. Same folder,
/// same sync client, no server — but deliberately one-way: the app writes,
/// the phone reads. Two writers over one dataset is a different and far
/// larger problem, and nothing about looking a word up on a bus needs it.
///
/// Written into `export/` rather than the folder root, because the root is
/// scanned for incoming words: a `vocab.json` sitting there would be read as
/// an import and then filed away into `processed/`.
class VocabExportService {
  VocabExportService._();
  static final VocabExportService instance = VocabExportService._();

  static const _kEnabled = 'vocab_export_enabled';
  static const String folderName = 'export';

  /// Long enough that a burst of edits — an import of twenty words, a session
  /// of status changes — costs one write instead of twenty.
  static const _debounce = Duration(seconds: 6);

  Timer? _pending;
  StreamSubscription<void>? _watch;
  DateTime? lastExport;

  Future<bool> enabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? true;
  }

  Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
    if (v) {
      await exportNow();
    } else {
      await _removeFiles();
    }
  }

  /// Re-exports shortly after the collection changes, so what the phone sees
  /// is never far behind what the app holds.
  void armAutoExport() {
    _watch?.cancel();
    try {
      _watch = StorageService.instance.box.watch().listen((_) {
        _pending?.cancel();
        _pending = Timer(_debounce, () => unawaited(exportNow()));
      });
    } catch (e) {
      debugPrint('[VocabExport] could not watch the box: $e');
    }
  }

  Future<void> dispose() async {
    _pending?.cancel();
    await _watch?.cancel();
    _watch = null;
  }

  /// Writes both files. Silent when there is no folder or the feature is off.
  Future<bool> exportNow() async {
    if (!await enabled()) return false;
    final root = await InboxService.instance.folder();
    if (root == null) return false;
    if (!Directory(root).existsSync()) return false;

    final dir = Directory('$root${Platform.pathSeparator}$folderName');
    final words = StorageService.instance.box.values.toList()
      ..sort((a, b) => a.hangul.compareTo(b.hangul));

    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      await _write(dir, 'vocab.md', _markdown(words));
      await _write(dir, 'vocab.json', _json(words));
      lastExport = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('[VocabExport] failed: $e');
      return false;
    }
  }

  /// Writes [content] to [name], but only when it differs from what is
  /// already there.
  ///
  /// Two things matter here, both learned the hard way. The export is
  /// triggered by ANY change to the box — including the correct/incorrect
  /// counters, which move on every review answer — so without this comparison
  /// a review session rewrites the whole collection card by card.
  ///
  /// And the write is in place, not delete-then-rename: a sync client sends
  /// every deletion to its trash, so the old approach left a numbered copy of
  /// the entire vocabulary in iCloud's bin on each export. An in-place write
  /// can in principle be read half-finished, but that window is milliseconds
  /// and self-correcting, while the litter was permanent and growing.
  Future<void> _write(Directory dir, String name, String content) async {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (file.existsSync()) {
      try {
        if (await file.readAsString() == content) return;
      } catch (_) {
        // Unreadable — fall through and replace it.
      }
    }
    await file.writeAsString(content);
  }

  Future<void> _removeFiles() async {
    final root = await InboxService.instance.folder();
    if (root == null) return;
    final dir = Directory('$root${Platform.pathSeparator}$folderName');
    for (final name in const ['vocab.md', 'vocab.json']) {
      try {
        final f = File('${dir.path}${Platform.pathSeparator}$name');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// The one a person reads. Plain Markdown so the Files app renders it and
  /// any note-taking app can open it.
  String _markdown(List<VocabWord> words) {
    final learning = [
      for (final w in words)
        if (w.status != WordStatus.reinforcement) w,
    ];
    final reinforced = [
      for (final w in words)
        if (w.status == WordStatus.reinforcement) w,
    ];
    final b = StringBuffer()
      ..writeln('# Maldari vocabulary')
      ..writeln()
      ..writeln('${words.length} words · ${reinforced.length} reinforced · '
          '${learning.length} learning')
      ..writeln()
      // Deliberately no timestamp: a clock in the header would make every
      // export differ from the last, and the unchanged-content check that
      // keeps this from churning the cloud would never once hold.
      ..writeln('Written by Maldari, and rewritten whenever the collection '
          'changes. Edits here are not read back.')
      ..writeln();

    void section(String title, List<VocabWord> list) {
      if (list.isEmpty) return;
      b
        ..writeln('## $title (${list.length})')
        ..writeln();
      for (final w in list) {
        b.write('- **${w.hangul}**');
        if (w.romanization.trim().isNotEmpty) b.write(' *(${w.romanization})*');
        if (w.englishMeaning.trim().isNotEmpty) b.write(' — ${w.englishMeaning}');
        if (w.politeForm.trim().isNotEmpty) b.write(' · ${w.politeForm}');
        b.writeln();
      }
      b.writeln();
    }

    section('Reinforced', reinforced);
    section('Learning', learning);
    return b.toString();
  }

  /// The one a Shortcut reads.
  String _json(List<VocabWord> words) => const JsonEncoder.withIndent('  ')
      .convert({
        // No exportedAt, for the same reason the Markdown carries no
        // timestamp: it would change on every run and force a pointless
        // rewrite of the file.
        'count': words.length,
        'words': [
          for (final w in words)
            {
              'hangul': w.hangul,
              'romanization': w.romanization,
              'englishMeaning': w.englishMeaning,
              'partOfSpeech': w.partOfSpeech,
              'politeForm': w.politeForm,
              'status': w.status == WordStatus.reinforcement
                  ? 'reinforcement'
                  : 'learning',
              'correct': w.correctCount,
              'incorrect': w.incorrectCount,
            },
        ],
      });
}
