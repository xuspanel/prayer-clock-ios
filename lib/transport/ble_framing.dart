import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// GATT Service & Characteristic UUIDs from `p4clock.html` lines 499-501.
const String kP4ServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kP4RxCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const String kP4TxCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// Maximum buffered incoming line length before rejecting (262,144 bytes, line 930).
const int kMaxBleBufferLength = 262144;

/// Computes the BLE write chunk size from negotiated MTU (`p4clock.html` line 856):
/// `bChunk = Math.max(20, Math.min(240, mtu - 3));`
int computeBleChunkSize(int? mtu) {
  final effectiveMtu = mtu ?? 23;
  return math.max(20, math.min(240, effectiveMtu - 3));
}

/// Splits a UTF-8 string into byte chunks of at most [chunkSize] bytes (`bleWrite`, lines 955-965).
List<Uint8List> chunkBlePayload(String text, int chunkSize) {
  final effectiveChunk = math.max(20, math.min(240, chunkSize));
  final bytes = utf8.encode(text);
  if (bytes.isEmpty) return const <Uint8List>[];
  final chunks = <Uint8List>[];
  for (int i = 0; i < bytes.length; i += effectiveChunk) {
    final end = math.min(i + effectiveChunk, bytes.length);
    chunks.add(Uint8List.sublistView(Uint8List.fromList(bytes), i, end));
  }
  return chunks;
}

/// Encodes a newline-delimited JSON request frame (`bleReq`, lines 656 & 977):
/// `JSON.stringify({id:id,p:p,m:post?1:0,a:a})+'\n'`
String encodeBleRequest({
  required int id,
  required String path,
  required bool post,
  required Map<String, dynamic> params,
}) {
  final coerced = <String, String>{};
  params.forEach((key, value) {
    if (value != null) {
      coerced[key] = value.toString();
    }
  });
  final frame = <String, dynamic>{
    'id': id,
    'p': path,
    'm': post ? 1 : 0,
    'a': coerced,
  };
  return '${jsonEncode(frame)}\n';
}

enum BleFrameKind {
  response,
  statusPush,
  console,
}

class BleDecodedFrame {
  final BleFrameKind kind;
  final int? id;
  final int? status;
  final dynamic data;
  final String? consoleLine;

  const BleDecodedFrame._({
    required this.kind,
    this.id,
    this.status,
    this.data,
    this.consoleLine,
  });

  factory BleDecodedFrame.response({
    required int id,
    required int status,
    required dynamic data,
  }) =>
      BleDecodedFrame._(
        kind: BleFrameKind.response,
        id: id,
        status: status,
        data: data,
      );

  factory BleDecodedFrame.statusPush(Map<String, dynamic> data) =>
      BleDecodedFrame._(
        kind: BleFrameKind.statusPush,
        data: data,
      );

  factory BleDecodedFrame.console(String line) => BleDecodedFrame._(
        kind: BleFrameKind.console,
        consoleLine: line,
      );
}

class BleOversizedFrameException implements Exception {
  final String message;
  const BleOversizedFrameException([
    this.message = 'Bluetooth reply exceeded receive limit',
  ]);

  @override
  String toString() => message;
}

/// Stateful newline-delimited BLE incoming data framer (`bleData` & `bleLine`, lines 920-953).
/// Handles arbitrary UTF-8 multi-byte splits across BLE notification packets.
class BleLineFramer {
  final List<int> _pendingBytes = <int>[];
  String _buffer = '';

  String get currentBuffer => _buffer;

  void reset() {
    _pendingBytes.clear();
    _buffer = '';
  }

  /// Feeds raw notification bytes into the framer and returns all complete frames.
  /// Throws [BleOversizedFrameException] if the incomplete line exceeds 262,144 chars.
  List<BleDecodedFrame> addBytes(List<int> chunk) {
    _pendingBytes.addAll(chunk);
    _decodeAvailableUtf8();

    final frames = <BleDecodedFrame>[];
    int newlineIdx;
    while ((newlineIdx = _buffer.indexOf('\n')) >= 0) {
      String line = _buffer.substring(0, newlineIdx);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      _buffer = _buffer.substring(newlineIdx + 1);
      if (line.isNotEmpty) {
        frames.add(parseLine(line));
      }
    }

    if (_buffer.length + _pendingBytes.length > kMaxBleBufferLength) {
      reset();
      throw const BleOversizedFrameException();
    }

    return frames;
  }

  void _decodeAvailableUtf8() {
    if (_pendingBytes.isEmpty) return;
    // Attempt decoding; if trailing bytes are an incomplete multi-byte UTF-8 sequence,
    // hold back up to 3 trailing bytes until the next packet arrives.
    for (int holdBack = 0; holdBack <= math.min(3, _pendingBytes.length); holdBack++) {
      final cut = _pendingBytes.length - holdBack;
      if (cut == 0) break;
      try {
        final decoded = utf8.decode(_pendingBytes.sublist(0, cut), allowMalformed: false);
        _buffer += decoded;
        _pendingBytes.removeRange(0, cut);
        return;
      } on FormatException {
        if (holdBack == math.min(3, _pendingBytes.length)) {
          // Malformed byte sequence; decode with replacement character so stream doesn't wedge
          _buffer += utf8.decode(_pendingBytes, allowMalformed: true);
          _pendingBytes.clear();
          return;
        }
      }
    }
  }

  /// Parses a single complete line (`bleLine`, lines 937-953).
  static BleDecodedFrame parseLine(String line) {
    if (line.startsWith('{')) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final rawId = map['id'];
          if (rawId is int && rawId > 0) {
            final status = (map['s'] is num) ? (map['s'] as num).toInt() : 200;
            return BleDecodedFrame.response(
              id: rawId,
              status: status,
              data: map['d'],
            );
          }
          if (map['ev'] == 'status') {
            final d = map['d'];
            if (d is Map) {
              return BleDecodedFrame.statusPush(Map<String, dynamic>.from(d));
            }
            return BleDecodedFrame.statusPush(<String, dynamic>{});
          }
        }
      } catch (_) {
        return BleDecodedFrame.console('<< $line');
      }
    }
    return BleDecodedFrame.console('<< $line');
  }
}

