import 'dart:io';

import 'package:flutter/foundation.dart';

/// Ensures only one Maldari runs at a time.
///
/// This is not a nicety. A tray app holds the Hive files open for as long as
/// it lives, so a second copy would find every box locked and be turned away
/// at the door — which is exactly the "it erased everything" scare this design
/// is meant to end. Claiming the slot happens BEFORE storage is touched, so a
/// second launch never gets near the data.
///
/// The claim is a loopback socket rather than a lock file: a lock file
/// outlives a hard kill and needs stale-detection, whereas a socket is
/// released by the OS the moment the process dies, however it dies.
class SingleInstance {
  SingleInstance._();

  /// Arbitrary high port. Loopback only, so nothing outside this machine can
  /// reach it.
  ///
  /// Also hard-coded in windows/runner/main.cpp, which pokes it from native
  /// code before Flutter starts — that is the fast path for a second launch.
  /// This Dart-side claim stays as the fallback. Change one, change both.
  static const int _port = 45731;

  static ServerSocket? _server;

  /// True if this process is the one and only. False means another copy is
  /// already running and has been asked to show itself — the caller should
  /// exit without opening anything.
  static Future<bool> claim({required VoidCallback onSecondLaunch}) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port);
      _server!.listen((socket) {
        socket.destroy();
        // Someone tried to launch us again — they want the window, not a
        // second app.
        onSecondLaunch();
      });
      return true;
    } catch (_) {
      await _poke();
      return false;
    }
  }

  /// Tells the running instance to come to the front.
  static Future<void> _poke() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
    } catch (e) {
      // The port is taken by something that isn't us. Nothing to hand over
      // to; the caller still exits rather than risking two copies on one set
      // of files.
      debugPrint('[SingleInstance] could not reach the running copy: $e');
    }
  }

  static Future<void> release() async {
    await _server?.close();
    _server = null;
  }
}
