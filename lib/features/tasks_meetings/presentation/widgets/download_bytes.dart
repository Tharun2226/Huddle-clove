import 'dart:typed_data';

import 'download_bytes_stub.dart'
    if (dart.library.html) 'download_bytes_web.dart' as impl;

Future<void> downloadBytesInBrowser({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  return impl.downloadBytesInBrowser(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
  );
}
