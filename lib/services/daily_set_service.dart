import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/vocab_word.dart';

/// Picks the handful of words the combined list shows for one day.
///
/// The rules, in order of priority:
///
///   1. Ten words a day, chosen at random.
///   2. A word already shown in the current CYCLE is not picked again until
///      the cycle ends — so a rotation walks the whole collection instead of
///      re-showing favourites.
///   3. When fewer than ten unseen words remain, the cycle closes and a new
///      one starts. The words needed to fill that last day come from the
///      LEAST recently shown end of the previous cycle, so the words you saw
///      most recently are the last to come back around.
class DailySetService {
  DailySetService._();
  static final DailySetService instance = DailySetService._();

  /// How many words a day the combined list shows.
  static const int perDay = 10;

  static const _kDate = 'daily_date';
  static const _kToday = 'daily_ids';

  /// Ids shown in the current cycle, oldest first. The order is what makes
  /// "least recently shown" answerable.
  static const _kCycle = 'daily_cycle_shown';

  final Random _rng = Random();

  List<String> _today = const [];
  List<String> _cycleShown = const [];
  String _date = '';
  bool _loaded = false;

  List<String> get todayIds => _today;

  /// How far through the current cycle we are — for the "12 / 120" readout.
  int get cycleShownCount => _cycleShown.length;

  static String _stamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _date = p.getString(_kDate) ?? '';
    _today = p.getStringList(_kToday) ?? const [];
    _cycleShown = p.getStringList(_kCycle) ?? const [];
    _loaded = true;
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDate, _date);
    await p.setStringList(_kToday, _today);
    await p.setStringList(_kCycle, _cycleShown);
  }

  /// Returns today's ids, choosing a fresh set if the day rolled over, if the
  /// stored set no longer matches the collection, or if nothing is stored.
  Future<List<String>> ensureToday(List<VocabWord> words) async {
    await _load();

    final available = {for (final w in words) w.id};
    if (available.isEmpty) {
      _today = const [];
      return _today;
    }

    // Drop ids for words that have since been deleted.
    _cycleShown = [for (final id in _cycleShown) if (available.contains(id)) id];
    final kept = [for (final id in _today) if (available.contains(id)) id];

    final target = available.length < perDay ? available.length : perDay;
    final today = _stamp(DateTime.now());
    if (_date == today && kept.length == target) {
      // Already picked for today and still valid.
      if (kept.length != _today.length) {
        _today = kept;
        await _save();
      }
      return _today;
    }

    _today = _pick(available, target);
    _date = today;
    await _save();
    return _today;
  }

  List<String> _pick(Set<String> available, int target) {
    final seen = _cycleShown.toSet();
    final unseen = [for (final id in available) if (!seen.contains(id)) id]
      ..shuffle(_rng);

    if (unseen.length >= target) {
      final picked = unseen.take(target).toList();
      _cycleShown = [..._cycleShown, ...picked];
      return picked;
    }

    // The cycle ends here: take everything still unseen, then top up from the
    // least recently shown words and begin a new cycle with what we picked.
    final picked = [...unseen];
    final byOldestFirst = [
      for (final id in _cycleShown) if (!picked.contains(id)) id,
    ];
    for (final id in byOldestFirst) {
      if (picked.length >= target) break;
      picked.add(id);
    }
    _cycleShown = picked;
    return picked;
  }

  /// Forces a new draw for today — the manual "shuffle" action.
  Future<List<String>> reshuffle(List<VocabWord> words) async {
    await _load();
    final available = {for (final w in words) w.id};
    if (available.isEmpty) return _today = const [];

    // Un-see today's picks first, so a reshuffle doesn't burn through the
    // cycle faster than a day at a time.
    final todaySet = _today.toSet();
    _cycleShown = [for (final id in _cycleShown) if (!todaySet.contains(id)) id];

    final target = available.length < perDay ? available.length : perDay;
    _today = _pick(available, target);
    _date = _stamp(DateTime.now());
    await _save();
    return _today;
  }
}
