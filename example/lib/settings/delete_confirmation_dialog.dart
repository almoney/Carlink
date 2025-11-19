import 'package:flutter/material.dart';
import 'dart:io';

/// Confirmation dialog for deleting log files
class DeleteConfirmationDialog extends StatelessWidget {
  final List<File> files;
  final String operationType;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  const DeleteConfirmationDialog({
    required this.files,
    required this.operationType,
    required this.onConfirm,
    this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalSize = _getTotalSizeString();
    final isMultiple = files.length > 1;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 420,
          minWidth: 320,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_forever,
                  color: colorScheme.error,
                  size: 32,
                ),
              ),

              const SizedBox(height: 16),

              // Title
              Text(
                operationType,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // File Information
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isMultiple ? 'Files to delete:' : 'File to delete:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${files.length} file${files.length != 1 ? 's' : ''}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total size:',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          totalSize,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // File list (if multiple files)
              if (isMultiple && files.length <= 5) ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Column(
                      children: files.map((file) {
                        final fileName = file.path.split('/').last;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                Icons.description,
                                color: colorScheme.onSurfaceVariant,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  fileName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Warning Message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: colorScheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Permanent Deletion',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isMultiple
                          ? 'These files will be permanently deleted from your device. This action cannot be undone.'
                          : 'This file will be permanently deleted from your device. This action cannot be undone.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: onCancel ?? () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: Text(isMultiple ? 'Delete Files' : 'Delete File'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        foregroundColor: colorScheme.onError,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTotalSizeString() {
    try {
      final totalBytes = files.fold<int>(0, (sum, file) {
        try {
          return sum + file.lengthSync();
        } catch (e) {
          return sum;
        }
      });

      if (totalBytes < 1024) {
        return '${totalBytes}B';
      } else if (totalBytes < 1024 * 1024) {
        return '${(totalBytes / 1024).toStringAsFixed(1)}KB';
      } else {
        return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
      }
    } catch (e) {
      return 'Unknown size';
    }
  }

  /// Show the delete confirmation dialog
  static Future<bool> show({
    required BuildContext context,
    required List<File> files,
    required String operationType,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => DeleteConfirmationDialog(
            files: files,
            operationType: operationType,
            onConfirm: () => Navigator.of(context).pop(true),
            onCancel: () => Navigator.of(context).pop(false),
          ),
        ) ??
        false;
  }
}
