// import 'package:android_automotive_plugin/android_automotive_plugin.dart';
import 'package:carlink/carlink.dart';
import 'package:carlink/carlink_platform_interface.dart';
import 'package:carlink/driver/sendable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🔕 Stop forcing immersive mode; leave system UI alone.
    // (If you still want edge-to-edge, configure in Android styles or let the app bar/scaffold handle it.)

    Future.delayed(const Duration(seconds: 3), () {
      _start();
    });
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
    // No immersive mode toggling anymore.
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(carlink: _carlink),
      ),
    );
  }

  Future<void> _start() async {
    if (_initialized) return;

    // Flutter's logical display metrics (for sanity/logs only)
    final displaySize = MediaQuery.of(context).size;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;

    if (displaySize.width == 0 || displaySize.height == 0) {
      return;
    }

    // Android's native hardware display metrics
    final hardwareMetrics = await CarlinkPlatform.instance.getDisplayMetrics();
    final hardwareWidth = hardwareMetrics['widthPixels'] as int;
    final hardwareHeight = hardwareMetrics['heightPixels'] as int;
    final hardwareDpi = hardwareMetrics['densityDpi'] as int;
    final refreshRate = hardwareMetrics['refreshRate'] as double;

    // Flutter's physical pixels (for comparison/logging)
    final flutterPhysicalWidth = (displaySize.width * pixelRatio).toInt();
    final flutterPhysicalHeight = (displaySize.height * pixelRatio).toInt();

    // Use Android's native hardware resolution for the dongle
    _dongleConfig.width = hardwareWidth;
    _dongleConfig.height = hardwareHeight;
    _dongleConfig.dpi = hardwareDpi;
    _dongleConfig.fps = refreshRate.toInt();

    Logger.log(
        "[INIT] Flutter display: ${displaySize.width}x${displaySize.height}, pixelRatio: $pixelRatio, calculated: ${flutterPhysicalWidth}x${flutterPhysicalHeight}");
    Logger.log(
        "[INIT] Android hardware: ${hardwareWidth}x${hardwareHeight}, DPI: $hardwareDpi, refreshRate: ${refreshRate}Hz");
    Logger.log(
        "[INIT] Carlink config: ${_dongleConfig.width}x${_dongleConfig.height}, DPI: ${_dongleConfig.dpi}, FPS: ${_dongleConfig.fps}");
    Logger.log(
        "[INIT] Device config: boxName: ${_dongleConfig.boxName}, micType: ${_dongleConfig.micType}, wifiType: ${_dongleConfig.wifiType}");
    Logger.log(
        "[INIT] Audio config: transferMode: ${_dongleConfig.audioTransferMode}, nightMode: ${_dongleConfig.nightMode}, hand: ${_dongleConfig.hand}");

    _startCarlink(_dongleConfig);

    _initialized = true;
  }

  void _startCarlink(DongleConfig config) async {
    _carlink = Carlink(
      config: config,
      onTextureChanged: (textureId) async {
        Logger.log("[TEXTURE] Created texture ID: $textureId, Size: ${_dongleConfig.width}x${_dongleConfig.height}");
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

  /// Maps a pointer [local] (relative to the Listener's viewport) into normalized
  /// texture coordinates [0..1] x [0..1], accounting for letterboxing created
  /// by FittedBox(BoxFit.contain). Returns null if outside the displayed texture.
  Offset? _mapViewportPointToTextureNormalized({
    required Offset local,
    required Size viewportSize,
    required Size texturePixelSize,
  }) {
    if (viewportSize.isEmpty || texturePixelSize.isEmpty) return null;

    final vw = viewportSize.width;
    final vh = viewportSize.height;
    final tw = texturePixelSize.width;
    final th = texturePixelSize.height;

    // Scale that FittedBox(BoxFit.contain) uses
    final scale = (vw / tw).clamp(0.0, double.infinity).compareTo(vh / th) <= 0
        ? vw / tw
        : vh / th;

    final displayW = tw * scale;
    final displayH = th * scale;

    // Letterbox offsets
    final offsetX = (vw - displayW) / 2.0;
    final offsetY = (vh - displayH) / 2.0;

    // If the touch falls inside the displayed texture rect, map it.
    final dx = local.dx - offsetX;
    final dy = local.dy - offsetY;
    if (dx < 0 || dy < 0 || dx > displayW || dy > displayH) {
      // Outside the active video area (in the black bars) -> ignore
      return null;
    }

    final nx = (dx / displayW).clamp(0.0, 1.0);
    final ny = (dy / displayH).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  Future<void> _processMultitouchEvent({
    required MultiTouchAction action,
    required int id,
    required Offset localPositionInViewport,
    required Size viewportSize,
  }) async {
    // If we don't have a texture yet, skip
    if (_textureId == null) return;

    final normalized = _mapViewportPointToTextureNormalized(
      local: localPositionInViewport,
      viewportSize: viewportSize,
      texturePixelSize: Size(
        _dongleConfig.width.toDouble(),
        _dongleConfig.height.toDouble(),
      ),
    );

    // Ignore touches that land in the letterbox area
    if (normalized == null) {
      // If you prefer to send edge-clamped coordinates instead of ignoring,
      // you could clamp to [0,1] here and proceed.
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
          return;
        }
      }
    } else {
      return;
    }

    _carlink?.sendMultiTouch(_multitouch
        .map((e) => TouchItem(e.x, e.y, e.action, _multitouch.indexOf(e)))
        .toList());

    _multitouch.removeWhere((e) => e.action == MultiTouchAction.Up);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea( // keep SafeArea if desired; mapping respects it via LayoutBuilder
        child: Center(
          child: Stack(
            children: [
              Positioned.fill(
                // Measure the *actual* area the video can use (post SafeArea/padding)
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportSize = constraints.biggest;

                    return Listener(
                      onPointerDown: (p) async => _processMultitouchEvent(
                        action: MultiTouchAction.Down,
                        id: p.pointer,
                        localPositionInViewport: p.localPosition,
                        viewportSize: viewportSize,
                      ),
                      onPointerMove: (p) async => _processMultitouchEvent(
                        action: MultiTouchAction.Move,
                        id: p.pointer,
                        localPositionInViewport: p.localPosition,
                        viewportSize: viewportSize,
                      ),
                      onPointerUp: (p) async => _processMultitouchEvent(
                        action: MultiTouchAction.Up,
                        id: p.pointer,
                        localPositionInViewport: p.localPosition,
                        viewportSize: viewportSize,
                      ),
                      onPointerCancel: (p) async => _processMultitouchEvent(
                        action: MultiTouchAction.Up,
                        id: p.pointer,
                        localPositionInViewport: p.localPosition,
                        viewportSize: viewportSize,
                      ),
                      child: _textureId != null
                          ? FittedBox(
                              fit: BoxFit.contain, // maintain aspect ratio
                              child: SizedBox(
                                width: _dongleConfig.width.toDouble(),
                                height: _dongleConfig.height.toDouble(),
                                child: Texture(textureId: _textureId!),
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
              ),
              if (loading)
                Positioned.fill(
                  child: Container(
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
                  ),
                ),
              if (loading)
                Positioned(
                  top: 24,
                  right: 24,
                  child: IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => _openSettings(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

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
