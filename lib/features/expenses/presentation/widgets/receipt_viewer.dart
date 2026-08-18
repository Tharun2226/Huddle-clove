import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen receipt viewer with pinch-zoom. Pass either a local [filePath]
/// or a remote [networkUrl] (not both required — file wins when present).
Future<void> showReceiptViewer(
  BuildContext context, {
  String? filePath,
  String? networkUrl,
}) async {
  final hasFile = filePath != null && filePath.isNotEmpty && File(filePath).existsSync();
  final hasNetwork = networkUrl != null && networkUrl.isNotEmpty;
  if (!hasFile && !hasNetwork) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close receipt',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    pageBuilder: (context, animation, secondaryAnimation) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Center(
                      child: hasFile
                          ? Image.file(
                              File(filePath!),
                              fit: BoxFit.contain,
                            )
                          : Image.network(
                              networkUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white54,
                                size: 48,
                              ),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black45,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const Positioned(
                  left: 16,
                  bottom: 16,
                  child: Text(
                    'Pinch to zoom',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
