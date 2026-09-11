import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts how long you actually spend studying, day by day, for one week.
///
/// "Actually" is the whole design. The app now lives in the tray and runs all
/// day, so time-since-launch would report twelve hours. What is counted
/// instead is time the window is in front AND you are doing something — any
/// mouse movement, click, scroll or key. After [idleAfter] of nothing the
/// clock stops, so a window left open over lunch costs nothing.
///
/// Each day is kept for [keepDays] days and then deleted; nothing older ever
/// exists on disk.
class StudyTimeService extends ChangeNotifier {
  StudyTimeService._();
  static final StudyTimeService instance = StudyTimeService._();

  static const _kSeconds = 'study_seconds_v1';
  static const _kFirstDay = 'study_first_day_v1';

  /// How long without input before the clock stops. Long enough to read a
  /// story or think about a word without touching anything; short enough that
  /// walking away is not counted.
  static const Duration idleAfter = Duration(minutes: 2);

  /// Days of history kept, today included.
  static const int keepDays = 7;

  /// The daily goal the dashboard measures against.
  static const Duration dailyGoal = Duration(minutes: 30);

  /// Seconds per day, keyed yyyy-mm-dd.
  final Map<String, int> _seconds = {};
  DateTime? _firstDay;

  bool _foreground = false;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _tick;
  int _unsaved = 0;
  bool _loaded = false;

  /// Whether the clock is running this second.
  bool get isCounting =>
      _foreground && DateTime.now().difference(_lastActivity) < idleAfter;

  Future<void> start() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString(_kSeconds);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is num) _seconds['$k'] = v.toInt();
          });
        }
      }
    } catch (_) {
      // A damaged record costs a week of timings, never the app.
      _seconds.clear();
    }
    _firstDay = DateTime.tryParse(p.getString(_kFirstDay) ?? '');
    if (_firstDay == null) {
      _firstDay = _dayOnly(DateTime.now());
      await p.setString(_kFirstDay, _key(_firstDay!));
    }
    _prune();
    _loaded = true;

    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!isCounting) return;
    final today = _key(DateTime.now());
    _seconds[today] = (_seconds[today] ?? 0) + 1;
    _unsaved++;
    // Written every quarter minute rather than every second: an abrupt
    // shutdown loses at most that much timing, and the disk is left alone.
    if (_unsaved >= 15) unawaited(flush());
    notifyListeners();
  }

  /// Any sign of life — pointer or key.
  void noteActivity() => _lastActivity = DateTime.now();

  /// The window came to the front or left it.
  void setForeground(bool v) {
    if (_foreground == v) return;
    _foreground = v;
    // Coming to the front is deliberately NOT activity. Windows can put this
    // window in front at login with nobody at the desk, and counting that
    // would add phantom minutes every morning. The first real input starts
    // the clock — and moving the mouse into the window is enough.
    if (!v) unawaited(flush());
    notifyListeners();
  }

  Future<void> flush() async {
    if (!_loaded) return;
    _unsaved = 0;
    _prune();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSeconds, jsonEncode(_seconds));
  }

  /// Deletes every day older than the window. The deletion the week-long
  /// promise depends on — run on load, on save, and whenever a day is read.
  void _prune() {
    final oldest = _dayOnly(DateTime.now())
        .subtract(const Duration(days: keepDays - 1));
    _seconds.removeWhere((k, _) {
      final d = DateTime.tryParse(k);
      return d == null || d.isBefore(oldest);
    });
  }

  // --- reading ------------------------------------------------------------

  /// The last [keepDays] days, oldest first, today last.
  List<({DateTime day, Duration time})> week() {
    final today = _dayOnly(DateTime.now());
    return [
      for (var i = keepDays - 1; i >= 0; i--)
        () {
          final d = today.subtract(Duration(days: i));
          return (day: d, time: Duration(seconds: _seconds[_key(d)] ?? 0));
        }(),
    ];
  }

  Duration get today =>
      Duration(seconds: _seconds[_key(DateTime.now())] ?? 0);

  /// How many days the average is taken over.
  ///
  /// Only days since tracking began count. Averaging a first day's twenty
  /// minutes over seven days would report three, and tell someone who has
  /// just started that they are failing at something they began this morning.
  int get daysTracked {
    final today = _dayOnly(DateTime.now());
    final first = _firstDay ?? today;
    final span = today.difference(first).inDays + 1;
    return span.clamp(1, keepDays);
  }

  /// Mean time per day over the tracked span. Days in the span with no study
  /// count as zero — skipping them would flatter the number.
  Duration get averagePerDay {
    final days = week().sublist(keepDays - daysTracked);
    final total = days.fold<int>(0, (sum, d) => sum + d.time.inSeconds);
    return Duration(seconds: (total / days.length).round());
  }

  bool get meetsGoal => averagePerDay > dailyGoal;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
