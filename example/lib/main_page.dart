// main_page.dart
//
// Full refactor that:
//  - DOES NOT force immersive mode
//  - Measures the actual on-screen viewport via LayoutBuilder
//  - Broadcasts at the viewport’s physical resolution (so aspect matches)
//  - Maps touches to the (potentially letterboxed) texture rect correctly
//
// Notes:
//  - If your encoder requires even dimensions, we round width/height to even.
//  - If the viewport changes (rotation, split-screen, insets), the stream
//    restarts with the new resolution.
//  - Touch mapping is robust for contain/cover/fill; default here is contain.

import 'dart:typed_data';

// import 'package:android_automotive_plugin/android_automotive_plugin.dart';
import 'package:carlink/carlink.dart';
import 'package:carlink/carlink_platform_interface.dart';
import 'package:carlink/driver/sendable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'logger.dart';
import 'settings_page.dart';
import 'settings/status_monitor.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<StatefulWidget> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  Carlink? _carlink;
  int? _textureId;

  final DongleConfig _dongleConfig = DEFAULT_CONFIG;

  bool loading = true;

  // final AndroidAutomotivePlugin _automotivePlugin = AndroidAutomotivePlugin();

  final List<TouchItem> _multitouch = [];

  // Track last applied viewport & broadcast resolution to avoid thrashing
  Size? _lastViewportLogical;
  int? _lastBroadcastW;
  int? _lastBroadcastH;

  bool get _isStarted => _carlink != null;

  // ----------------------- Lifecycle -----------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No immersive mode toggling here; leave system UI alone.
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
    // No immersive mode toggling.
    // If you need auto-reconnect on resume, you could check state here.
  }

  // ----------------------- Carlink setup -----------------------

  Future<void> _startCarlink(DongleConfig config) async {
    _carlink = Carlink(
      config: config,
      onTextureChanged: (textureId) async {
        Logger.log(
            "[TEXTURE] Created texture ID: $textureId, Size: ${_dongleConfig.width}x${_dongleConfig.height}");
        setState(() {
          _textureId = textureId;
        });
      },
      onStateChanged: (carlinkState) {
        Logger.log("[STATE] Carlink state changed: ${carlinkState.name}");

        switch (carlinkState) {
          case CarlinkState.connecting:
            Logger.log("[STATE] Searching for USB dongle device...");
            break;
          case CarlinkState.deviceConnected:
            Logger.log("[STATE] USB device connected, initializing protocol...");
            break;
          case CarlinkState.streaming:
            Logger.log("[STATE] Video streaming active");
            break;
          case CarlinkState.disconnected:
            Logger.log("[STATE] Device disconnected");
            break;
        }

        setState(() {
          loading = carlinkState != CarlinkState.streaming;
        });
      },
      onMediaInfoChanged: (mediaInfo) {
        try {
          Logger.log(
              "[MEDIA] Now playing: ${mediaInfo.songTitle} by ${mediaInfo.songArtist}, Album: ${mediaInfo.albumName}, App: ${mediaInfo.appName}, Cover: ${mediaInfo.albumCoverImageData?.length ?? 0} bytes");
          _setInfoAndCover(
            mediaInfo.songTitle,
            mediaInfo.songArtist,
            mediaInfo.appName,
            mediaInfo.albumName,
            mediaInfo.albumCoverImageData,
          );
        } catch (e) {
          Logger.log("[ERROR] Media info processing failed: ${e.toString()}");
        }
      },
      onLogMessage: (log) {
        Logger.log("[DONGLE] $log");
      },
      onHostUIPressed: () {
        Logger.log("[UI] Host UI button pressed - opening settings");
        _openSettings(context);
      },
      onMessageIntercepted: (message) {
        // Forward all CPC200-CCPA messages to status monitor for real-time processing
        adapterStatusMonitor.processMessage(message);
      },
    );

    Logger.log("[DONGLE] Starting Carlink connection...");

    // Start monitoring adapter status with direct message interception
    adapterStatusMonitor.startMonitoring(_carlink);

    _carlink?.start();
  }

  Future<void> _stopCarlink() async {
    try {
      await _carlink?.stop();
    } catch (e) {
      Logger.log("[DONGLE] stop() failed: $e");
    }
  }

  // ----------------------- Viewport → Broadcast config -----------------------

  int _roundToEven(num v) => (v.round() & ~1); // encoders often need even dims
  bool _differsInt(int a, int b, {int tol = 1}) => (a - b).abs() > tol;

  /// Configure the dongle to broadcast at the viewport's *physical* resolution
  /// (Viewport logical size from LayoutBuilder multiplied by devicePixelRatio).
  Future<void> _configureForViewport(Size viewportLogical) async {
    if (viewportLogical.isEmpty) return;

    final dpr = MediaQuery.of(context).devicePixelRatio;

    // Physical pixels for the actual drawable area (post SafeArea/padding)
    final physW = _roundToEven(viewportLogical.width * dpr);
    final physH = _roundToEven(viewportLogical.height * dpr);

    if (_lastBroadcastW != null &&
        _lastBroadcastH != null &&
        !_differsInt(_lastBroadcastW!, physW) &&
        !_differsInt(_lastBroadcastH!, physH)) {
      // Nothing to change
      return;
    }

    // Optional but useful: get DPI / refresh from the device
    final hw = await CarlinkPlatform.instance.getDisplayMetrics();
    final dpi = (hw['densityDpi'] as int?) ?? 320;
    final fps = ((hw['refreshRate'] as double?) ?? 60).toInt();

    _dongleConfig
      ..width = physW
      ..height = physH
      ..dpi = dpi
      ..fps = fps;

    Logger.log(
      "[RES] Viewport(logical): "
      "${viewportLogical.width.toStringAsFixed(1)}x${viewportLogical.height.toStringAsFixed(1)} "
      "DPR=$dpr -> Broadcast (physical): ${_dongleConfig.width}x${_dongleConfig.height} "
      "@${_dongleConfig.fps}fps, ${_dongleConfig.dpi}dpi",
    );

    if (!_isStarted) {
      await _startCarlink(_dongleConfig);
    } else {
      // If your SDK supports a hot reconfigure, prefer that. Otherwise restart.
      try {
        await _stopCarlink();
        await Future.delayed(const Duration(milliseconds: 150));
        await _carlink?.start();
      } catch (e) {
        Logger.log("[DONGLE] Restart after resolution change failed: $e");
      }
    }

    _lastViewportLogical = viewportLogical;
    _lastBroadcastW = physW;
    _lastBroadcastH = physH;

    setState(() {
      // Texture size may change
    });
  }

  // ----------------------- Touch mapping -----------------------

  /// Map a viewport-local point (from Listener) into normalized texture coords [0..1],
  /// accounting for FittedBox(BoxFit.contain) letterboxing.
  Offset? _mapViewportPointToTextureNormalized({
    required Offset local,
    required Size viewportSize,
    required Size texturePixelSize,
    Alignment alignment = Alignment.center, // matches FittedBox default
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
        _dongleConfig.width.toDouble(),
        _dongleConfig.height.toDouble(),
      ),
      alignment: Alignment.center,
      fit: BoxFit.contain, // Keep in sync with the FittedBox below
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

  // ----------------------- UI -----------------------

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(carlink: _carlink),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              "assets/projection_icon.png",
              height: 220,
            ),
            const SizedBox(height: 24),
            const CupertinoActivityIndicator(
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Keep SafeArea if you want to avoid cutouts; mapping uses the post-SafeArea viewport.
      body: SafeArea(
        // If you truly want zero padding, set left/right/top/bottom to false.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;

            // Configure/reconfigure the broadcast for this viewport.
            if (viewport.width > 0 && viewport.height > 0) {
              // Use a microtask to avoid doing async work during layout.
              Future.microtask(() => _configureForViewport(viewport));
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
                            fit: BoxFit.contain, // Aspect-preserving; with matched broadcast aspect, bars should be ~0
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: _dongleConfig.width.toDouble(),
                              height:
                                  _dongleConfig.height.toDouble(),
                              child: Texture(textureId: _textureId!),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                if (loading) Positioned.fill(child: _buildLoadingOverlay()),
                if (loading)
                  Positioned(
                    top: 24,
                    right: 24,
                    child: IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () => _openSettings(context),
                    ),
                  ),
                // Uncomment for log tail while debugging:
                // Positioned(
                //   right: 20,
                //   bottom: 20,
                //   width: 500,
                //   height: 150,
                //   child: SingleChildScrollView(
                //     child: Text(
                //       log,
                //       style: TextStyle(color: Colors.white60, fontSize: 18),
                //     ),
                //   ),
                // )
              ],
            );
          },
        ),
      ),
    );
  }

  // ----------------------- Media cover (stubbed) -----------------------

  Future<void> _setInfoAndCover(
    String? mediaSongName,
    String? mediaArtistName,
    String? mediaAppName,
    String? mediaAlbumName,
    Uint8List? coverData,
  ) async {
    // String? path;
    // File writing functionality removed - coverData processing disabled
    if (coverData != null) {
      // Cover data received but not saved to file
    }

    // try {
    //   if (path != null) {
    //     await _automotivePlugin
    //         .setVehicleSettingMusicAlbumPictureFilePath(path);
    //   }
    //
    //   await _automotivePlugin.setDoubleMediaMusicSource(
    //     playingId: 1,
    //     programName: mediaAlbumName ?? mediaAppName ?? " ",
    //     singerName: mediaArtistName ?? " ",
    //     songName: mediaSongName ?? mediaAppName ?? " ",
    //     sourceType: 25,
    //   );
    //
    //   if (path != null) {
    //     await _automotivePlugin.setDoubleMediaMusicAlbumPictureFilePath(
    //       doublePlayingId: 1,
    //       songId: "test-song",
    //       path: path,
    //     );
    //   }
    // } catch (e) {
    //   // ignore
    // }
  }
}
