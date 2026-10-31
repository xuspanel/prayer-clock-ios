import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'p4_transport.dart';

/// WiFi HTTP transport implementation of [P4Transport].
///
/// Mirrors `p4clock.html` lines 663-668, 1903-1911, 2003-2032, and 2065-2110.
class HttpTransport extends P4Transport {
  final String _baseUrl;
  final http.Client _client;
  final StreamController<StatusEvent> _statusController =
      StreamController<StatusEvent>.broadcast();
  final StreamController<String> _consoleController =
      StreamController<String>.broadcast();

  HttpTransport({
    required String baseUrl,
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  @override
  String get mode => 'wifi';

  @override
  String? get baseUrl => _baseUrl;

  @override
  Stream<StatusEvent> get statusStream => _statusController.stream;

  @override
  Stream<String> get consoleStream => _consoleController.stream;

  @override
  Future<ApiResponse> send(
    String path,
    Map<String, String> params, {
    bool post = false,
    Duration? timeout,
  }) async {
    final coerced = <String, String>{};
    params.forEach((k, v) => coerced[k] = v.toString());
    final query = Uri(queryParameters: coerced).query;
    final uri = Uri.parse(post ? '$_baseUrl$path' : '$_baseUrl$path?$query');

    final effectiveTimeout = timeout ?? const Duration(seconds: 30);
    http.Response response;
    if (post) {
      response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Cache-Control': 'no-store',
            },
            body: query,
          )
          .timeout(effectiveTimeout);
    } else {
      response = await _client
          .get(
            uri,
            headers: const {
              'Cache-Control': 'no-store',
            },
          )
          .timeout(effectiveTimeout);
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = <String, dynamic>{'err': response.body};
      }
    } else {
      decoded = <String, dynamic>{};
    }

    return ApiResponse(
      status: response.statusCode,
      data: decoded,
    );
  }

  @override
  Future<Uint8List> downloadHttpFile(
    String path,
    String pin, {
    void Function(int loaded, int? total)? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final query = Uri(queryParameters: {'pin': pin, 'path': path}).query;
    final uri = Uri.parse('$_baseUrl/api/fs/get?$query');
    final request = http.Request('GET', uri);
    final streamed = await _client.send(request);

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw P4TransportException(
        'HTTP ${streamed.statusCode}',
        statusCode: streamed.statusCode,
      );
    }

    final total = streamed.contentLength;
    final builder = BytesBuilder(copy: false);
    int loaded = 0;

    await for (final chunk in streamed.stream) {
      if (isCancelled != null && await isCancelled()) {
        throw const P4TransportException('cancelled');
      }
      builder.add(chunk);
      loaded += chunk.length;
      onProgress?.call(loaded, total);
    }

    return builder.takeBytes();
  }

  @override
  Future<Map<String, dynamic>> uploadHttpFile(
    Uint8List bytes, {
    void Function(int loaded, int total)? onProgress,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/fs/put');
    final request = http.StreamedRequest('POST', uri);
    request.headers['Content-Type'] = 'application/octet-stream';
    request.contentLength = bytes.length;

    // Stream in 16 KB chunks to report smooth upload progress
    unawaited(() async {
      const int chunkSize = 16384;
      int offset = 0;
      try {
        while (offset < bytes.length) {
          final end =
              (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
          request.sink.add(Uint8List.sublistView(bytes, offset, end));
          offset = end;
          onProgress?.call(offset, bytes.length);
          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        await request.sink.close();
      }
    }());

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) {
        decoded = Map<String, dynamic>.from(raw);
      }
    } catch (_) {}

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] != true) {
      throw P4TransportException(
        (decoded['err']?.toString()) ?? 'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  @override
  Future<Map<String, dynamic>> uploadOtaFirmware(
    String fileName,
    Uint8List bytes,
    String pin, {
    void Function(int loaded, int total)? onProgress,
  }) async {
    final query = Uri(queryParameters: {'pin': pin}).query;
    final uri = Uri.parse('$_baseUrl/api/ota?$query');
    final multipart = http.MultipartRequest('POST', uri);
    multipart.files.add(
      http.MultipartFile.fromBytes(
        'firmware',
        bytes,
        filename: fileName,
      ),
    );

    final byteStream = multipart.finalize();
    final total = multipart.contentLength;
    final streamedRequest = http.StreamedRequest('POST', uri);
    streamedRequest.headers.addAll(multipart.headers);
    streamedRequest.contentLength = total;

    int loaded = 0;
    byteStream.listen(
      (chunk) {
        loaded += chunk.length;
        streamedRequest.sink.add(chunk);
        onProgress?.call(loaded, total);
      },
      onDone: () {
        streamedRequest.sink.close();
      },
      onError: (Object e) {
        streamedRequest.sink.addError(e);
        streamedRequest.sink.close();
      },
      cancelOnError: true,
    );

    final streamedResponse = await _client.send(streamedRequest);
    final response = await http.Response.fromStream(streamedResponse);
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map) {
        decoded = Map<String, dynamic>.from(raw);
      }
    } catch (_) {}

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['ok'] != true) {
      throw P4TransportException(
        'Failed: ${decoded['err'] ?? 'HTTP ${response.statusCode}'}',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  @override
  Future<void> sendConsoleLine(String line) async {
    throw UnsupportedError('Bluetooth console is only available in BLE mode');
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _consoleController.close();
    _client.close();
  }
}

