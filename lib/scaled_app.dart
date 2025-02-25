import 'dart:async' show scheduleMicrotask, Timer;
import 'dart:collection' show Queue;
import 'dart:ui' show PointerDataPacket;
import 'package:flutter/rendering.dart' show ViewConfiguration;
import 'package:flutter/gestures.dart' show FlutterView, PointerEventConverter;
import 'package:flutter/widgets.dart';
import 'dart:developer';

/// The size of the screen is in logical pixels.
///
/// Scale of 1 means original size.
///
typedef ScaleFactorCallback = double Function(Size deviceSize);

/// Replace [runApp] with [runAppScaled] in `main()`.
///
/// Scaling will be applied based on [scaleFactor] callback.
///
void runAppScaled(Widget app, {ScaleFactorCallback? scaleFactor}) {
  WidgetsBinding binding = ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: scaleFactor,
  );
  Timer.run(() {
    binding.attachRootWidget(binding.wrapWithDefaultView(app));
  });
  binding.scheduleWarmUpFrame();
}

/// Adapted from [WidgetsFlutterBinding]
///
class ScaledWidgetsFlutterBinding extends WidgetsFlutterBinding {
  FlutterView get view => platformDispatcher.implicitView!;

  /// Calculate scale factor from device size.
  ScaleFactorCallback? _scaleFactor;

  ScaledWidgetsFlutterBinding._({ScaleFactorCallback? scaleFactor})
      : _scaleFactor = scaleFactor;

  ScaleFactorCallback get scaleFactor => _scaleFactor ?? (_) => 1.0;

  /// Update scaleFactor callback, then rebuild layout
  set scaleFactor(ScaleFactorCallback? callback) {
    _scaleFactor = callback;
    handleMetricsChanged();
  }

  double get scale => scaleFactor(view.physicalSize / view.devicePixelRatio);

  double devicePixelRatioScaled = 0;

  bool get isScaling => scale != 1.0;

  static ScaledWidgetsFlutterBinding? _binding;

  /// Scaling will be applied based on [scaleFactor] callback.
  ///
  static WidgetsBinding ensureInitialized({ScaleFactorCallback? scaleFactor}) {
    _binding ??= ScaledWidgetsFlutterBinding._(scaleFactor: scaleFactor);
    return _binding!;
  }

  static ScaledWidgetsFlutterBinding get instance => _binding!;

  /// Override the method from [RendererBinding.createViewConfiguration] to
  /// change what size or device pixel ratio the [RenderView] will use.
  ///
  /// See more:
  /// * [RendererBinding.createViewConfiguration]
  /// * [TestWidgetsFlutterBinding.createViewConfiguration]
  @override
  ViewConfiguration createViewConfiguration() {
    if (view.physicalSize.isEmpty) {
      return super.createViewConfiguration();
    } else {
      devicePixelRatioScaled = view.devicePixelRatio * scale;
      return ViewConfiguration(
        size: view.physicalSize / devicePixelRatioScaled,
        devicePixelRatio: devicePixelRatioScaled,
      );
    }
  }

  // @override
  // SingletonFlutterWindow get window => super.window;

  /// Adapted from [GestureBinding.initInstances]
  @override
  void initInstances() {
    super.initInstances();
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();

  /// When we scale UI using [ViewConfiguration], [ui.window] stays the same.
  ///
  /// [GestureBinding] uses [view.devicePixelRatio] for calculations,
  /// so we override corresponding methods.
  ///
  void _handlePointerDataPacket(PointerDataPacket packet) {
    // We convert pointer data to logical pixels so that e.g. the touch slop can be
    // defined in a device-independent manner.
    _pendingPointerEvents.addAll(
        PointerEventConverter.expand(packet.data, devicePixelRatioScaled));
    if (!locked) {
      _flushPointerEventQueue();
    }
  }

  /// Dispatch a [PointerCancelEvent] for the given pointer soon.
  ///
  /// The pointer event will be dispatched before the next pointer event and
  /// before the end of the microtask but not within this function call.
  @override
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked) {
      scheduleMicrotask(_flushPointerEventQueue);
    }
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);

    while (_pendingPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingPointerEvents.removeFirst());
    }
  }
}

extension ScaledMediaQueryData on MediaQueryData {
  /// Scale MediaQueryData accordingly,
  /// so that widgets using [MediaQueryData.size],
  /// [MediaQueryData.devicePixelRatio], [MediaQueryData.viewInsets],
  /// [MediaQueryData.viewPadding], [MediaQueryData.padding]
  /// can be laid out correctly.
  ///
  /// e.g. keyboard, appBar, navigationBar.
  ///
  MediaQueryData scale() {
    final scale = (ScaledWidgetsFlutterBinding._binding?.scale ?? 1);
    return copyWith(
      size: size / scale,
      devicePixelRatio: devicePixelRatio * scale,
      viewInsets: viewInsets / scale,
      viewPadding: viewPadding / scale,
      padding: padding / scale,
    );
  }
}
