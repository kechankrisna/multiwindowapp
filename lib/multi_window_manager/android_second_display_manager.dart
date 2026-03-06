import 'package:flutter/services.dart';

import 'multi_window_manager.dart';
import 'sub_display_state.dart';

/// Android implementation using a custom MethodChannel that bridges to
/// [SecondDisplayPlugin] (Kotlin) which manages the Android Presentation API
/// and the secondary FlutterEngine.
class AndroidSecondDisplayManager extends MultiWindowManager {
  static const _channel = MethodChannel('second_display');

  // Cached after the first platform call — isSupported() never queries twice.
  bool? _cachedSupported;

  @override
  Future<bool> isSupported() async {
    _cachedSupported ??=
        await _channel.invokeMethod<bool>('isSecondDisplayAvailable') ?? false;
    return _cachedSupported!;
  }

  /// No-op on Android — sub-windows are desktop-only.
  @override
  Future<void> openSubWindow(Map<String, dynamic> argument) async {}

  /// Sends a full state snapshot to the secondary display in a single call.
  /// Callers should debounce rapid updates (see main_window.dart).
  @override
  Future<void> sendStateToSubDisplay(SubDisplayState state) async {
    await _channel.invokeMethod<void>('sendState', state.toJson());
  }

  @override
  Future<void> closeAll() async {
    await _channel.invokeMethod<void>('releaseSecondDisplay');
    _cachedSupported = null; // reset so re-connection is detected correctly
  }
}
