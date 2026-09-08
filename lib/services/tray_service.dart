import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps Maldari alive in the notification area after its window is closed.
///
/// The point is the inbox. Words captured on the phone are imported at launch
/// and on window focus — neither of which happens while the app is shut — so
/// living in the tray is what turns "capture it and it appears" from a claim
/// into a fact. Everything else the tray does is in service of that.
class TrayService with TrayListener, WindowListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  static const _kIntervalSeconds = 'inbox_poll_seconds';
  static const _kIntervalMinutesLegacy = 'inbox_poll_minutes';
  static const _kRunInTray = 'run_in_tray';

  /// How often to look in the inbox, in SECONDS.
  ///
  /// Half a minute by default. A check on an empty folder is three existsSync
  /// calls and a directory listing — free in any sense that matters, and
  /// nothing is sent anywhere unless a file is actually there. The cost of
  /// looking often is nil; the cost of looking rarely is a word sitting on
  /// disk unnoticed.
  static const int defaultIntervalSeconds = 30;
  static const List<int> intervalChoices = [15, 30, 60, 300, 900, 3600];

  /// "15 sec", "5 min", "1 hour".
  static String intervalLabel(int seconds) {
    if (seconds < 60) return '$seconds sec';
    if (seconds >= 3600) return '${seconds ~/ 3600} hour';
    return '${seconds ~/ 60} min';
  }

  Timer? _poll;

  /// Runs an import, and reports whether it found anything. Set by main,
  /// which owns the provider container.
  Future<bool> Function()? onImport;

  /// Called when the window is hidden, so on-demand services can stand down.
  Future<void> Function()? onHide;

  /// Called for a real quit, so shutdown still flushes and closes properly.
  Future<void> Function()? onQuit;

  bool _started = false;

  Future<bool> runInTray() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kRunInTray) ?? true;
  }

  Future<void> setRunInTray(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRunInTray, v);
    if (v) {
      await start();
    } else {
      await stop();
    }
  }

  /// The argument a login-launched copy is given, so it can come up hidden.
  ///
  /// Starting with Windows and then throwing a window in your face every
  /// morning would be its own kind of rude — the point is to be there, not to
  /// be seen.
  static const String hiddenFlag = '--tray';

  bool _autostartReady = false;

  void _prepareAutostart() {
    if (_autostartReady) return;
    launchAtStartup.setup(
      appName: 'Maldari',
      appPath: Platform.resolvedExecutable,
      args: [hiddenFlag],
    );
    _autostartReady = true;
  }

  Future<bool> startsWithWindows() async {
    try {
      _prepareAutostart();
      return await launchAtStartup.isEnabled();
    } catch (e) {
      debugPrint('[TrayService] autostart unreadable: $e');
      return false;
    }
  }

  Future<bool> setStartsWithWindows(bool v) async {
    try {
      _prepareAutostart();
      if (v) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      return await launchAtStartup.isEnabled();
    } catch (e) {
      debugPrint('[TrayService] could not change autostart: $e');
      return false;
    }
  }

  Future<int> intervalSeconds() async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getInt(_kIntervalSeconds);
    if (stored != null) {
      return intervalChoices.contains(stored)
          ? stored
          : defaultIntervalSeconds;
    }
    // Carry over a setting made when this was measured in minutes, so an
    // existing choice is honoured rather than silently reset.
    final legacy = p.getInt(_kIntervalMinutesLegacy);
    if (legacy != null) {
      final asSeconds = legacy * 60;
      if (intervalChoices.contains(asSeconds)) return asSeconds;
    }
    return defaultIntervalSeconds;
  }

  Future<void> setIntervalSeconds(int seconds) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kIntervalSeconds, seconds);
    await p.remove(_kIntervalMinutesLegacy);
    await _armPoll();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

    trayManager.addListener(this);
    windowManager.addListener(this);
    // The window manager must be told not to close, or the X quits the app
    // before we get a say.
    await windowManager.setPreventClose(true);

    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('Maldari — Korean vocabulary');
      await _rebuildMenu();
    } catch (e) {
      debugPrint('[TrayService] tray unavailable: $e');
    }

    await _armPoll();
  }

  Future<void> stop() async {
    _poll?.cancel();
    _poll = null;
    if (!_started) return;
    _started = false;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  Future<void> _rebuildMenu() async {
    final every = intervalLabel(await intervalSeconds());
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: 'Open Maldari'),
      MenuItem(key: 'import', label: 'Import words now'),
      MenuItem.separator(),
      MenuItem(
        key: 'interval',
        label: 'Checking often, up to every $every when idle',
        disabled: true,
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  /// How long to wait after each fruitless look, in seconds.
  ///
  /// Checking is nearly free, so the first few looks come quickly: a word you
  /// just captured should not sit on disk waiting out a fixed interval. It is
  /// only after a run of empty folders — nobody is capturing anything — that
  /// backing off is worth anything, and even then it never exceeds the
  /// interval chosen in Settings.
  static const List<int> _backoff = [2, 3, 5, 8, 13, 21];

  /// Consecutive checks that found nothing.
  int _misses = 0;

  Future<void> _armPoll() async {
    _poll?.cancel();
    final ceiling = await intervalSeconds();
    final step = _misses < _backoff.length ? _backoff[_misses] : ceiling;
    _poll = Timer(Duration(seconds: min(step, ceiling)), _tick);
    if (_started) await _rebuildMenu();
  }

  Future<void> _tick() async {
    final found = await onImport?.call() ?? false;
    // Something arrived: whoever sent it may be sending more, so go back to
    // looking often.
    _misses = found ? 0 : _misses + 1;
    await _armPoll();
  }

  /// Drops back to checking eagerly. Called when there is fresh reason to
  /// expect something — the window coming back, or an import by hand.
  Future<void> quicken() async {
    _misses = 0;
    await _armPoll();
  }

  /// Brings the window back — from the tray, or from a second launch.
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
    // You are looking at it again; look for words again too.
    await quicken();
  }

  Future<void> hide() async {
    await windowManager.hide();
    await onHide?.call();
  }

  /// The only path that actually ends the process.
  Future<void> quit() async {
    _poll?.cancel();
    await onQuit?.call();
    await stop();
    exit(0);
  }

  // --- tray ---------------------------------------------------------------

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        show();
      case 'import':
        show();
        quicken();
      case 'quit':
        quit();
    }
  }

  // --- window -------------------------------------------------------------

  @override
  void onWindowClose() async {
    // Closing hides; only the tray's Quit ends the app. A close that silently
    // killed a resident app would make "is it running?" unanswerable.
    if (await runInTray()) {
      await hide();
    } else {
      await quit();
    }
  }
}
