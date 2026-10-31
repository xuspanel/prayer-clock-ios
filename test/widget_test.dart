import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prayer_clock/main.dart';
import 'package:prayer_clock/state/clock_controller.dart';
import 'package:prayer_clock/transport/ble_framing.dart';
import 'package:prayer_clock/transport/p4_transport.dart';

/// Mock implementation of [P4Transport] for deterministic unit and widget testing.
class MockP4Transport extends P4Transport {
  @override
  final String mode;

  @override
  final String? baseUrl;

  final StreamController<StatusEvent> statusController =
      StreamController<StatusEvent>.broadcast();
  final StreamController<String> consoleController =
      StreamController<String>.broadcast();

  final List<({String path, Map<String, String> params, bool post})> calls = [];
  Map<String, dynamic> Function(
    String path,
    Map<String, String> params,
    bool post,
  )? handler;

  MockP4Transport({
    this.mode = 'ble',
    this.baseUrl,
    this.handler,
  });

  @override
  Stream<StatusEvent> get statusStream => statusController.stream;

  @override
  Stream<String> get consoleStream => consoleController.stream;

  @override
  Future<ApiResponse> send(
    String path,
    Map<String, String> params, {
    bool post = false,
    Duration? timeout,
  }) async {
    calls.add((path: path, params: Map<String, String>.from(params), post: post));
    if (handler != null) {
      final res = handler!(path, params, post);
      final status = (res['_status'] is int) ? res['_status'] as int : 200;
      final body = res['_body'] ?? res;
      return ApiResponse(status: status, data: body);
    }

    // Default responses for session startup
    switch (path) {
      case '/api/auth':
        return const ApiResponse(status: 200, data: {'ok': true});
      case '/api/status':
        return const ApiResponse(
          status: 200,
          data: {
            'clock': '14:35',
            'date': '2026-10-31',
            'hijri': '20 Jumada I 1448',
            'bat': 88,
            'wifi': 'HomeLAN',
            'next': 'Maghrib 17:42',
            'fw': 'v2.4.1',
            'src': 'music',
            'title': 'Surah_Yasin.mp3',
            'pos': 65,
            'dur': 185,
            'playing': true,
            'vol': 14,
            'track': 1,
            'pt': [310, 395, 730, 1050, 1062],
            'nexti': 4,
            'cfg': 1,
          },
        );
      case '/api/settings':
        if (post) {
          return const ApiResponse(status: 200, data: {'ok': true});
        }
        return const ApiResponse(
          status: 200,
          data: {
            'bname': 'MasjidClock',
            'defble': 'P4-Clock',
            'defhost': 'prayerclock',
            'method': 0,
            'methods': ['MWL', 'Umm al-Qura'],
            'mang': [18.0, 18.5],
            'tzs': ['Asia/Riyadh', 'UTC'],
            'tzsel': 0,
            'tzval': '',
            'tz': 'Asia/Riyadh',
            'city': 'Makkah',
            'lat': 21.4225,
            'lon': 39.8262,
            'hijri': 0,
            'h24': true,
            'bright': 75,
            'locksec': 120,
            'az': [true, true, true],
            'azvol': 18,
            'lead': 0,
            'magh': 12,
            'azbg': true,
            'azfiles': ['/azan/azan.mp3', '/azan/azan_fajr.mp3'],
            'azfile': '/azan/azan.mp3',
            'azfajr': '/azan/azan_fajr.mp3',
            'azmag': '/azan/azan.mp3',
            'fangle': 0,
            'keep': true,
          },
        );
      case '/api/list':
        return const ApiResponse(
          status: 200,
          data: ['01_Fatiha.mp3', 'Surah_Yasin.mp3', 'Dua_Kumayl.mp3'],
        );
      case '/api/alarms':
        return const ApiResponse(
          status: 200,
          data: [
            {
              'on': true,
              't': '04:40',
              'l': 'Suhoor',
              'd': '30 min before Fajr (Ramadan)',
              'label': 'Suhoor',
              'hour': 4,
              'min': 40,
              'days': 127,
              'rel': 0,
              'offset': -30,
              'ram': true,
              'useDate': false,
              'year': 2026,
              'month': 10,
              'day': 31,
              'sound': '/alarms/beep.mp3',
              'vol': 16,
            },
            {
              'on': false,
              't': '07:00',
              'l': 'Morning',
              'd': 'Mon-Fri',
              'label': 'Morning',
              'hour': 7,
              'min': 0,
              'days': 62,
              'rel': -1,
              'offset': 0,
              'ram': false,
              'useDate': false,
              'year': 2026,
              'month': 10,
              'day': 31,
              'sound': '',
              'vol': 12,
            },
          ],
        );
      case '/api/fs/list':
        if (params['path'] == '/alarms') {
          return const ApiResponse(
            status: 200,
            data: {
              'ok': true,
              'path': '/alarms',
              'dirs': <String>[],
              'files': [
                {'n': 'beep.mp3', 's': 12400},
                {'n': 'chime.wav', 's': 34000},
              ],
            },
          );
        }
        return const ApiResponse(
          status: 200,
          data: {'ok': true, 'path': '/', 'dirs': ['music', 'alarms'], 'files': []},
        );
      case '/api/wifi':
        return const ApiResponse(
          status: 200,
          data: {'ip': '192.168.1.77', 'status': 'Connected', 'con': true, 'keep': true},
        );
      case '/api/cmd':
      case '/api/alarm':
      case '/api/alarm/test':
        return const ApiResponse(status: 200, data: {'ok': true});
      default:
        return const ApiResponse(status: 200, data: {'ok': true});
    }
  }

  @override
  Future<void> sendConsoleLine(String line) async {
    consoleController.add('>> $line');
  }

  @override
  Future<void> dispose() async {
    await statusController.close();
    await consoleController.close();
  }
}

void main() {
  group('BLE Transport Decoders & Chunking Unit Tests', () {
    test('computeBleChunkSize clamps MTU-3 to [20, 240]', () {
      expect(computeBleChunkSize(null), 20);
      expect(computeBleChunkSize(23), 20);
      expect(computeBleChunkSize(15), 20);
      expect(computeBleChunkSize(100), 97);
      expect(computeBleChunkSize(185), 182);
      expect(computeBleChunkSize(243), 240);
      expect(computeBleChunkSize(512), 240);
    });

    test('chunkBlePayload slices UTF-8 payload at exact MTU-3 boundaries', () {
      final payload = 'A' * 55;
      final chunks = chunkBlePayload(payload, 20);
      expect(chunks.length, 3);
      expect(chunks[0].length, 20);
      expect(chunks[1].length, 20);
      expect(chunks[2].length, 15);
      final reassembled = utf8.decode(chunks.expand((c) => c).toList());
      expect(reassembled, payload);
    });

    test('encodeBleRequest coerces all parameter values to String and appends newline', () {
      final line = encodeBleRequest(
        id: 42,
        path: '/api/settings',
        post: true,
        params: {
          'pin': '1234',
          'h24': 1,
          'azvol': 18,
          'fangle': 18.5,
        },
      );
      expect(line.endsWith('\n'), isTrue);
      final decoded = jsonDecode(line.trim()) as Map<String, dynamic>;
      expect(decoded['id'], 42);
      expect(decoded['p'], '/api/settings');
      expect(decoded['m'], 1);
      expect(decoded['a'], {
        'pin': '1234',
        'h24': '1',
        'azvol': '18',
        'fangle': '18.5',
      });
    });

    test('BleLineFramer reassembles fragmented packets, CRLF, status pushes, and console lines', () {
      final framer = BleLineFramer();
      const rawStream =
          '{"id":7,"s":200,"d":{"ok":true,"mtu":185}}\r\n'
          '{"ev":"status","d":{"clock":"12:30","vol":15}}\n'
          'plain console output\n';
      final bytes = utf8.encode(rawStream);

      // Feed in small 11-byte fragments to simulate BLE packet splitting
      final frames = <BleDecodedFrame>[];
      for (int i = 0; i < bytes.length; i += 11) {
        final end = (i + 11 < bytes.length) ? i + 11 : bytes.length;
        frames.addAll(framer.addBytes(bytes.sublist(i, end)));
      }

      expect(frames.length, 3);
      expect(frames[0].kind, BleFrameKind.response);
      expect(frames[0].id, 7);
      expect(frames[0].status, 200);
      expect((frames[0].data as Map)['mtu'], 185);

      expect(frames[1].kind, BleFrameKind.statusPush);
      expect((frames[1].data as Map)['clock'], '12:30');

      expect(frames[2].kind, BleFrameKind.console);
      expect(frames[2].consoleLine, '<< plain console output');
    });

    test('BleLineFramer handles split multi-byte UTF-8 characters across packets', () {
      final framer = BleLineFramer();
      final bytes = utf8.encode('{"id":1,"s":200,"d":{"title":"🕌 Fajr • آذان"}}\n');
      // Split right inside the multi-byte emoji/Arabic sequence
      final part1 = bytes.sublist(0, 31);
      final part2 = bytes.sublist(31);

      expect(framer.addBytes(part1), isEmpty);
      final frames = framer.addBytes(part2);
      expect(frames.length, 1);
      expect(frames.first.kind, BleFrameKind.response);
      expect((frames.first.data as Map)['title'], '🕌 Fajr • آذان');
    });

    test('BleLineFramer rejects oversized (>262,144 bytes) unterminated lines', () {
      final framer = BleLineFramer();
      final huge = List<int>.filled(kMaxBleBufferLength + 10, 65);
      expect(
        () => framer.addBytes(huge),
        throwsA(isA<BleOversizedFrameException>()),
      );
      expect(framer.currentBuffer, isEmpty);
    });
  });

  group('Widget Tests: Remote Tab & Alarms Edit Sheet', () {
    testWidgets('Remote tab displays live track info, playlist, and sends transport commands',
        (WidgetTester tester) async {
      final mockTransport = MockP4Transport();
      final controller = ClockController();
      await controller.useCustomTransport(mockTransport);
      // Push live status over BLE stream
      mockTransport.statusController.add(
        const StatusEvent({
          'clock': '14:35',
          'next': 'Maghrib 17:42',
          'src': 'music',
          'title': 'Surah_Yasin.mp3',
          'pos': 65,
          'dur': 185,
          'playing': true,
          'vol': 14,
          'track': 1,
          'pt': [310, 395, 730, 1050, 1062],
          'nexti': 4,
        }),
      );

      await tester.pumpWidget(PrayerClockApp(controller: controller));
      await tester.pumpAndSettle();

      // Verify Remote tab title & formatted duration (65s = 1:05, 185s = 3:05)
      expect(find.byKey(const Key('remote_title')), findsOneWidget);
      expect(find.text('♫ Surah_Yasin.mp3'), findsOneWidget);
      expect(find.text('1:05 / 3:05'), findsOneWidget);

      // Verify playlist items rendered
      expect(find.text('1.  01_Fatiha.mp3'), findsOneWidget);
      expect(find.text('2.  Surah_Yasin.mp3'), findsOneWidget);

      // Tap Next button -> sends /api/cmd with c=next
      await tester.tap(find.byKey(const Key('btn_next')));
      await tester.pump();
      expect(
        mockTransport.calls.any(
          (c) => c.path == '/api/cmd' && c.params['c'] == 'next',
        ),
        isTrue,
      );

      // Tap playlist track 0 -> sends /api/cmd with c=track, v=0
      await tester.ensureVisible(find.byKey(const Key('playlist_item_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_item_0')));
      await tester.pump();
      expect(
        mockTransport.calls.any(
          (c) =>
              c.path == '/api/cmd' &&
              c.params['c'] == 'track' &&
              c.params['v'] == '0',
        ),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 7));
      controller.dispose();
    });

    testWidgets('Alarms tab opens Alarm edit card, previews relative prayer ring time, validates and saves',
        (WidgetTester tester) async {
      final mockTransport = MockP4Transport();
      final controller = ClockController();
      await controller.useCustomTransport(mockTransport);
      mockTransport.statusController.add(
        const StatusEvent({
          'clock': '14:35',
          'pt': [310, 395, 730, 1050, 1062], // Fajr = 310 (05:10)
          'nexti': 2,
        }),
      );

      await tester.pumpWidget(PrayerClockApp(controller: controller));
      await tester.pumpAndSettle();

      // Switch to Alarms tab (index 2)
      await tester.tap(find.byKey(const Key('tab_btn_2')));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 of 2 alarms on.'), findsOneWidget);
      expect(find.textContaining('04:40   Suhoor'), findsOneWidget);

      // Tap alarm #1 to open edit card (#aed)
      await tester.ensureVisible(find.byKey(const Key('alarm_tap_0')));
      await tester.tap(find.byKey(const Key('alarm_tap_0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('alarm_edit_card')), findsOneWidget);
      expect(find.text('Edit alarm #1'), findsOneWidget);
      // Relative preview: Fajr is 05:10 (310m), offset -30m -> rings at 04:40
      expect(
        find.text('Today it rings at 04:40  (Fajr is at 05:10)'),
        findsOneWidget,
      );

      // Update title and save
      await tester.enterText(
        find.byKey(const Key('alarm_edit_title')),
        'Early Suhoor',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('btn_alarm_save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_alarm_save')));
      await tester.pumpAndSettle();

      final saveCall = mockTransport.calls.lastWhere(
        (c) => c.path == '/api/alarm' && c.post,
      );
      expect(saveCall.params['label'], 'Early Suhoor');
      expect(saveCall.params['rel'], '0');
      expect(saveCall.params['offset'], '-30');
      expect(saveCall.params['ram'], '1');
      // Editor closes after save
      expect(find.byKey(const Key('alarm_edit_card')), findsNothing);
      await tester.pump(const Duration(seconds: 7));
      controller.dispose();
    });
  });
}
