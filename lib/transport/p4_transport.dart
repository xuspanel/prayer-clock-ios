import 'dart:async';
import 'dart:typed_data';

/// Represents a normalized response `{s, d}` from either WiFi HTTP or BLE GATT.
///
/// Mirrors `p4clock.html` lines 667 & 973:
/// `{s: r.status, d: d}` and BLE `{"id":<n>,"s":<http-status>,"d":<body>}`.
class ApiResponse {
  final int status;
  final dynamic data;

  const ApiResponse({
    required this.status,
    required this.data,
  });

  Map<String, dynamic> get mapData {
    if (data is Map<String, dynamic>) {
      return data as Map<String, dynamic>;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data as Map);
    }
    return <String, dynamic>{};
  }
}

/// Asynchronous status event pushed over BLE (`{"ev":"status","d":{...}}`)
/// or emitted by periodic `/api/status` polling over WiFi.
class StatusEvent {
  final Map<String, dynamic> data;

  const StatusEvent(this.data);
}

/// Transport exception carrying HTTP/BLE status code when applicable.
class P4TransportException implements Exception {
  final int? statusCode;
  final String message;

  const P4TransportException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Mandatory transport abstraction (§5) hiding whether WiFi HTTP or BLE is active.
abstract class P4Transport {
  /// `'wifi'` or `'ble'`.
  String get mode;

  /// Base URL (`http://<ip>`) when `mode == 'wifi'`, or `null` on BLE.
  String? get baseUrl;

  /// Sends a request to [path] with query/body parameters [params].
  /// All parameter values are coerced to strings (`for(let k in a) a[k]=String(a[k])`).
  Future<ApiResponse> send(
    String path,
    Map<String, String> params, {
    bool post = false,
    Duration? timeout,
  });

  /// Asynchronous status stream (`{"ev":"status","d":{...}}`).
  Stream<StatusEvent> get statusStream;

  /// Console log stream (`<< ...` and `>> ...` lines in Bluetooth console).
  Stream<String> get consoleStream;

  /// Sends a raw text command line over the BLE console (`conSend()`).
  Future<void> sendConsoleLine(String line);

  /// Downloads a file over HTTP (`GET /api/fs/get`) with progress callback.
  /// Only supported on `HttpTransport`; on `BleTransport`, chunked `/api/fs/read` is used.
  Future<Uint8List> downloadHttpFile(
    String path,
    String pin, {
    void Function(int loaded, int? total)? onProgress,
    Future<bool> Function()? isCancelled,
  }) {
    throw UnsupportedError('Direct HTTP download requires WiFi transport');
  }

  /// Uploads raw file bytes via `POST /api/fs/put` (`application/octet-stream`) after `/api/fs/upbegin`.
  Future<Map<String, dynamic>> uploadHttpFile(
    Uint8List bytes, {
    void Function(int loaded, int total)? onProgress,
  }) {
    throw UnsupportedError('Direct HTTP upload requires WiFi transport');
  }

  /// Uploads firmware `.bin` via multipart `POST /api/ota?pin=<pin>`.
  Future<Map<String, dynamic>> uploadOtaFirmware(
    String fileName,
    Uint8List bytes,
    String pin, {
    void Function(int loaded, int total)? onProgress,
  }) {
    throw UnsupportedError('OTA update requires WiFi transport');
  }

  Future<void> dispose();
}

// ---------- Formatting & validation helpers verbatim from p4clock.html ----------

/// `function p2(n){return (n<10?'0':'')+n}` (line 540)
String p2(int n) => (n < 10 ? '0' : '') + n.toString();

/// `function hm(m)` (lines 542-547)
String formatHm(int? m, {bool h24 = true}) {
  if (m == null || m < 0) return '--:--';
  final h = m ~/ 60;
  final x = m % 60;
  if (!h24) {
    final h12 = (h % 12) == 0 ? 12 : (h % 12);
    return '$h12:${p2(x)}${h < 12 ? ' AM' : ' PM'}';
  }
  return '${p2(h)}:${p2(x)}';
}

/// `function f(s)` (lines 549-553)
String formatDuration(num? s) {
  final sec = (s == null || s < 0) ? 0 : s.floor();
  final h = sec ~/ 3600;
  final m = (sec ~/ 60) % 60;
  final x = sec % 60;
  final prefix = h > 0 ? '$h:${m < 10 ? '0' : ''}' : '';
  return '$prefix$m:${p2(x)}';
}

/// `function sz(b)` (lines 555-560)
String formatSize(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

/// `function J(a,b){return (a=='/'?'':a)+'/'+b}` (line 562)
String joinPath(String a, String b) => '${a == '/' ? '' : a}/$b';

/// `function up(p){let i=p.lastIndexOf('/');return i<=0?'/':p.slice(0,i)}` (line 563)
String parentPath(String p) {
  final i = p.lastIndexOf('/');
  return i <= 0 ? '/' : p.substring(0, i);
}

/// `function bn(p){return String(p).slice(String(p).lastIndexOf('/')+1)}` (line 564)
String baseName(String p) => p.substring(p.lastIndexOf('/') + 1);

/// `const PN=['Fajr','Sunrise','Dhuhr','Sunset','Maghrib'];` (line 510)
const List<String> prayerNames = ['Fajr', 'Sunrise', 'Dhuhr', 'Sunset', 'Maghrib'];

/// `const AZPT=[0,2,4];` (line 511)
const List<int> azanPrayerIndices = [0, 2, 4];

/// `const DN=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];` (line 512)
const List<String> dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// `const AUD=/\.(mp3|m4a|aac|wav|flac|ogg)$/i;` (line 513)
final RegExp audioFileRegex = RegExp(r'\.(mp3|m4a|aac|wav|flac|ogg)$', caseSensitive: false);

bool isAudioFile(String path) => audioFileRegex.hasMatch(path);

/// `function validClockName(n)` (lines 615-619)
bool validClockName(String n) {
  if (n.length > 20) return false;
  if (n.isEmpty) return true;
  return RegExp(r'^[A-Za-z0-9 _.-]+$').hasMatch(n) &&
      RegExp(r'[A-Za-z0-9]').hasMatch(n);
}

/// `function hostForName(n)` (lines 621-624)
String hostForName(String n, {String? defHost}) {
  final h = n
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (h.isNotEmpty) return h;
  if (defHost != null && defHost.isNotEmpty) return defHost;
  return 'prayerclock';
}

/// `function validFileName(n)` (lines 1834-1836)
bool validFileName(String n) {
  if (n.isEmpty || n == '.' || n == '..') return false;
  return !RegExp(r'[/\\\x00-\x1f]').hasMatch(n);
}

