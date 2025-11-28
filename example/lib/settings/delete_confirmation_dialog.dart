import 'package:flutter/material.dart';
import 'dart:io';
import 'responsive_dialog.dart';

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

    return ResponsiveDialog(
      title: operationType,
      icon: Icons.delete_forever,
      iconColor: colorScheme.error,
      iconBackgroundColor: colorScheme.error.withValues(alpha: 0.15),
      content: [
        // File Information
        ResponsiveDialog.buildContentBox(
          context: context,
          child: Column(
            children: [
              ResponsiveDialog.buildInfoRow(
                context: context,
                label: isMultiple ? 'Files to delete:' : 'File to delete:',
                value: '${files.length} file${files.length != 1 ? 's' : ''}',
              ),
              const SizedBox(height: 4),
              ResponsiveDialog.buildInfoRow(
                context: context,
                label: 'Total size:',
                value: totalSize,
              ),
            ],
          ),
        ),

        // File list (if multiple files and not too many)
        if (isMultiple && files.length <= 5)
          ResponsiveDialog.buildContentBox(
            context: context,
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

        // Warning Message
        ResponsiveDialog.buildWarningBox(
          context: context,
          title: 'Permanent Deletion',
          icon: Icons.warning_amber,
          isError: true,
          message: isMultiple
              ? 'These files will be permanently deleted from your device. This action cannot be undone.'
              : 'This file will be permanently deleted from your device. This action cannot be undone.',
        ),
      ],
      actions: [
        TextButton(
          onPressed: onCancel ?? () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: onConfirm,
          icon: const Icon(Icons.delete_forever, size: 18),
          label: Text(isMultiple ? 'Delete Files' : 'Delete File'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
        ),
      ],
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
