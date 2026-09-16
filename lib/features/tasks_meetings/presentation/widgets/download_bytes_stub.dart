import 'dart:typed_data';

/// Non-web stub — prefer [SharePlus] / native save on mobile/desktop.
Future<void> downloadBytesInBrowser({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  throw UnsupportedError('Browser download is only available on web');
}
