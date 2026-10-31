import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_framing.dart';
import 'p4_transport.dart';

class _PendingBleRequest {
  final Completer<ApiResponse> completer;
  final Timer timer;

  _PendingBleRequest({
    required this.completer,
    required this.timer,
  });
}

/// Bluetooth Low Energy GATT transport implementation of [P4Transport].
///
/// Mirrors `p4clock.html` lines 785-1006:
/// - Service UUID `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
/// - RX Characteristic `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
/// - TX Characteristic `6e400003-b5a3-f393-e0a9-e50e24dcca9e`
/// - Chunk size `Math.max(20, Math.min(240, mtu - 3))` from `/api/hello`
/// - Sequential request queue `bQ`, 120s timeout, up to 5 auto-reconnect retries at 2s intervals.
class BleTransport extends P4Transport {
  final BluetoothDevice device;
  final void Function(String statusText, bool connected)? onConnectionStatus;
  final void Function()? onUnrecoverableDisconnect;
  final Future<void> Function()? onReconnected;

  BluetoothCharacteristic? _rxChar;
  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final BleLineFramer _framer = BleLineFramer();
  final Map<int, _PendingBleRequest> _pending = <int, _PendingBleRequest>{};
  final StreamController<StatusEvent> _statusController =
      StreamController<StatusEvent>.broadcast();
  final StreamController<String> _consoleController =
      StreamController<String>.broadcast();

  Future<void> _queue = Future<void>.value();
  int _nextId = 0;
  int _chunkSize = 20;
  int _negotiatedMtu = 23;
  String _boardBleName = 'P4-Clock';
  bool _manualDisconnect = false;
  bool _opening = false;
  Timer? _retryTimer;

  BleTransport({
    required this.device,
    this.onConnectionStatus,
    this.onUnrecoverableDisconnect,
    this.onReconnected,
  });

  @override
  String get mode => 'ble';

  @override
  String? get baseUrl => null;

  int get chunkSize => _chunkSize;
  int get negotiatedMtu => _negotiatedMtu;
  String get boardBleName => _boardBleName;

  @override
  Stream<StatusEvent> get statusStream => _statusController.stream;

  @override
  Stream<String> get consoleStream => _consoleController.stream;

  /// Opens the GATT connection, discovers NUS characteristics, subscribes to TX
  /// notifications, and negotiates MTU + name via `/api/hello` (`bleOpen`, lines 828-864).
  Future<void> open() async {
    if (_opening) {
      throw const P4TransportException('Connection already in progress');
    }
    if (_manualDisconnect) {
      throw const P4TransportException('Connection cancelled');
    }
    _opening = true;
    try {
      onConnectionStatus?.call('Connecting Bluetooth...', false);

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connSub ??= device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_opening) {
          _handleBleLost();
        }
      });

      final services = await device.discoverServices();
      final targetSvcGuid = Guid(kP4ServiceUuid);
      final targetRxGuid = Guid(kP4RxCharUuid);
      final targetTxGuid = Guid(kP4TxCharUuid);

      BluetoothService? nusService;
      for (final s in services) {
        if (s.uuid == targetSvcGuid) {
          nusService = s;
          break;
        }
      }
      if (nusService == null) {
        throw const P4TransportException(
          'Prayer Clock BLE service (6e400001-...) not found on device',
        );
      }

      BluetoothCharacteristic? rx;
      BluetoothCharacteristic? tx;
      for (final c in nusService.characteristics) {
        if (c.uuid == targetRxGuid) rx = c;
        if (c.uuid == targetTxGuid) tx = c;
      }
      if (rx == null || tx == null) {
        throw const P4TransportException(
          'Prayer Clock BLE RX/TX characteristics not found',
        );
      }

      _rxChar = rx;
      await _txSub?.cancel();

      // Initialise decoding before notifications can arrive (`p4clock.html` line 840).
      _framer.reset();
      _queue = Future<void>.value();
      _chunkSize = 20;

      _txSub = tx.onValueReceived.listen(_onNotificationData);
      await tx.setNotifyValue(true);

      if (_manualDisconnect) {
        await device.disconnect();
        throw const P4TransportException('Connection cancelled');
      }

      // Send `/api/hello` (`let h = await bleReq('/api/hello', {}, 0);`, line 854)
      final hello = await send('/api/hello', const <String, String>{}, post: false);
      final helloData = hello.mapData;
      final rawMtu = helloData['mtu'];
      _negotiatedMtu = (rawMtu is num && rawMtu > 0) ? rawMtu.toInt() : 23;
      _chunkSize = computeBleChunkSize(_negotiatedMtu);
      final rawName = helloData['name']?.toString();
      _boardBleName = (rawName != null && rawName.isNotEmpty)
          ? rawName
          : (device.platformName.isNotEmpty ? device.platformName : 'P4-Clock');

      onConnectionStatus?.call(
        'Bluetooth: connected to $_boardBleName (MTU $_negotiatedMtu)',
        true,
      );
    } finally {
      _opening = false;
    }
  }

  void _onNotificationData(List<int> bytes) {
    try {
      final frames = _framer.addBytes(bytes);
      for (final frame in frames) {
        switch (frame.kind) {
          case BleFrameKind.response:
            final pending = _pending.remove(frame.id);
            if (pending != null) {
              pending.timer.cancel();
              pending.completer.complete(
                ApiResponse(
                  status: frame.status ?? 200,
                  data: frame.data,
                ),
              );
            }
            break;
          case BleFrameKind.statusPush:
            final map = frame.data is Map<String, dynamic>
                ? frame.data as Map<String, dynamic>
                : <String, dynamic>{};
            _statusController.add(StatusEvent(map));
            break;
          case BleFrameKind.console:
            if (frame.consoleLine != null) {
              _consoleController.add(frame.consoleLine!);
            }
            break;
        }
      }
    } on BleOversizedFrameException catch (e) {
      _rejectPendingRequests(e.message);
      _consoleController.add('<< Invalid oversized Bluetooth reply');
    }
  }

  void _rejectPendingRequests(String reason) {
    final entries = _pending.values.toList();
    _pending.clear();
    for (final p in entries) {
      p.timer.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(P4TransportException(reason));
      }
    }
  }

  void _handleBleLost() {
    _rxChar = null;
    _framer.reset();
    _rejectPendingRequests('Bluetooth disconnected');
    if (_manualDisconnect) {
      onConnectionStatus?.call('Bluetooth disconnected', false);
      onUnrecoverableDisconnect?.call();
      return;
    }
    onConnectionStatus?.call('Bluetooth lost - reconnecting...', false);
    _scheduleRetry(1);
  }

  void _scheduleRetry(int attempt) {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () async {
      if (_manualDisconnect) return;
      try {
        await open();
        await onReconnected?.call();
      } catch (_) {
        if (attempt < 5 && !_manualDisconnect) {
          _scheduleRetry(attempt + 1);
        } else {
          onConnectionStatus?.call(
            'Bluetooth lost - press Connect Bluetooth',
            false,
          );
          onUnrecoverableDisconnect?.call();
        }
      }
    });
  }

  Future<void> _bleWrite(String payload) async {
    final rx = _rxChar;
    if (rx == null) {
      throw const P4TransportException('Bluetooth not connected');
    }
    final chunks = chunkBlePayload(payload, _chunkSize);
    final bool withoutResponse =
        !rx.properties.write && rx.properties.writeWithoutResponse;
    for (final chunk in chunks) {
      if (!identical(rx, _rxChar)) {
        throw const P4TransportException('Bluetooth connection changed');
      }
      await rx.write(chunk, withoutResponse: withoutResponse);
    }
  }

  @override
  Future<ApiResponse> send(
    String path,
    Map<String, String> params, {
    bool post = false,
    Duration? timeout,
  }) {
    Future<ApiResponse> run() {
      final completer = Completer<ApiResponse>();
      if (_rxChar == null) {
        completer.completeError(const P4TransportException('not connected'));
        return completer.future;
      }
      final id = ++_nextId;
      final effectiveTimeout = timeout ?? const Duration(milliseconds: 120000);
      final timer = Timer(effectiveTimeout, () {
        _pending.remove(id);
        if (!completer.isCompleted) {
          completer.completeError(const P4TransportException('timeout'));
        }
      });

      _pending[id] = _PendingBleRequest(
        completer: completer,
        timer: timer,
      );

      final encoded = encodeBleRequest(
        id: id,
        path: path,
        post: post,
        params: params,
      );

      _bleWrite(encoded).catchError((Object e) {
        final w = _pending.remove(id);
        if (w != null) {
          w.timer.cancel();
          if (!w.completer.isCompleted) {
            w.completer.completeError(e);
          }
        }
      });

      return completer.future;
    }

    final next = _queue.then((_) => run(), onError: (_) => run());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> sendConsoleLine(String line) async {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    final redacted = RegExp(r'^pin(?:\s|$)', caseSensitive: false).hasMatch(trimmed)
        ? 'pin [hidden]'
        : trimmed;
    _consoleController.add('>> $redacted');

    final next = _queue.then(
      (_) => _bleWrite('$trimmed\n'),
      onError: (_) => _bleWrite('$trimmed\n'),
    );
    _queue = next.catchError((_) {});
    await next;
  }

  Future<void> disconnectManually() async {
    _manualDisconnect = true;
    _retryTimer?.cancel();
    _rejectPendingRequests('Bluetooth disconnected');
    _rxChar = null;
    try {
      await _txSub?.cancel();
      await _connSub?.cancel();
      if (device.isConnected) {
        await device.disconnect();
      }
    } catch (_) {}
    onConnectionStatus?.call('Bluetooth disconnected', false);
  }

  @override
  Future<void> dispose() async {
    await disconnectManually();
    await _statusController.close();
    await _consoleController.close();
  }
}

