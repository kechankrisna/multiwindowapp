import 'dart:convert';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'multi_window_manager.dart';
import 'sub_display_state.dart';

/// Desktop implementation (Windows, macOS, Linux).
///
/// Each [openSubWindow] call spawns a **new OS process** running a completely
/// independent Flutter engine — there is no shared state with the main window.
class DesktopMultiWindowManager extends MultiWindowManager {
  int _windowCount = 0;
  final List<WindowController> _controllers = [];

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> openSubWindow(Map<String, dynamic> argument) async {
    _windowCount++;
    final controller = await DesktopMultiWindow.createWindow(
      jsonEncode({...argument, 'windowNumber': _windowCount}),
    );
    await controller.setFrame(const Rect.fromLTWH(200, 200, 480, 640));
    await controller.setTitle('Sub Window $_windowCount');
    await controller.show();
    _controllers.add(controller);
  }

  /// No-op on desktop — state sync is Android-only.
  @override
  Future<void> sendStateToSubDisplay(SubDisplayState state) async {}

  @override
  Future<void> closeAll() async {
    for (final c in _controllers) {
      await c.close();
    }
    _controllers.clear();
  }
}
