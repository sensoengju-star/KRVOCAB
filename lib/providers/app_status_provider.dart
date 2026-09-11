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
  const AppStatusState({this.status = AppStatus.ready, this.note = ''});

  final AppStatus status;

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

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = AppStatusState(
      status: p.getString(_kStatus) == 'construction'
          ? AppStatus.construction
          : AppStatus.ready,
      note: p.getString(_kNote) ?? '',
    );
  }

  Future<void> set(AppStatus status, {String note = ''}) async {
    // A note only means something while work is under way; carrying a stale
    // one into "ready" would describe work that has finished.
    final kept = status == AppStatus.construction ? note.trim() : '';
    state = AppStatusState(status: status, note: kept);
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kStatus, status == AppStatus.construction ? 'construction' : 'ready');
    await p.setString(_kNote, kept);
  }
}

final appStatusProvider =
    StateNotifierProvider<AppStatusNotifier, AppStatusState>(
        (ref) => AppStatusNotifier());
