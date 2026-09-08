import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inbox_service.dart';

/// A record of one import that actually did something.
@immutable
class ImportLogEntry {
  const ImportLogEntry({
    required this.at,
    required this.summary,
    this.corrections = const [],
    this.errors = const [],
  });

  final DateTime at;

  /// The same line the snackbar showed, kept verbatim so the log and the
  /// moment agree.
  final String summary;

  final List<String> corrections;
  final List<String> errors;

  bool get hadTrouble => errors.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'summary': summary,
        'corrections': corrections,
        'errors': errors,
      };

  static ImportLogEntry? decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return ImportLogEntry(
        at: DateTime.tryParse((m['at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        summary: (m['summary'] ?? '').toString(),
        corrections: [for (final c in (m['corrections'] as List? ?? [])) '$c'],
        errors: [for (final e in (m['errors'] as List? ?? [])) '$e'],
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the inbox has done, kept across restarts.
///
/// An import happens on its own — at launch, ten seconds later, and on every
/// window focus — so the message announcing it is easy to miss entirely. A
/// correction in particular is a decision made about your words while you
/// weren't looking; being able to go back and read it is the difference
/// between a tool you can check and one you have to trust.
class ImportLog {
  ImportLog._();
  static final ImportLog instance = ImportLog._();

  static const _kEntries = 'import_log_v1';

  /// Enough to cover weeks of use without the list becoming its own problem.
  static const int limit = 50;

  /// Records [result], unless nothing happened. The automatic import runs
  /// several times a session and would otherwise fill the log with "nothing
  /// new" — a log of non-events is one nobody reads.
  Future<void> record(InboxResult result) async {
    if (!result.configured) return;
    final worthKeeping = result.added > 0 ||
        result.corrections.isNotEmpty ||
        result.errors.isNotEmpty;
    if (!worthKeeping) return;

    final entry = ImportLogEntry(
      at: DateTime.now(),
      summary: result.summary,
      corrections: result.corrections,
      errors: result.errors,
    );

    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_kEntries) ?? <String>[];
    list.insert(0, jsonEncode(entry.toJson()));
    if (list.length > limit) list.removeRange(limit, list.length);
    await p.setStringList(_kEntries, list);
  }

  Future<List<ImportLogEntry>> entries() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kEntries) ?? const <String>[];
    return [
      for (final r in raw)
        if (ImportLogEntry.decode(r) case final e?) e,
    ];
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kEntries);
  }
}
