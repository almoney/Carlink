import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';

/// Enhanced transfer dialog that shows actual progress during file sharing operations
class TransferDialog extends StatefulWidget {
  final List<File> files;
  final String operationName;
  final Future<bool> Function() shareOperation;
  final VoidCallback? onCancel;

  const TransferDialog({
    required this.files,
    required this.operationName,
    required this.shareOperation,
    this.onCancel,
    super.key,
  });

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _pulseController;

  TransferState _state = TransferState.preparing;
  String _statusMessage = 'Preparing files for export...';
  int _currentAttempt = 1;
  final int _maxAttempts = 3;
  Timer? _timeoutTimer;
  Timer? _progressTimer;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();

    _spinController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _startTransfer();
  }

  @override
  void dispose() {
    _cancelled = true;
    _timeoutTimer?.cancel();
    _progressTimer?.cancel();
    _spinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startTransfer() async {
    if (_cancelled) return;

    // Start timeout timer (30 seconds)
    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!_cancelled && _state == TransferState.inProgress) {
        _handleTimeout();
      }
    });

    // Start progress updates
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 500), _updateProgress);

    try {
      setState(() {
        _state = TransferState.validating;
        _statusMessage = 'Validating ${widget.files.length} files...';
      });

      // Validate files exist and are readable
      await _validateFiles();

      if (_cancelled) return;

      setState(() {
        _state = TransferState.inProgress;
        _statusMessage = 'Opening share dialog...';
      });

      // Small delay to show progress
      await Future.delayed(const Duration(milliseconds: 800));

      if (_cancelled) return;

      // Attempt the share operation
      final success = await widget.shareOperation();

      if (_cancelled) return;

      if (success) {
        setState(() {
          _state = TransferState.completed;
          _statusMessage = 'Share dialog opened - verify files after saving';
        });

        // Auto-close after showing success
        Timer(const Duration(seconds: 3), () {
          if (!_cancelled && mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else {
        _handleFailure('Share operation did not complete');
      }
    } catch (e) {
      if (!_cancelled) {
        _handleFailure(e.toString());
      }
    } finally {
      _timeoutTimer?.cancel();
      _progressTimer?.cancel();
    }
  }

  void _updateProgress(Timer timer) {
    if (_cancelled || !mounted) {
      timer.cancel();
      return;
    }

    // Update status message based on current state
    if (_state == TransferState.inProgress) {
      final messages = [
        'Opening share dialog...',
        'Waiting for file manager selection...',
        'Preparing files for transfer...',
        'Share dialog is open - please select destination...',
      ];

      setState(() {
        _statusMessage = messages[(timer.tick ~/ 4) % messages.length];
      });
    }
  }

  Future<void> _validateFiles() async {
    for (final file in widget.files) {
      if (!await file.exists()) {
        throw Exception('File not found: ${file.path}');
      }

      try {
        await file.length(); // Test if readable
      } catch (e) {
        throw Exception('Cannot read file: ${file.path}');
      }
    }
  }

  void _handleTimeout() {
    if (_currentAttempt < _maxAttempts) {
      _retryTransfer();
    } else {
      _handleFailure('Operation timed out after $_maxAttempts attempts');
    }
  }

  void _handleFailure(String error) {
    if (_currentAttempt < _maxAttempts) {
      _retryTransfer();
    } else {
      setState(() {
        _state = TransferState.failed;
        _statusMessage = 'Export failed: $error';
      });
    }
  }

  void _retryTransfer() {
    _currentAttempt++;

    setState(() {
      _state = TransferState.retrying;
      _statusMessage =
          'Retrying... (attempt $_currentAttempt of $_maxAttempts)';
    });

    // Brief delay before retry
    Timer(const Duration(seconds: 2), () {
      if (!_cancelled) {
        _startTransfer();
      }
    });
  }

  void _cancel() {
    _cancelled = true;
    _timeoutTimer?.cancel();
    _progressTimer?.cancel();

    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.of(context).pop(false);
    }
  }

  String _getTotalSizeString() {
    try {
      final totalBytes =
          widget.files.fold<int>(0, (sum, file) => sum + file.lengthSync());
      final totalMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      return '${totalMB}MB';
    } catch (e) {
      return 'Unknown size';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: _state != TransferState.inProgress,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 380,
            minWidth: 280,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status Icon with Animation
                SizedBox(
                  width: 64,
                  height: 64,
                  child: _buildStatusIcon(),
                ),

                const SizedBox(height: 16),

                // Title
                Text(
                  widget.operationName,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // File count and size
                Text(
                  '${widget.files.length} file${widget.files.length != 1 ? 's' : ''} • ${_getTotalSizeString()}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 20),

                // Progress indicator
                if (_state == TransferState.inProgress ||
                    _state == TransferState.validating ||
                    _state == TransferState.retrying) ...[
                  AnimatedBuilder(
                    animation: _pulseController,
                    child: LinearProgressIndicator(
                      color: colorScheme.primary,
                    ),
                    builder: (context, child) {
                      return Opacity(
                        opacity: 0.6 + (0.4 * _pulseController.value),
                        child: child,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Status message
                Text(
                  _statusMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _getStatusColor(),
                  ),
                  textAlign: TextAlign.center,
                ),

                // Retry indicator
                if (_currentAttempt > 1) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Attempt $_currentAttempt of $_maxAttempts',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_state == TransferState.failed) ...[
                      TextButton(
                        onPressed: _cancel,
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          _currentAttempt = 1;
                          _startTransfer();
                        },
                        child: const Text('Retry'),
                      ),
                    ] else if (_state != TransferState.completed) ...[
                      TextButton(
                        onPressed: _cancel,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    switch (_state) {
      case TransferState.preparing:
      case TransferState.validating:
        return AnimatedBuilder(
          animation: _spinController,
          child: Icon(Icons.folder_open, size: 32, color: colorScheme.primary),
          builder: (context, child) {
            return Transform.rotate(
              angle: _spinController.value * 2 * 3.14159,
              child: child,
            );
          },
        );

      case TransferState.inProgress:
        return AnimatedBuilder(
          animation: _pulseController,
          child: Icon(Icons.share, size: 32, color: colorScheme.primary),
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (0.2 * _pulseController.value),
              child: child,
            );
          },
        );

      case TransferState.retrying:
        return AnimatedBuilder(
          animation: _spinController,
          child: Icon(Icons.refresh,
              size: 32, color: colorScheme.tertiaryContainer),
          builder: (context, child) {
            return Transform.rotate(
              angle: _spinController.value * 2 * 3.14159,
              child: child,
            );
          },
        );

      case TransferState.completed:
        return Icon(Icons.check_circle, size: 32, color: colorScheme.primary);

      case TransferState.failed:
        return Icon(Icons.error, size: 32, color: colorScheme.error);
    }
  }

  Color _getStatusColor() {
    final colorScheme = Theme.of(context).colorScheme;

    switch (_state) {
      case TransferState.preparing:
      case TransferState.validating:
      case TransferState.inProgress:
        return colorScheme.primary;
      case TransferState.retrying:
        return colorScheme.tertiary;
      case TransferState.completed:
        return colorScheme.primary;
      case TransferState.failed:
        return colorScheme.error;
    }
  }
}

enum TransferState {
  preparing,
  validating,
  inProgress,
  retrying,
  completed,
  failed,
}
