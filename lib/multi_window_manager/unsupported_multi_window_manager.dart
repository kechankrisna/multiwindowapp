import 'multi_window_manager.dart';
import 'sub_display_state.dart';

/// Fallback implementation for platforms that do not support multi-window
/// or secondary displays (iOS, Web).
///
/// [isSupported] always returns `false`. All other methods are safe no-ops so
/// callers never need to guard against platform checks at the call site.
class UnsupportedMultiWindowManager extends MultiWindowManager {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<void> openSubWindow(Map<String, dynamic> argument) async {}

  @override
  Future<void> sendStateToSubDisplay(SubDisplayState state) async {}

  @override
  Future<void> closeAll() async {}
}
