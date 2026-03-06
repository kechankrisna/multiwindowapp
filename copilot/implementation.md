# Implementation Plan: Flutter Multi-Window / Dual-Display App

## Environment
- Flutter SDK: ^3.10.4 / Dart: ^3.10.4
- Android package: `com.example.multiwindowapp`, Kotlin JVM 17
- Existing `MainActivity`: extends `FlutterActivity` (bare)
- Existing `lib/main.dart`: default counter template

---

## Architecture

```
lib/
  main.dart                                ← entry point router
  main_window.dart                         ← main/cashier UI
  sub_window.dart                          ← desktop sub-window (own engine)
  sub_screen_entry.dart                    ← Android sub-screen entry (own engine)
  multi_window_manager/                    ← future package boundary
    multi_window_manager.dart              ← abstract API + singleton factory
    sub_display_state.dart                 ← sealed state class + JSON codec
    desktop_multi_window_manager.dart      ← Windows/macOS/Linux impl
    android_second_display_manager.dart    ← Android impl (MethodChannel)
    unsupported_multi_window_manager.dart  ← iOS/Web impl (no-op)

android/app/src/main/kotlin/com/example/multiwindowapp/
  MainActivity.kt                          ← updated: register plugin + dispose
  SecondDisplayPlugin.kt                   ← new: Presentation API + 2nd FlutterEngine
```

---

## Phase 1 — pubspec.yaml

Add under `dependencies`:
```yaml
desktop_multi_window: ^0.2.0
```

---

## Phase 2 — sub_display_state.dart

Dart 3 sealed class with full JSON codec:

```dart
sealed class SubDisplayState {
  const SubDisplayState();
  Map<String, dynamic> toJson();
  factory SubDisplayState.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'idle'           => const IdleState(),
      'order_summary'  => OrderSummaryState.fromJson(json),
      'payment_prompt' => PaymentPromptState.fromJson(json),
      _                => const IdleState(),
    };
  }
}

final class IdleState extends SubDisplayState {
  const IdleState();
  Map<String, dynamic> toJson() => {'type': 'idle'};
}

final class OrderSummaryState extends SubDisplayState {
  const OrderSummaryState({required this.items, required this.total});
  final List<Map<String, dynamic>> items; // [{name, qty, price}]
  final double total;
  factory OrderSummaryState.fromJson(Map<String, dynamic> json) => OrderSummaryState(
    items: List<Map<String, dynamic>>.from(
      (json['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    ),
    total: (json['total'] as num).toDouble(),
  );
  Map<String, dynamic> toJson() => {'type': 'order_summary', 'items': items, 'total': total};
}

final class PaymentPromptState extends SubDisplayState {
  const PaymentPromptState({required this.total});
  final double total;
  factory PaymentPromptState.fromJson(Map<String, dynamic> json) =>
      PaymentPromptState(total: (json['total'] as num).toDouble());
  Map<String, dynamic> toJson() => {'type': 'payment_prompt', 'total': total};
}
```

---

## Phase 3 — multi_window_manager.dart

Abstract class + singleton factory:

```dart
abstract class MultiWindowManager {
  static MultiWindowManager? _instance; // cached — never query platform twice

  static Future<MultiWindowManager> instance() async {
    _instance ??= await _create();
    return _instance!;
  }

  static Future<MultiWindowManager> _create() async {
    if (kIsWeb) return UnsupportedMultiWindowManager();
    if (Platform.isAndroid) return AndroidSecondDisplayManager();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return DesktopMultiWindowManager();
    return UnsupportedMultiWindowManager(); // iOS
  }

  Future<bool> isSupported();
  Future<void> openSubWindow(Map<String, dynamic> argument);   // desktop
  Future<void> sendStateToSubDisplay(SubDisplayState state);   // android
  Future<void> closeAll();
}
```

---

## Phase 4 — unsupported_multi_window_manager.dart

```dart
class UnsupportedMultiWindowManager extends MultiWindowManager {
  Future<bool> isSupported() async => false;
  Future<void> openSubWindow(Map<String, dynamic> argument) async {}
  Future<void> sendStateToSubDisplay(SubDisplayState state) async {}
  Future<void> closeAll() async {}
}
```

---

## Phase 5 — desktop_multi_window_manager.dart

```dart
class DesktopMultiWindowManager extends MultiWindowManager {
  int _windowCount = 0;
  final List<WindowController> _controllers = [];

  Future<bool> isSupported() async => true;

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

  Future<void> sendStateToSubDisplay(SubDisplayState state) async {} // no-op

  Future<void> closeAll() async {
    for (final c in _controllers) { await c.close(); }
    _controllers.clear();
  }
}
```

Each sub-window = **a new OS process + independent Flutter engine**. Fully isolated.

---

## Phase 6 — android_second_display_manager.dart

```dart
class AndroidSecondDisplayManager extends MultiWindowManager {
  static const _channel = MethodChannel('second_display');
  bool? _cachedSupported; // cached after first call

  Future<bool> isSupported() async {
    _cachedSupported ??= await _channel.invokeMethod<bool>('isSecondDisplayAvailable') ?? false;
    return _cachedSupported!;
  }

  Future<void> openSubWindow(Map<String, dynamic> argument) async {} // no-op

  Future<void> sendStateToSubDisplay(SubDisplayState state) async {
    await _channel.invokeMethod<void>('sendState', state.toJson());
  }

  Future<void> closeAll() async {
    await _channel.invokeMethod<void>('releaseSecondDisplay');
  }
}
```

---

## Phase 7 — lib/main.dart

```dart
void main(List<String> args) {
  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args.length > 2 && args[2].isNotEmpty
        ? jsonDecode(args[2]) as Map<String, dynamic>
        : <String, dynamic>{};
    WidgetsFlutterBinding.ensureInitialized();
    runApp(SubWindowApp(windowId: windowId, argument: argument));
    return;
  }
  runApp(const MainApp());
}
```

---

## Phase 8 — lib/sub_window.dart (Desktop — own Flutter engine)

- `SubWindowApp` → `MaterialApp` with window title from `argument['windowNumber']`
- `SubWindowPage` (StatefulWidget):
  - `ValueNotifier<int> _counter` — scoped rebuild, no broad `setState`
  - All child widgets use `const` constructors
  - Shows: window number label, counter value, increment FAB

---

## Phase 9 — lib/sub_screen_entry.dart (Android — own Flutter engine)

```dart
@pragma('vm:entry-point')
void subScreenMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SubScreenApp());
}

class _SubScreenAppState extends State<SubScreenApp> {
  static const _channel = MethodChannel('sub_screen_commands');
  SubDisplayState _state = const IdleState();

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'updateState') {
        setState(() => _state = SubDisplayState.fromJson(
          Map<String, dynamic>.from(call.arguments as Map),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: switch (_state) {
      IdleState()          => const IdleScreen(),
      OrderSummaryState s  => OrderSummaryScreen(items: s.items, total: s.total),
      PaymentPromptState s => PaymentPromptScreen(total: s.total),
    },
  );
}
```

Sub-screen widgets use `const` constructors and are scoped — no full-tree rebuilds.

---

## Phase 10 — SecondDisplayPlugin.kt (new file)

```kotlin
class SecondDisplayPlugin(private val context: Context) : DisplayManager.DisplayListener {
    companion object {
        const val CHANNEL = "second_display"
        const val SUB_CHANNEL = "sub_screen_commands"
        const val ENGINE_ID = "sub_screen_engine"
    }

    private val displayManager = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    private var subEngine: FlutterEngine? = null       // lazy — null until display detected
    private var presentation: SecondDisplayPresentation? = null
    private var subChannel: MethodChannel? = null

    fun register(mainChannel: MethodChannel) {
        mainChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSecondDisplayAvailable" -> result.success(getSecondDisplay() != null)
                "sendState" -> {
                    subChannel?.invokeMethod("updateState", call.arguments)
                    result.success(null)
                }
                "releaseSecondDisplay" -> { releaseEngine(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        displayManager.registerDisplayListener(this, null)
        getSecondDisplay()?.let { initSecondDisplay(it) }  // check on startup
    }

    fun dispose() {
        displayManager.unregisterDisplayListener(this)
        releaseEngine()
    }

    // DisplayListener
    override fun onDisplayAdded(displayId: Int) {
        displayManager.getDisplay(displayId)?.let { initSecondDisplay(it) }
    }
    override fun onDisplayRemoved(displayId: Int) { releaseEngine() }
    override fun onDisplayChanged(displayId: Int) {}

    private fun getSecondDisplay(): Display? =
        displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).firstOrNull()

    private fun initSecondDisplay(display: Display) {
        if (subEngine != null) return  // guard: never recreate if already alive

        subEngine = FlutterEngine(context).also { engine ->
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "subScreenMain"
                )
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)  // cache for reuse
            subChannel = MethodChannel(engine.dartExecutor.binaryMessenger, SUB_CHANNEL)
        }
        presentation = SecondDisplayPresentation(context, display, subEngine!!).also { it.show() }
    }

    private fun releaseEngine() {
        presentation?.detach()
        presentation?.dismiss()
        presentation = null
        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        subEngine?.destroy()
        subEngine = null
        subChannel = null
    }
}

class SecondDisplayPresentation(
    context: Context,
    display: Display,
    private val engine: FlutterEngine,
) : Presentation(context, display) {
    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        flutterView = FlutterView(context).also { view ->
            view.attachToFlutterEngine(engine)
            setContentView(view)
        }
    }

    fun detach() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
    }
}
```

---

## Phase 11 — MainActivity.kt (updated)

```kotlin
class MainActivity : FlutterActivity() {
    private lateinit var plugin: SecondDisplayPlugin

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        plugin = SecondDisplayPlugin(applicationContext)
        plugin.register(
            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "second_display")
        )
    }

    override fun onDestroy() {
        plugin.dispose()
        super.onDestroy()
    }
}
```

---

## Phase 12 — lib/main_window.dart

- `MainApp` → `MaterialApp(home: MainWindowPage())`
- `_MainWindowPageState`:
  - `ValueNotifier<int> _counter` — desktop counter (scoped rebuild)
  - `ValueNotifier<List<Map<String,dynamic>>> _items` — android items
  - `ValueNotifier<double> _total` — android total
  - `bool _supported = false`
  - `Timer? _debounce`

**100ms debounce — batches rapid item additions into one MethodChannel call:**
```dart
void _syncSubDisplay() {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 100), () {
    _manager.sendStateToSubDisplay(
      OrderSummaryState(items: _items.value, total: _total.value),
    );
  });
}
```

**Build logic:**
- `!_supported` → `_UnsupportedBanner` (const widget, shows platform name + explanation)
- Android + supported → POS cashier layout using `ValueListenableBuilder` for scoped rebuilds
- Desktop → counter + "Open Sub Window" + "Close All"

---

## Phase 13 — AndroidManifest.xml

Add `android:resizeableActivity="true"` to the `<activity android:name=".MainActivity">` element.

---

## Optimization Details

| # | Optimization | Location |
|---|---|---|
| 1 | `FlutterEngine` lazy init — only when display detected | `SecondDisplayPlugin.initSecondDisplay()` |
| 2 | `FlutterEngineCache` — engine cached by `ENGINE_ID` | `SecondDisplayPlugin` |
| 3 | `if (subEngine != null) return` guard | `initSecondDisplay()` |
| 4 | `_cachedSupported` — `isSupported()` queries platform only once | `AndroidSecondDisplayManager` |
| 5 | 100ms `Timer` debounce on `sendStateToSubDisplay` | `main_window.dart._syncSubDisplay()` |
| 6 | `ValueNotifier` + `ValueListenableBuilder` — scoped rebuilds only | `main_window.dart`, `sub_window.dart` |
| 7 | `const` constructors on all sub-screen widgets | `sub_screen_entry.dart` |
| 8 | Full state snapshot JSON in one call — not per-field | `SubDisplayState.toJson()` |
| 9 | `MultiWindowManager` singleton — `_instance` cached at class level | `multi_window_manager.dart` |

---

## File Checklist

### Modified (4)
- `pubspec.yaml`
- `lib/main.dart`
- `android/app/src/main/kotlin/com/example/multiwindowapp/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`

### Created (10)
- `lib/main_window.dart`
- `lib/sub_window.dart`
- `lib/sub_screen_entry.dart`
- `lib/multi_window_manager/multi_window_manager.dart`
- `lib/multi_window_manager/sub_display_state.dart`
- `lib/multi_window_manager/desktop_multi_window_manager.dart`
- `lib/multi_window_manager/android_second_display_manager.dart`
- `lib/multi_window_manager/unsupported_multi_window_manager.dart`
- `android/app/src/main/kotlin/com/example/multiwindowapp/SecondDisplayPlugin.kt`

---

## Verification Steps

1. `flutter pub get` — resolves cleanly, no conflicts
2. `flutter analyze` — zero errors
3. **macOS / Windows / Linux**: `isSupported()` = `true`; "Open Sub Window" opens independent OS windows with own counters; "Close All" dismisses them
4. **Android — single display**: `isSupported()` = `false` → `_UnsupportedBanner` shown, no crash
5. **Android — dual display (POS)**: sub-screen starts Idle → "Add Item" × N → OrderSummary updates (debounced) → "Payment" → PaymentPrompt → "New Order" → Idle
6. **iOS simulator / Web**: `isSupported()` = `false` → banner shown, no crash

---

## Package Extraction Guide (future)

To convert `lib/multi_window_manager/` into a standalone pub package:
1. `flutter create --template=package multi_window_manager`
2. Move `lib/multi_window_manager/*.dart` → new package `lib/`
3. Move `android/` Kotlin files → new package `android/`
4. Public API (`MultiWindowManager`, `SubDisplayState`) is already clean — no refactoring needed
5. Add `desktop_multi_window` as a dependency in the new package's `pubspec.yaml`
