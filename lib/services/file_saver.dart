import 'dart:typed_data';
import 'file_saver_io.dart' if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

/// Saves or shares downloaded bytes on the current platform:
/// - On iOS/mobile: writes to temporary directory via `path_provider` and opens the
///   native iOS Share / Save to Files sheet via `Share.shareXFiles` (`share_plus`).
/// - On Web: triggers a browser Blob download.
Future<void> saveOrShareBytes(Uint8List bytes, String fileName) =>
    impl.saveOrShareBytesImpl(bytes, fileName);

