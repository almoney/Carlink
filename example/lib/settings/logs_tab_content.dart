import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:carlink/log.dart';
import 'enhanced_sharing.dart';
import 'export_warning_dialog.dart';
import 'delete_confirmation_dialog.dart';
import 'debug_apk_warning_dialog.dart';
import 'settings_tab_base.dart';
import 'logging_preferences.dart';
import 'dart:io';
import 'dart:async';

/// Logs tab content widget that provides file logging control and export functionality.
/// Contains toggle for file logging, status display, and sharing capabilities.
class LogsTabContent extends SettingsTabContent {
  const LogsTabContent({
    super.key,
    required super.carlink,
  }) : super(title: 'Logs');

  @override
  SettingsTabContentState<LogsTabContent> createState() =>
      _LogsTabContentState();
}

class _LogsTabContentState extends SettingsTabContentState<LogsTabContent>
    with ResponsiveTabMixin {
  // File logging state
  bool _fileLoggingEnabled = false;
  Map<String, dynamic>? _fileLoggingStatus;
  List<File> _logFiles = [];
  final Set<String> _selectedLogFiles = {};
  LogPreset _selectedLogLevel = LogPreset.silent;
  bool _debugWarningShown = false;

  @override
  Widget buildTabContent(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: responsivePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFileLoggingCard(),
          SizedBox(height: responsiveSpacing),
          _buildLogFilesCardWithActions(),
        ],
      ),
    );
  }

  /// Builds the file logging control card
  Widget _buildFileLoggingCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _buildCard(
      title: 'File Logging',
      icon: Icons.article,
      children: [
        // File logging toggle
        SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          title: Text(
            'Save logs to file',
            style: theme.textTheme.titleMedium,
          ),
          subtitle: Text(
            'Store app logs in private storage for debugging',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          value: _fileLoggingEnabled,
          onChanged: isProcessing ? null : _toggleFileLogging,
        ),

        // Log level selection
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log Level',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showLogLevelSelector,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedLogLevel.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _selectedLogLevel.color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedLogLevel.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Status information
        if (_fileLoggingStatus != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File Logging Status',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ..._buildFileLoggingStatusRows(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Builds the log files list card with integrated export actions
  Widget _buildLogFilesCardWithActions() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasSelection = _selectedLogFiles.isNotEmpty;

    return _buildCard(
      title: 'Log Files',
      icon: Icons.folder,
      children: [
        Text(
          '${_logFiles.length} log file${_logFiles.length != 1 ? 's' : ''} available',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ..._logFiles.map((file) => _buildLogFileItem(file)),

        // Export actions for selected files only
        if (_logFiles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Divider(color: colorScheme.outline, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: (isProcessing || !hasSelection)
                      ? null
                      : _shareSelectedLogs,
                  icon: const Icon(Icons.share),
                  label: Text(hasSelection
                      ? 'Share Selected (${_selectedLogFiles.length})'
                      : 'Share Selected'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (isProcessing || !hasSelection)
                      ? null
                      : _deleteSelectedLogs,
                  icon: const Icon(Icons.delete_forever),
                  label: Text(hasSelection
                      ? 'Delete Selected (${_selectedLogFiles.length})'
                      : 'Delete Selected'),
                  style: FilledButton.styleFrom(
                    backgroundColor: hasSelection ? colorScheme.error : null,
                    foregroundColor: hasSelection ? colorScheme.onError : null,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasSelection
                ? '${_selectedLogFiles.length} file${_selectedLogFiles.length != 1 ? 's' : ''} selected for actions'
                : 'Select files above for bulk actions, or use individual delete buttons',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Builds the share actions card
  /// Note: This method is currently unused but kept for potential future use
  // ignore: unused_element
  Widget _buildShareActionsCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasSelection = _selectedLogFiles.isNotEmpty;

    return _buildCard(
      title: 'Export Logs',
      icon: Icons.share,
      children: [
        // Share Actions Row
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed:
                    (_logFiles.isEmpty || isProcessing) ? null : _shareAllLogs,
                icon: const Icon(Icons.share),
                label: Text(_logFiles.isEmpty ? 'No Files' : 'Share All'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed:
                    (isProcessing || !hasSelection) ? null : _shareSelectedLogs,
                icon: const Icon(Icons.checklist),
                label: Text('Share (${_selectedLogFiles.length})'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Delete Actions Row
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    (_logFiles.isEmpty || isProcessing) ? null : _deleteAllLogs,
                icon: const Icon(Icons.delete_sweep),
                label: Text(_logFiles.isEmpty ? 'No Files' : 'Delete All'),
                style: FilledButton.styleFrom(
                  backgroundColor: _logFiles.isEmpty ? null : colorScheme.error,
                  foregroundColor:
                      _logFiles.isEmpty ? null : colorScheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: (isProcessing || !hasSelection)
                    ? null
                    : _deleteSelectedLogs,
                icon: const Icon(Icons.delete_forever),
                label: Text('Delete (${_selectedLogFiles.length})'),
                style: FilledButton.styleFrom(
                  backgroundColor: hasSelection ? colorScheme.error : null,
                  foregroundColor: hasSelection ? colorScheme.onError : null,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _getExportHelpText(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Builds a single log file item with checkbox
  Widget _buildLogFileItem(File file) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = file.path.split('/').last;
    final isSelected = _selectedLogFiles.contains(file.path);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _toggleFileSelection(file.path),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: colorScheme.primary, width: 2)
                : null,
          ),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleFileSelection(file.path),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatFileInfo(file),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Individual delete button
              IconButton(
                onPressed:
                    isProcessing ? null : () => _deleteIndividualFile(file),
                icon: Icon(
                  Icons.delete_outline,
                  color: isProcessing
                      ? colorScheme.onSurface.withValues(alpha: 0.38)
                      : colorScheme.error,
                  size: 20,
                ),
                tooltip: 'Delete this log file',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build file logging status display rows
  List<Widget> _buildFileLoggingStatusRows() {
    if (_fileLoggingStatus == null) return [];

    return [
      _buildStatusRow('Status',
          _fileLoggingStatus!['enabled'] == true ? 'Active' : 'Disabled'),
      _buildStatusRow('Current file size',
          _fileLoggingStatus!['currentFileSizeMB'] ?? '0.00'),
      _buildStatusRow(
          'Total files', _fileLoggingStatus!['totalFiles']?.toString() ?? '0'),
      _buildStatusRow(
          'Total size', '${_fileLoggingStatus!['totalSizeMB'] ?? '0.00'} MB'),
    ];
  }

  /// Build a single status row
  Widget _buildStatusRow(String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a card container
  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Format file information (size and date)
  String _formatFileInfo(File file) {
    try {
      final stat = file.statSync();
      final sizeKB = (stat.size / 1024).toStringAsFixed(1);
      final modified = stat.modified;
      final dateStr =
          '${modified.day}/${modified.month}/${modified.year} ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
      return '$sizeKB KB • $dateStr';
    } catch (e) {
      return 'Unknown size';
    }
  }

  /// Get contextual help text for export actions
  String _getExportHelpText() {
    if (_logFiles.isEmpty) {
      return 'Enable file logging to create exportable log files';
    } else if (_selectedLogFiles.isEmpty) {
      return 'Select files above for bulk actions, or use individual delete buttons';
    } else {
      return '${_selectedLogFiles.length} file${_selectedLogFiles.length != 1 ? 's' : ''} selected for actions';
    }
  }

  /// Delete all log files
  Future<void> _deleteAllLogs() async {
    if (_logFiles.isEmpty) return;

    final shouldDelete = await DeleteConfirmationDialog.show(
      context: context,
      files: _logFiles,
      operationType: 'Delete All Log Files',
    );

    if (!shouldDelete) {
      log('Delete all cancelled by user', tag: 'LOGS_TAB');
      return;
    }

    try {
      int deletedCount = 0;
      final List<String> failedFiles = [];

      for (final file in _logFiles) {
        try {
          await file.delete();
          deletedCount++;
          log('Deleted log file: ${file.path}', tag: 'LOGS_TAB');
        } catch (e) {
          failedFiles.add(file.path.split('/').last);
          log('Failed to delete ${file.path}: $e', tag: 'LOGS_TAB');
        }
      }

      // Clear selection and refresh file list
      setState(() {
        _selectedLogFiles.clear();
      });
      await _loadLogFiles();

      if (mounted) {
        if (failedFiles.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully deleted $deletedCount log files'),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Deleted $deletedCount files, failed to delete ${failedFiles.length}'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      log('Error during delete all operation: $e', tag: 'LOGS_TAB');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete operation failed: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Delete selected log files
  Future<void> _deleteSelectedLogs() async {
    if (_selectedLogFiles.isEmpty) return;

    final selectedFiles = _logFiles
        .where((file) => _selectedLogFiles.contains(file.path))
        .toList();

    if (selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected files no longer exist'),
        ),
      );
      return;
    }

    final shouldDelete = await DeleteConfirmationDialog.show(
      context: context,
      files: selectedFiles,
      operationType: 'Delete Selected Log Files',
    );

    if (!shouldDelete) {
      log('Delete selected cancelled by user', tag: 'LOGS_TAB');
      return;
    }

    try {
      int deletedCount = 0;
      final List<String> failedFiles = [];

      for (final file in selectedFiles) {
        try {
          await file.delete();
          deletedCount++;
          log('Deleted selected log file: ${file.path}', tag: 'LOGS_TAB');
        } catch (e) {
          failedFiles.add(file.path.split('/').last);
          log('Failed to delete selected ${file.path}: $e', tag: 'LOGS_TAB');
        }
      }

      // Clear selection and refresh file list
      setState(() {
        _selectedLogFiles.clear();
      });
      await _loadLogFiles();

      if (mounted) {
        if (failedFiles.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Successfully deleted $deletedCount selected files'),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Deleted $deletedCount files, failed to delete ${failedFiles.length}'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      log('Error during delete selected operation: $e', tag: 'LOGS_TAB');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete operation failed: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Delete an individual log file
  Future<void> _deleteIndividualFile(File file) async {
    final shouldDelete = await DeleteConfirmationDialog.show(
      context: context,
      files: [file],
      operationType: 'Delete Log File',
    );

    if (!shouldDelete) {
      log('Delete individual file cancelled by user', tag: 'LOGS_TAB');
      return;
    }

    try {
      await file.delete();
      log('Deleted individual log file: ${file.path}', tag: 'LOGS_TAB');

      // Remove from selection if it was selected
      setState(() {
        _selectedLogFiles.remove(file.path);
      });
      await _loadLogFiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted ${file.path.split('/').last}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      log('Failed to delete individual file ${file.path}: $e', tag: 'LOGS_TAB');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete file: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Toggle selection of a log file
  void _toggleFileSelection(String filePath) {
    setState(() {
      if (_selectedLogFiles.contains(filePath)) {
        _selectedLogFiles.remove(filePath);
      } else {
        _selectedLogFiles.add(filePath);
      }
    });
  }

  /// Share all available log files with enhanced progress dialog
  Future<void> _shareAllLogs() async {
    final context = this.context; // Capture context before async operations

    if (_logFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No log files available to share'),
        ),
      );
      return;
    }

    // Show warning dialog first
    if (!mounted) return;
    final shouldProceed = await ExportWarningDialog.show(
      context: context,
      files: _logFiles,
      operationType: 'Export All Logs',
    );

    if (!shouldProceed) {
      log('Export cancelled by user at warning dialog', tag: 'LOGS_TAB');
      return;
    }

    try {
      if (!context.mounted) return;
      final success = await EnhancedSharing.shareFilesWithProgress(
        context: context,
        files: _logFiles,
        operationName: 'Export All Logs',
        shareText:
            'Carlink Debug Logs (${_logFiles.length} files • ${EnhancedSharing.getFilesTotalSize(_logFiles)})',
      );

      if (success) {
        log('Successfully opened share dialog for ${_logFiles.length} files',
            tag: 'LOGS_TAB');
      } else {
        log('Share dialog was cancelled or failed', tag: 'LOGS_TAB');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export was cancelled'),
            ),
          );
        }
      }
    } catch (e) {
      log('Failed to share all logs: $e', tag: 'LOGS_TAB');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Share selected log files with enhanced progress dialog
  Future<void> _shareSelectedLogs() async {
    final context = this.context; // Capture context before async operations

    if (_selectedLogFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No log files selected'),
        ),
      );
      return;
    }

    final selectedFiles = _logFiles
        .where((file) => _selectedLogFiles.contains(file.path))
        .toList();

    if (selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected files no longer exist'),
        ),
      );
      return;
    }

    // Show warning dialog first
    if (!mounted) return;
    final shouldProceed = await ExportWarningDialog.show(
      context: context,
      files: selectedFiles,
      operationType: 'Export Selected Logs',
    );

    if (!shouldProceed) {
      log('Export cancelled by user at warning dialog', tag: 'LOGS_TAB');
      return;
    }

    try {
      if (!context.mounted) return;
      final success = await EnhancedSharing.shareFilesWithProgress(
        context: context,
        files: selectedFiles,
        operationName: 'Export Selected Logs',
        shareText:
            'Carlink Debug Logs (${selectedFiles.length} selected files • ${EnhancedSharing.getFilesTotalSize(selectedFiles)})',
      );

      if (success) {
        log('Successfully opened share dialog for ${selectedFiles.length} selected files',
            tag: 'LOGS_TAB');

        // Clear selection after successful share
        setState(() {
          _selectedLogFiles.clear();
        });
      } else {
        log('Share dialog was cancelled or failed for selected files',
            tag: 'LOGS_TAB');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Export was cancelled'),
            ),
          );
        }
      }
    } catch (e) {
      log('Failed to share selected logs: $e', tag: 'LOGS_TAB');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initializePreferences();
  }

  /// Initialize preferences and load saved settings
  Future<void> _initializePreferences() async {
    try {
      // Load saved preferences first
      await LoggingPreferences.instance.initialize();

      final savedLevel = await LoggingPreferences.instance.getLogLevel();
      final savedEnabled = await LoggingPreferences.instance.isLoggingEnabled();
      final isFirstLaunch = await LoggingPreferences.instance.isFirstLaunch();

      if (mounted) {
        // Show debug APK warning dialog if in debug mode
        if (kDebugMode && !_debugWarningShown) {
          _debugWarningShown = true;
          await _showDebugApkWarning();
        }

        setState(() {
          _selectedLogLevel = savedLevel;
          _fileLoggingEnabled = savedEnabled;
        });

        log('Loaded preferences: level=${savedLevel.name}, enabled=$savedEnabled, firstLaunch=$isFirstLaunch',
            tag: 'LOGS_TAB');

        // In debug mode: enforce Silent preset and disable file logging
        if (kDebugMode) {
          log('Debug APK detected - enforcing Silent preset and disabling file logging',
              tag: 'LOGS_TAB');
          await _enforceDebugApkSettings();
        } else {
          // Release mode: normal behavior
          // Only auto-enable on first launch if logging is not already configured
          if (isFirstLaunch && !savedEnabled) {
            log('First launch detected - enabling logging with Normal preset',
                tag: 'LOGS_TAB');
            await _enableLoggingByDefault();
          } else {
            // Apply saved preferences
            if (savedEnabled) {
              setLogPreset(savedLevel);
              await setFileLoggingEnabled(true);
            }
          }
        }

        // Load current status and files
        await _loadFileLoggingStatus();
        await _loadLogFiles();
      }
    } catch (e) {
      log('Failed to initialize preferences: $e', tag: 'LOGS_TAB');
      // Fallback to current behavior if preferences fail
      if (mounted) {
        await _loadFileLoggingStatus();
        await _loadLogFiles();
      }
    }
  }

  /// Show the debug APK warning dialog
  Future<void> _showDebugApkWarning() async {
    if (!mounted) return;
    await DebugApkWarningDialog.show(context);
  }

  /// Enforce safe settings for debug APK builds
  Future<void> _enforceDebugApkSettings() async {
    // Set to Silent preset
    setLogPreset(LogPreset.silent);
    setState(() {
      _selectedLogLevel = LogPreset.silent;
    });

    // Disable file logging if enabled
    if (_fileLoggingEnabled) {
      await setFileLoggingEnabled(false);
      setState(() {
        _fileLoggingEnabled = false;
      });
    }
  }

  /// Load current file logging status
  Future<void> _loadFileLoggingStatus() async {
    try {
      final status = await getFileLoggingStatus();
      if (mounted) {
        setState(() {
          _fileLoggingStatus = status;
          _fileLoggingEnabled = status['enabled'] == true;
        });
      }
    } catch (e) {
      log('Failed to load file logging status: $e', tag: 'LOGS_TAB');
    }
  }

  /// Enable logging by default with Normal preset
  Future<void> _enableLoggingByDefault() async {
    try {
      final success = await setFileLoggingEnabled(true);
      if (success) {
        setLogPreset(_selectedLogLevel); // Apply Normal preset
        log('File logging enabled by default with ${_selectedLogLevel.name} preset',
            tag: 'LOGS_TAB');

        if (mounted) {
          setState(() {
            _fileLoggingEnabled = true;
          });
          await _loadFileLoggingStatus();
          await _loadLogFiles(); // Refresh file list after enabling logging
        }
      }
    } catch (e) {
      log('Failed to enable logging by default: $e', tag: 'LOGS_TAB');
    }
  }

  /// Load available log files
  Future<void> _loadLogFiles() async {
    try {
      final files = await getLogFiles();
      final fileObjects = files
          .map((path) => File(path))
          .where((file) => file.existsSync())
          .toList();

      if (mounted) {
        setState(() {
          _logFiles = fileObjects;
          // Clear selection if files changed
          _selectedLogFiles.removeWhere((path) => !files.contains(path));
        });
      }
    } catch (e) {
      log('Failed to load log files: $e', tag: 'LOGS_TAB');
    }
  }

  /// Toggle file logging on/off
  Future<void> _toggleFileLogging(bool enabled) async {
    // In debug mode, show warning when trying to enable
    if (kDebugMode && enabled) {
      _showDebugApkSnackbar(
        'File logging disabled in debug builds. Use ADB logcat instead.',
      );
      return;
    }

    setProcessing(true);
    try {
      final success = await setFileLoggingEnabled(enabled);

      if (success) {
        // Save user preference
        await LoggingPreferences.instance.setLoggingEnabled(enabled);

        if (!enabled) {
          await LoggingPreferences.instance.setUserHasExplicitlyDisabled(true);
          log('User explicitly disabled logging', tag: 'LOGS_TAB');
        } else {
          await LoggingPreferences.instance.setUserHasExplicitlyDisabled(false);
        }

        // Apply selected log level when enabling
        if (enabled) {
          setLogPreset(_selectedLogLevel);
          log('Applied log preset: $_selectedLogLevel', tag: 'LOGS_TAB');
        }

        // Update status and reload files after change
        await _loadFileLoggingStatus();
        await _loadLogFiles();

        log('File logging ${enabled ? 'enabled' : 'disabled'}',
            tag: 'LOGS_TAB');
      } else {
        log('Failed to ${enabled ? 'enable' : 'disable'} file logging',
            tag: 'LOGS_TAB');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Failed to ${enabled ? 'enable' : 'disable'} file logging'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      log('Error toggling file logging: $e', tag: 'LOGS_TAB');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setProcessing(false);
    }
  }

  /// Show a snackbar for debug APK restrictions
  void _showDebugApkSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.bug_report, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show log level selection popup
  Future<void> _showLogLevelSelector() async {
    // In debug mode, block changing log level
    if (kDebugMode) {
      _showDebugApkSnackbar(
        'Log level locked to Silent in debug builds to prevent instability.',
      );
      return;
    }

    final selectedLevel = await showDialog<LogPreset>(
      context: context,
      builder: (context) => _LogLevelSelectorDialog(
        currentLevel: _selectedLogLevel,
      ),
    );

    if (selectedLevel != null && selectedLevel != _selectedLogLevel) {
      setState(() {
        _selectedLogLevel = selectedLevel;
      });

      // Save user preference
      await LoggingPreferences.instance.setLogLevel(selectedLevel);

      // Apply immediately if logging is enabled
      if (_fileLoggingEnabled) {
        setLogPreset(selectedLevel);
        log('Applied log preset: $selectedLevel', tag: 'LOGS_TAB');
      }
    }
  }
}

/// Log level selection dialog
class _LogLevelSelectorDialog extends StatelessWidget {
  final LogPreset currentLevel;

  const _LogLevelSelectorDialog({
    required this.currentLevel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // Calculate responsive dimensions
    final dialogWidth = (screenWidth * 0.85).clamp(420.0, 600.0);
    final maxDialogHeight = screenHeight * 0.8;

    // Responsive font sizes based on screen width
    final isLargeScreen = screenWidth > 600;
    final isMediumScreen = screenWidth > 400;

    return Dialog(
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: maxDialogHeight,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isLargeScreen ? 28.0 : 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Row(
                  children: [
                    Icon(Icons.tune,
                        color: colorScheme.primary,
                        size: isLargeScreen ? 28 : 24),
                    SizedBox(width: isLargeScreen ? 16 : 12),
                    Text(
                      'Select Log Level',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Log level options in two columns
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left column
                    Expanded(
                      child: Column(
                        children: [
                          _buildLogLevelOption(context, LogPreset.silent,
                              isLargeScreen, isMediumScreen),
                          _buildLogLevelOption(context, LogPreset.minimal,
                              isLargeScreen, isMediumScreen),
                          _buildLogLevelOption(context, LogPreset.normal,
                              isLargeScreen, isMediumScreen),
                          _buildLogLevelOption(context, LogPreset.performance,
                              isLargeScreen, isMediumScreen),
                        ],
                      ),
                    ),
                    SizedBox(width: isLargeScreen ? 16 : 12),
                    // Right column
                    Expanded(
                      child: Column(
                        children: [
                          _buildLogLevelOption(context, LogPreset.rxMessages,
                              isLargeScreen, isMediumScreen),
                          _buildLogLevelOption(context, LogPreset.videoOnly,
                              isLargeScreen, isMediumScreen),
                          _buildLogLevelOption(context, LogPreset.audioOnly,
                              isLargeScreen, isMediumScreen),
                          _buildLogLevelOption(context, LogPreset.debug,
                              isLargeScreen, isMediumScreen),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Cancel button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogLevelOption(BuildContext context, LogPreset level,
      bool isLargeScreen, bool isMediumScreen) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = level == currentLevel;
    final color = level.color;
    final name = level.displayName;
    final description = level.description;

    // Responsive dimensions
    final optionPadding = isLargeScreen ? 16.0 : (isMediumScreen ? 14.0 : 12.0);
    final indicatorSize = isLargeScreen ? 20.0 : (isMediumScreen ? 18.0 : 16.0);
    final checkIconSize = isLargeScreen ? 14.0 : (isMediumScreen ? 12.0 : 10.0);
    final horizontalSpacing =
        isLargeScreen ? 16.0 : (isMediumScreen ? 14.0 : 12.0);
    final verticalSpacing = isLargeScreen ? 4.0 : (isMediumScreen ? 3.0 : 2.0);
    final marginBottom = isLargeScreen ? 12.0 : (isMediumScreen ? 10.0 : 8.0);

    return Container(
      margin: EdgeInsets.only(bottom: marginBottom),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).pop(level),
          child: Container(
            padding: EdgeInsets.all(optionPadding),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.15)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? color : colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Selection indicator
                Container(
                  width: indicatorSize,
                  height: indicatorSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? color : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: isSelected
                      ? Icon(Icons.check,
                          color: colorScheme.surface, size: checkIconSize)
                      : null,
                ),
                SizedBox(width: horizontalSpacing),

                // Level info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: verticalSpacing),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
