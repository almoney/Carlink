import 'package:carlink/carlink.dart';
import 'package:carlink/carlink_platform_interface.dart';
import 'package:carlink/driver/sendable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carlink/log.dart';
import 'settings_page.dart';
import 'settings/status_monitor.dart';
import 'immersive_preference.dart';
import 'device_operations.dart';

// MainPage - Primary Projection Display Interface
//
// The main screen for the Carlink App, Displays Projection Video
//
// Key Responsibilities:
// - Video Rendering: Displays H.264 video stream from the adapter using Flutter
//   Texture widget with aspect-ratio-preserving letterboxing (BoxFit.contain)
//
// - Resolution Management: Dynamically configures broadcast resolution based on
//   viewport size, device pixel ratio, and display metrics (DPI/FPS). Rounds to
//   even dimensions for H.264 encoder compatibility
//
// - Touch Input: Captures multitouch gestures and maps viewport coordinates to
//   normalized texture space [0..1], accounting for letterboxing. Forwards touch
//   events to the connected phone via Adapter protocol
//
// - Connection Lifecycle: Manages CPC200-CCPA adapter initialization, state
//   monitoring (connecting → deviceConnected → streaming), and protocol message
//   interception for diagnostics
//
// - Display Modes: Supports immersive fullscreen (SystemUiMode.immersiveSticky)
//   and non-immersive modes based on user preference
//
// The page uses LayoutBuilder to respond to viewport changes and SafeArea to respect
// system UI insets. A loading overlay with progress indicator displays until video
// streaming becomes active. Settings access is available via floating button or
// OEM/Vehicle button. Shown within Carplay and Android Auto.
//
// Note: Media metadata (now-playing info) is processed in the Carlink core but not
// handled in this UI - future revisions may display it elsewhere or forward to OS.
//
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<StatefulWidget> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  Carlink? _carlink;
  int? _textureId;

  final AdaptrConfig _adaptrConfig = DEFAULT_CONFIG;

  bool loading = true;

  final List<TouchItem> _multitouch = [];

  // Track last broadcast resolution to avoid thrashing
  int? _lastBroadcastW;
  int? _lastBroadcastH;

  bool get _isStarted => _carlink != null;
  bool _isConfiguring = false; // Prevent concurrent configuration

  // Flag to control SafeArea behavior based on immersive mode preference
  // When true, SafeArea padding is disabled to prevent viewport resize in immersive mode
  bool _disableSafeArea = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Load immersive preference to control SafeArea behavior
    // This prevents viewport resize when SystemUI temporarily appears
    _loadImmersivePreference();

    // Immersive mode now initialized in main() before runApp()
    // This ensures correct viewport dimensions from first build

    // LayoutBuilder in build() will trigger _configureForViewport() which starts Carlink
    // No need for delayed _start() here
  }

  /// Load immersive mode preference to control SafeArea behavior
  ///
  /// When immersive mode is enabled, SafeArea is disabled to prevent the viewport
  /// from shrinking when system UI temporarily appears (dialogs, notifications).
  /// This ensures the texture resolution and viewport size remain consistent.
  Future<void> _loadImmersivePreference() async {
    final isImmersive = await ImmersivePreference.instance.isEnabled();
    if (mounted) {
      setState(() {
        _disableSafeArea = isImmersive;
      });
    }
  }

  /// Initialize immersive mode based on user preference
  Future<void> _initializeImmersiveMode() async {
    final isImmersiveEnabled = await ImmersivePreference.instance.isEnabled();
    if (isImmersiveEnabled) {
      _setImmersiveMode();
    } else {
      _setNonImmersiveMode();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Stop adapter status monitoring
    adapterStatusMonitor.stopMonitoring();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeImmersiveMode();
    }
  }

  void _setImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    log('[IMMERSIVE] Enabled fullscreen immersive mode');
  }

  void _setNonImmersiveMode() {
    // No SystemChrome call - let AAOS manage system UI naturally
    // Fullscreen theme in AndroidManifest.xml handles display mode
    log('[IMMERSIVE] Non-immersive mode - AAOS managing system UI');
  }

  /// Round to even number (H.264 encoders require even dimensions)
  int _roundToEven(num v) => (v.round() & ~1);

  /// Check if two integers differ by more than tolerance
  bool _differsInt(int a, int b, {int tol = 1}) => (a - b).abs() > tol;

  /// Configure the dongle to broadcast at the viewport's physical resolution
  /// (Viewport logical size from LayoutBuilder multiplied by devicePixelRatio).
  Future<void> _configureForViewport(
      Size viewportLogical, double devicePixelRatio) async {
    if (viewportLogical.isEmpty) return;

    // Prevent concurrent configuration
    if (_isConfiguring) {
      log("[RES] Configuration already in progress, skipping");
      return;
    }

    _isConfiguring = true;
    try {
      // Physical pixels for the actual drawable area (post SafeArea/padding)
      final physW = _roundToEven(viewportLogical.width * devicePixelRatio);
      final physH = _roundToEven(viewportLogical.height * devicePixelRatio);

      if (_lastBroadcastW != null &&
          _lastBroadcastH != null &&
          !_differsInt(_lastBroadcastW!, physW) &&
          !_differsInt(_lastBroadcastH!, physH)) {
        // Nothing to change
        return;
      }

      // Get DPI / refresh from the device
      final hw = await CarlinkPlatform.instance.getDisplayMetrics();
      final dpi = (hw['densityDpi'] as int?) ?? 320;
      final fps = ((hw['refreshRate'] as double?) ?? 60).toInt();

      _adaptrConfig
        ..width = physW
        ..height = physH
        ..dpi = dpi
        ..fps = fps;

      log(
        "[RES] Viewport(logical): "
        "${viewportLogical.width.toStringAsFixed(1)}x${viewportLogical.height.toStringAsFixed(1)} "
        "DPR=$devicePixelRatio -> Broadcast (physical): ${_adaptrConfig.width}x${_adaptrConfig.height} "
        "@${_adaptrConfig.fps}fps, ${_adaptrConfig.dpi}dpi",
      );

      if (!_isStarted) {
        await _startCarlink(_adaptrConfig);
        _lastBroadcastW = physW;
        _lastBroadcastH = physH;
      } else {
        // Resolution changes are ignored when already running
        log("[RES] Resolution change detected but ignored (Carlink already running)");
        return;
      }

      if (mounted) {
        setState(() {});
      }
    } finally {
      _isConfiguring = false;
    }
  }

  /// Map a viewport-local point (from Listener) into normalized texture coords [0..1],
  /// accounting for FittedBox(BoxFit.contain) letterboxing.
  Offset? _mapViewportPointToTextureNormalized({
    required Offset local,
    required Size viewportSize,
    required Size texturePixelSize,
    Alignment alignment = Alignment.center,
    BoxFit fit = BoxFit.contain,
  }) {
    if (viewportSize.isEmpty || texturePixelSize.isEmpty) return null;

    final vw = viewportSize.width;
    final vh = viewportSize.height;
    final tw = texturePixelSize.width;
    final th = texturePixelSize.height;

    double scale;
    if (fit == BoxFit.contain) {
      // Smaller of the two scales: fit entirely within viewport
      final sx = vw / tw;
      final sy = vh / th;
      scale = sx < sy ? sx : sy;
    } else if (fit == BoxFit.cover) {
      // Larger of the two scales: fill viewport and crop overflow
      final sx = vw / tw;
      final sy = vh / th;
      scale = sx > sy ? sx : sy;
    } else if (fit == BoxFit.fill) {
      // Independent scaling (distorts). Mapping becomes simple fractions.
      final nx = (local.dx / vw).clamp(0.0, 1.0);
      final ny = (local.dy / vh).clamp(0.0, 1.0);
      return Offset(nx, ny);
    } else {
      // For other fits, treat like contain as a sane default.
      final sx = vw / tw;
      final sy = vh / th;
      scale = sx < sy ? sx : sy;
    }

    final dispW = tw * scale;
    final dispH = th * scale;

    // Alignment: for contain/cover, Flutter positions the child according to alignment.
    // Default is center (0,0). Compute offsets accordingly.
    final ax = (alignment.x + 1) / 2; // 0..1
    final ay = (alignment.y + 1) / 2; // 0..1

    final offsetX = (vw - dispW) * ax;
    final offsetY = (vh - dispH) * ay;

    final dx = local.dx - offsetX;
    final dy = local.dy - offsetY;

    if (fit == BoxFit.contain) {
      // Ignore touches in the letterbox region
      if (dx < 0 || dy < 0 || dx > dispW || dy > dispH) return null;
    }
    // For cover, the displayed rect may extend beyond viewport; allow clamping.
    final nx = (dx / dispW).clamp(0.0, 1.0);
    final ny = (dy / dispH).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(carlink: _carlink),
      ),
    );
  }

  // Resolution configuration now handled by _configureForViewport() via LayoutBuilder
  // This ensures viewport-aware scaling in both immersive and non-immersive modes

  _startCarlink(AdaptrConfig config) async {
    _carlink = Carlink(
      config: config,
      onTextureChanged: (textureId) async {
        log("[TEXTURE] Created texture ID: $textureId, Size: ${config.width}x${config.height}");
        if (mounted) {
          setState(() {
            _textureId = textureId;
          });
        }
      },
      onStateChanged: (carlinkState) {
        log("[STATE] Carlink state changed: ${carlinkState.name}");

        switch (carlinkState) {
          case CarlinkState.connecting:
            log("[STATE] Searching for USB dongle device...");
            break;
          case CarlinkState.deviceConnected:
            log("[STATE] USB device connected, initializing protocol...");
            break;
          case CarlinkState.streaming:
            log("[STATE] Video streaming active", tag: 'VIDEO');
            break;
          case CarlinkState.disconnected:
            log("[STATE] Device disconnected");
            break;
        }

        if (mounted) {
          setState(() {
            loading = carlinkState != CarlinkState.streaming;
          });
        }
      },
      onLogMessage: (message) {
        log(message, tag: 'ADAPTR');
      },
      onHostUIPressed: () {
        log("[UI] Host UI button pressed - opening settings");
        _openSettings(context);
      },
      onMessageIntercepted: (message) {
        // Forward all CPC200-CCPA messages to status monitor for real-time processing
        adapterStatusMonitor.processMessage(message);
      },
    );

    log("[ADAPTR] Starting Carlink connection...");

    // Start monitoring adapter status with direct message interception
    adapterStatusMonitor.startMonitoring(_carlink);

    await _carlink?.start();
  }

  Future<void> _processMultitouchEvent({
    required MultiTouchAction action,
    required int id,
    required Offset localPositionInViewport,
    required Size viewportSize,
  }) async {
    if (_textureId == null) return;

    final normalized = _mapViewportPointToTextureNormalized(
      local: localPositionInViewport,
      viewportSize: viewportSize,
      texturePixelSize: Size(
        _adaptrConfig.width.toDouble(),
        _adaptrConfig.height.toDouble(),
      ),
      alignment: Alignment.center,
      fit: BoxFit.contain,
    );

    if (normalized == null) {
      // Touch landed in letterbox area; ignore.
      return;
    }

    final touch = TouchItem(
      normalized.dx,
      normalized.dy,
      action,
      id,
    );

    final index = _multitouch.indexWhere((e) => e.id == id);
    if (action == MultiTouchAction.Down) {
      _multitouch.add(touch);
    } else if (index != -1) {
      if (action == MultiTouchAction.Up) {
        _multitouch[index] = touch;
      } else if (action == MultiTouchAction.Move) {
        final existed = _multitouch[index];
        final dx = (existed.x * 1000 - touch.x * 1000).abs();
        final dy = (existed.y * 1000 - touch.y * 1000).abs();

        if ((dx > 3 || dy > 3)) {
          _multitouch[index] = touch;
        } else {
          return; // ignore tiny jitter
        }
      }
    } else {
      return; // up/move without prior down
    }

    _carlink?.sendMultiTouch(_multitouch
        .map((e) => TouchItem(e.x, e.y, e.action, _multitouch.indexOf(e)))
        .toList());

    _multitouch.removeWhere((e) => e.action == MultiTouchAction.Up);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        // Disable SafeArea in immersive mode to prevent viewport resize
        // when system UI temporarily appears (dialogs, notifications)
        top: !_disableSafeArea,
        bottom: !_disableSafeArea,
        left: !_disableSafeArea,
        right: !_disableSafeArea,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final dpr = MediaQuery.devicePixelRatioOf(context);

            // Configure/reconfigure the broadcast for this viewport.
            if (viewport.width > 0 && viewport.height > 0) {
              // Use a microtask to avoid doing async work during layout.
              Future.microtask(() => _configureForViewport(viewport, dpr));
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: Listener(
                    onPointerDown: (p) => _processMultitouchEvent(
                      action: MultiTouchAction.Down,
                      id: p.pointer,
                      localPositionInViewport: p.localPosition,
                      viewportSize: viewport,
                    ),
                    onPointerMove: (p) => _processMultitouchEvent(
                      action: MultiTouchAction.Move,
                      id: p.pointer,
                      localPositionInViewport: p.localPosition,
                      viewportSize: viewport,
                    ),
                    onPointerUp: (p) => _processMultitouchEvent(
                      action: MultiTouchAction.Up,
                      id: p.pointer,
                      localPositionInViewport: p.localPosition,
                      viewportSize: viewport,
                    ),
                    onPointerCancel: (p) => _processMultitouchEvent(
                      action: MultiTouchAction.Up,
                      id: p.pointer,
                      localPositionInViewport: p.localPosition,
                      viewportSize: viewport,
                    ),
                    child: _textureId != null
                        ? FittedBox(
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: _adaptrConfig.width.toDouble(),
                              height: _adaptrConfig.height.toDouble(),
                              child: Texture(textureId: _textureId!),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                if (loading)
                  Positioned.fill(
                    child: Container(
                      color: colorScheme.scrim.withValues(alpha: 0.7),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              "assets/projection_icon.png",
                              height: 220,
                            ),
                            const SizedBox(height: 24),
                            CircularProgressIndicator(
                              color: colorScheme.primary,
                              strokeWidth: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (loading)
                  Positioned(
                    top: 24,
                    left: 24,
                    child: Row(
                      children: [
                        _buildSettingsButton(context),
                        const SizedBox(width: 16),
                        _buildResetButton(context),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Builds a Material 3 settings button for automotive touch targets
  Widget _buildSettingsButton(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton.tonalIcon(
      onPressed: () => _openSettings(context),
      icon: const Icon(Icons.settings, size: 28),
      label: Text('Settings', style: theme.textTheme.titleLarge),
      style: FilledButton.styleFrom(
        minimumSize: const Size(180, 72),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      ),
    );
  }

  /// Builds a Material 3 reset button for automotive touch targets
  Widget _buildResetButton(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEnabled = _isStarted && !DeviceOperations.isProcessing;

    return FilledButton.tonalIcon(
      onPressed: isEnabled ? _resetDevice : null,
      icon: DeviceOperations.isProcessing
          ? const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.restart_alt, size: 28),
      label: Text('Reset Device', style: theme.textTheme.titleLarge),
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
        minimumSize: const Size(180, 72),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      ),
    );
  }

  /// Reset the USB device connection using shared DeviceOperations utility.
  ///
  /// This method delegates to DeviceOperations.restartConnection() to ensure
  /// identical behavior to Settings > Control > Reset USB Device.
  /// Prevents concurrent operations and provides consistent error handling.
  Future<void> _resetDevice() async {
    await DeviceOperations.restartConnection(
      context: context,
      carlink: _carlink,
      successMessage: 'Connection restart completed successfully',
      initiatedFrom: 'Main Page',
    );
  }
}
