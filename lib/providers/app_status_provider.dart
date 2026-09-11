import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app is fit to rely on right now.
///
/// Set by hand, not inferred. The obvious automatic signal — a debug build
/// means construction — would say "under construction" permanently, since a
/// debug build is what runs day to day here. A status that never changes
/// carries no information; one you set when you start and finish a piece of
/// work does.
enum AppStatus { ready, construction }

@immutable
class AppStatusState {
  const AppStatusState({
    this.status = AppStatus.ready,
    this.note = '',
    this.since,
  });

  final AppStatus status;

  /// When the status last changed. Null for a status saved before this was
  /// recorded, which is honestly unknown rather than guessed.
  ///
  /// Exists because "I don't remember setting it to Ready" had no answer: the
  /// app knew WHAT the status was but not WHEN it became so.
  final DateTime? since;

  /// What is being worked on, if anything. "Under construction" alone says
  /// something might be broken; the note says which part to avoid.
  final String note;

  bool get isConstruction => status == AppStatus.construction;
}

class AppStatusNotifier extends StateNotifier<AppStatusState> {
  AppStatusNotifier() : super(const AppStatusState()) {
    _load();
  }

  static const _kStatus = 'app_status';
  static const _kNote = 'app_status_note';
  static const _kSince = 'app_status_since';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = AppStatusState(
      status: p.getString(_kStatus) == 'construction'
          ? AppStatus.construction
          : AppStatus.ready,
      note: p.getString(_kNote) ?? '',
      since: DateTime.tryParse(p.getString(_kSince) ?? ''),
    );
  }

  Future<void> set(AppStatus status, {String note = ''}) async {
    // A note only means something while work is under way; carrying a stale
    // one into "ready" would describe work that has finished.
    final kept = status == AppStatus.construction ? note.trim() : '';
    // The clock restarts only when the status itself changes. Editing the
    // note on a construction that began this morning must not make it look
    // as if it began a minute ago.
    final since = (status != state.status || state.since == null)
        ? DateTime.now()
        : state.since;
    state = AppStatusState(status: status, note: kept, since: since);
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kStatus, status == AppStatus.construction ? 'construction' : 'ready');
    await p.setString(_kNote, kept);
    await p.setString(_kSince, since!.toIso8601String());
  }
}

final appStatusProvider =
    StateNotifierProvider<AppStatusNotifier, AppStatusState>(
        (ref) => AppStatusNotifier());

/// "today, 12:40", "yesterday, 09:05", "Sep 9, 17:20".
String describeSince(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final now = DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final time = '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'today, $time';
  if (diff == 1) return 'yesterday, $time';
  final date = '${months[when.month - 1]} ${when.day}';
  return when.year == now.year ? '$date, $time' : '$date ${when.year}, $time';
}
