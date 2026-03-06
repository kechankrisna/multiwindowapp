import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'sub_display_state.dart';
import 'desktop_multi_window_manager.dart';
import 'android_second_display_manager.dart';
import 'unsupported_multi_window_manager.dart';

/// Platform-agnostic API for multi-window and dual-display features.
///
/// Use [MultiWindowManager.instance] to obtain the singleton — the factory
/// returns the correct implementation for the current platform automatically.
///
/// This class is the public surface of the `multi_window_manager` package
/// boundary. Moving [lib/multi_window_manager/] into a standalone pub package
/// requires zero API changes.
abstract class MultiWindowManager {
  // Singleton — resolved once and cached so the platform is never queried twice.
  static MultiWindowManager? _instance;

  static Future<MultiWindowManager> instance() async {
    _instance ??= await _create();
    return _instance!;
  }

  static Future<MultiWindowManager> _create() async {
    if (kIsWeb) return UnsupportedMultiWindowManager();
    if (Platform.isAndroid) return AndroidSecondDisplayManager();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return DesktopMultiWindowManager();
    }
    return UnsupportedMultiWindowManager(); // iOS and any future unsupported platform
  }

  /// Returns `true` when this platform supports an active secondary display
  /// or multi-window. On Android the result reflects whether a second
  /// physical display is currently connected.
  Future<bool> isSupported();

  /// Opens a new independent sub-window (desktop only).
  /// [argument] is passed to the sub-window's Flutter engine via JSON.
  Future<void> openSubWindow(Map<String, dynamic> argument);

  /// Sends a [SubDisplayState] snapshot to the secondary display (Android only).
  /// Implementors should accept this call safely on any platform.
  Future<void> sendStateToSubDisplay(SubDisplayState state);

  /// Closes all open sub-windows and releases the secondary display engine.
  Future<void> closeAll();
}
