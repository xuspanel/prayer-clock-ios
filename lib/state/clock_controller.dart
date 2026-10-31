import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/file_saver.dart';
import '../services/notification_service.dart';
import '../transport/ble_transport.dart';
import '../transport/http_transport.dart';
import '../transport/p4_transport.dart';

class UploadItem {
  final String name;
  final Uint8List bytes;

  const UploadItem({required this.name, required this.bytes});
}

class CityEntry {
  final String name;
  final double lat;
  final double lon;
  final String tz;

  const CityEntry({
    required this.name,
    required this.lat,
    required this.lon,
    required this.tz,
  });
}

class GeoCandidate {
  final String label;
  final double lat;
  final double lon;
  final String tz;

  const GeoCandidate({
    required this.label,
    required this.lat,
    required this.lon,
    required this.tz,
  });
}

class FsFileEntry {
  final String name;
  final int size;

  const FsFileEntry({required this.name, required this.size});
}

/// Central state controller for the Prayer Clock app using `provider` (`ChangeNotifier`).
///
/// Mirrors the state & functions of `p4clock.html` (lines 528-2147) 1:1 while routing
/// all network and BLE calls through [P4Transport].
class ClockController extends ChangeNotifier {
  final NotificationService _notifications;
  SharedPreferences? _prefs;

  P4Transport? _transport;
  StreamSubscription<StatusEvent>? _statusSub;
  StreamSubscription<String>? _consoleSub;
  Timer? _statusPollTimer;
  Timer? _msgClearTimer;
  Timer? _volDebounceTimer;
  Timer? _briDebounceTimer;
  Timer? _alarmVolDebounceTimer;
  Timer? _geoPollTimer;
  Timer? _wifiPollTimer;
  Timer? _maintCountdownTimer;

  // Connection & auth state
  String _mode = ''; // '', 'wifi', 'ble'
  String _baseUrl = '';
  String _pin = ''; // Never persisted!
  String _ipInput = '';
  String _connText = 'Not connected - press Connect Bluetooth';
  bool _connOk = false;
  bool _ready = false;
  bool _busy = false;
  int _connectionEpoch = 0;
  bool _showLoginModal = false;
  String _loginMessage = '';
  bool _boardUnreachable = false;
  bool _wasBackgrounded = false;
  String _lifecycleBanner = '';

  // Toast message (#msg)
  String _toastMessage = '';

  // Active tab index (0..7)
  int _activeTabIndex = 0;

  // Mutual exclusion transfer flags
  bool _upBusy = false;
  bool _dlBusy = false;
  bool _fwBusy = false;
  bool _upStop = false;
  bool _mtGo = false;
  bool _setSaving = false;
  bool _cfgBusy = false;

  // Live status & settings state
  int? _lastCfg;
  String? _lastWifi;
  Map<String, dynamic>? _lastSt;
  Map<String, dynamic>? _setD;
  List<String> _methods = <String>[];
  List<double> _methodAngles = <double>[];
  List<String> _tzList = <String>[];
  String _boardBleName = 'P4-Clock';
  DateTime _lastVolumeDrag = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastNotifiedEventKey = '';

  // Dirty flags (`dirty.pray`, `dirty.loc`, `dirty.set`)
  bool dirtyPray = false;
  bool dirtyLoc = false;
  bool dirtySet = false;

  // Remote / playlist
  List<String> _playlist = <String>[];
  int _currentTrackIndex = -1;

  // Alarms
  List<Map<String, dynamic>> _rawAlarms = <Map<String, dynamic>>[];
  List<String> _alarmSounds = <String>[];
  int _editingAlarmIndex = -1;

  // Location / cities / geo
  String _citySearchMessage = '';
  List<CityEntry> _cityResults = <CityEntry>[];
  List<GeoCandidate> _geoResults = <GeoCandidate>[];
  String _lastGeoQuery = '';

  // WiFi tab
  Map<String, dynamic>? _wifiData;
  bool _keep0 = true;

  // Files tab
  bool _fsDone = false;
  String _cwd = '/';
  List<String> _fsDirs = <String>[];
  List<FsFileEntry> _fsFiles = <FsFileEntry>[];
  final Map<String, int> _fsSizes = <String, int>{};
  int? _fsTotal;
  int? _fsUsed;
  String? _selectedPath;
  bool _selectedIsDir = false;
  String? _clipboardPath;
  bool _clipboardIsCut = false;
  String _transferProgress = '';

  // System tab
  String _otaStatus = '';
  String _maintStatus = '';
  String _videoStatus = '';
  final List<String> _bleConsoleLines = <String>[];

  // Versions increments whenever `loadSet()` populates clean form fields
  int _settingsFormVersion = 0;

  ClockController({
    NotificationService? notifications,
  }) : _notifications = notifications ?? NotificationService();

  // Getters
  P4Transport? get transport => _transport;
  String get mode => _mode;
  String get baseUrl => _baseUrl;
  String get ipInput => _ipInput;
  String get connText => _connText;
  bool get connOk => _connOk;
  bool get ready => _ready;
  bool get showLoginModal => _showLoginModal;
  String get loginMessage => _loginMessage;
  bool get boardUnreachable => _boardUnreachable;
  bool get wasBackgrounded => _wasBackgrounded;
  String get lifecycleBanner => _lifecycleBanner;
  String get toastMessage => _toastMessage;
  int get activeTabIndex => _activeTabIndex;

  bool get upBusy => _upBusy;
  bool get dlBusy => _dlBusy;
  bool get fwBusy => _fwBusy;
  bool get anyTransferBusy => _upBusy || _dlBusy || _fwBusy;
  bool get setSaving => _setSaving;
  bool get mtGo => _mtGo;

  Map<String, dynamic>? get lastSt => _lastSt;
  Map<String, dynamic>? get setD => _setD;
  List<String> get methods => _methods;
  List<double> get methodAngles => _methodAngles;
  List<String> get tzList => _tzList;
  String get boardBleName => _boardBleName;
  int get settingsFormVersion => _settingsFormVersion;

  List<String> get playlist => _playlist;
  int get currentTrackIndex => _currentTrackIndex;

  List<Map<String, dynamic>> get rawAlarms => _rawAlarms;
  List<String> get alarmSounds => _alarmSounds;
  int get editingAlarmIndex => _editingAlarmIndex;

  String get citySearchMessage => _citySearchMessage;
  List<CityEntry> get cityResults => _cityResults;
  List<GeoCandidate> get geoResults => _geoResults;

  Map<String, dynamic>? get wifiData => _wifiData;
  bool get keep0 => _keep0;

  String get cwd => _cwd;
  List<String> get fsDirs => _fsDirs;
  List<FsFileEntry> get fsFiles => _fsFiles;
  Map<String, int> get fsSizes => _fsSizes;
  int? get fsTotal => _fsTotal;
  int? get fsUsed => _fsUsed;
  String? get selectedPath => _selectedPath;
  bool get selectedIsDir => _selectedIsDir;
  String? get clipboardPath => _clipboardPath;
  bool get clipboardIsCut => _clipboardIsCut;
  String get transferProgress => _transferProgress;

  String get otaStatus => _otaStatus;
  String get maintStatus => _maintStatus;
  String get videoStatus => _videoStatus;
  List<String> get bleConsoleLines => List<String>.unmodifiable(_bleConsoleLines);

  String get headingTitle {
    final bname = _setD?['bname']?.toString() ?? '';
    return '\u263E ${bname.isNotEmpty ? bname : 'Prayer Clock'}';
  }

  String get firmwareVersion => _lastSt?['fw']?.toString() ?? '';

  bool get is24Hour => (_setD?['h24'] == null) ? true : (_setD!['h24'] == true || _setD!['h24'] == 1);

  bool get isDraggingVolume =>
      DateTime.now().difference(_lastVolumeDrag).inMilliseconds <= 1500;

  /// Boot initialization (`p4clock.html` lines 525-526, 2114-2146).
  Future<void> initialize({P4Transport? injectedTransport}) async {
    try {
      _prefs = await SharedPreferences.getInstance();
      // Remove PINs persisted by older versions (`prefRemove('pin')`, line 526).
      await _prefs?.remove('pin');
      final savedIp = _prefs?.getString('ip') ?? '';
      if (savedIp.isNotEmpty) {
        _ipInput = savedIp;
      }
    } catch (_) {}

    if (injectedTransport != null) {
      await useCustomTransport(injectedTransport);
      return;
    }

    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      pollStatus();
    });
    notifyListeners();
  }

  /// Injects a custom or mock [P4Transport] (used in unit/widget tests or custom sessions).
  Future<void> useCustomTransport(
    P4Transport customTransport, {
    bool autoStart = true,
  }) async {
    await _disposeTransport();
    _resetConnectionData();
    _transport = customTransport;
    _mode = customTransport.mode;
    _baseUrl = customTransport.baseUrl ?? '';
    _connOk = true;
    _connText = _mode == 'ble'
        ? 'Bluetooth: connected to $_boardBleName'
        : 'WiFi: $_baseUrl';
    _statusSub = customTransport.statusStream.listen((ev) {
      if (_ready) {
        applyStatus(ev.data);
      }
    });
    _consoleSub = customTransport.consoleStream.listen(_appendConsoleLine);
    if (autoStart) {
      await _authenticate();
    }
    notifyListeners();
  }

  /// App lifecycle handling (§2.3: make it obvious when backgrounded/disconnected).
  void onAppLifecycleChanged(bool isForeground) {
    if (!isForeground) {
      _wasBackgrounded = true;
      if (_mode.isNotEmpty) {
        _lifecycleBanner =
            'App is in background — live updates pause until returned to foreground.';
      }
      notifyListeners();
    } else if (_wasBackgrounded) {
      _wasBackgrounded = false;
      if (_mode == 'wifi' && _ready) {
        _lifecycleBanner = '';
        pollStatus();
      } else if (_mode == 'ble' && !_connOk) {
        _lifecycleBanner =
            'Disconnected while app was in the background — tap Connect Bluetooth to reconnect.';
      } else {
        _lifecycleBanner = '';
      }
      notifyListeners();
    }
  }

  void dismissLifecycleBanner() {
    _lifecycleBanner = '';
    notifyListeners();
  }

  /// Shows a sticky message for 6,000 ms (`function msg(t)`, lines 566-569).
  void showMsg(String text) {
    _toastMessage = text;
    _msgClearTimer?.cancel();
    if (text.isNotEmpty) {
      _msgClearTimer = Timer(const Duration(milliseconds: 6000), () {
        if (_toastMessage == text) {
          _toastMessage = '';
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  void dismissMsg() {
    _msgClearTimer?.cancel();
    _toastMessage = '';
    notifyListeners();
  }

  void setIpInput(String value) {
    _ipInput = value;
  }

  Future<void> clearSavedIp() async {
    _ipInput = '';
    try {
      await _prefs?.remove('ip');
    } catch (_) {}
    showMsg('Saved board IP cleared');
    notifyListeners();
  }

  void _setConn(String text, [bool ok = false]) {
    _connText = text;
    _connOk = ok;
    notifyListeners();
  }

  void _resetConnectionData() {
    _connectionEpoch++;
    _ready = false;
    _lastCfg = null;
    _lastSt = null;
    _setD = null;
    _methods = <String>[];
    _methodAngles = <double>[];
    _tzList = <String>[];
    dirtyPray = false;
    dirtyLoc = false;
    dirtySet = false;
    _fsDone = false;
    _rawAlarms = <Map<String, dynamic>>[];
    _editingAlarmIndex = -1;
    _boardUnreachable = false;
    _geoPollTimer?.cancel();
    _wifiPollTimer?.cancel();
    _volDebounceTimer?.cancel();
    _briDebounceTimer?.cancel();
    _alarmVolDebounceTimer?.cancel();
    _maintCountdownTimer?.cancel();
  }

  Future<void> _disposeTransport() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await _consoleSub?.cancel();
    _consoleSub = null;
    final old = _transport;
    _transport = null;
    if (old != null) {
      await old.dispose();
    }
  }

  /// Core `api(p, a, post)` wrapper (`p4clock.html` lines 653-685).
  Future<dynamic> api(
    String path, [
    Map<String, dynamic>? params,
    bool post = false,
    Duration? timeout,
  ]) async {
    final activeTransport = _transport;
    if (activeTransport == null || _mode.isEmpty) {
      throw const P4TransportException('Not connected');
    }

    final coerced = <String, String>{};
    if (params != null) {
      params.forEach((k, v) {
        if (v != null) {
          coerced[k] = v.toString();
        }
      });
    }
    coerced['pin'] = _pin;

    final int epoch = _connectionEpoch;
    final ApiResponse r = await activeTransport.send(
      path,
      coerced,
      post: post,
      timeout: timeout,
    );

    if (epoch != _connectionEpoch) {
      throw const P4TransportException('epoch_changed', statusCode: 0);
    }

    if (r.status == 401) {
      _lock(_pin.isNotEmpty ? 'Wrong PIN' : '');
      throw const P4TransportException('Unauthorized', statusCode: 401);
    }
    if (r.status == 429) {
      _lock('Too many wrong PINs - wait 1 minute');
      throw const P4TransportException('Rate limited', statusCode: 429);
    }
    if (r.status < 200 || r.status >= 300) {
      final errText =
          (r.data is Map && r.data['err'] != null) ? r.data['err'].toString() : 'HTTP ${r.status}';
      throw P4TransportException(errText, statusCode: r.status);
    }
    return r.data;
  }

  void _lock(String message) {
    _ready = false;
    _volDebounceTimer?.cancel();
    _briDebounceTimer?.cancel();
    _alarmVolDebounceTimer?.cancel();
    _wifiPollTimer?.cancel();
    _geoPollTimer?.cancel();
    _showLoginModal = true;
    _loginMessage = message;
    notifyListeners();
  }

  Future<void> _authenticate() async {
    try {
      final res = await api('/api/auth');
      if (res is Map && res['ok'] == true) {
        _showLoginModal = false;
        _loginMessage = '';
        await _startSession();
      }
    } catch (e) {
      if (e is P4TransportException && (e.statusCode == 401 || e.statusCode == 429)) {
        // _lock already handled it
        return;
      }
      _boardUnreachable = true;
      showMsg('Could not reach board: $e');
    }
  }

  Future<void> login(String enteredPin) async {
    _pin = enteredPin.trim();
    try {
      final res = await api('/api/auth');
      if (res is Map && res['ok'] == true) {
        _showLoginModal = false;
        _loginMessage = '';
        await _startSession();
      }
    } catch (_) {}
  }

  void cancelLoginModal() {
    _showLoginModal = false;
    notifyListeners();
  }

  void logout() {
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer before locking this page');
      return;
    }
    _pin = '';
    _lock('');
  }

  /// Connects over WiFi (`function wifiIp()`, lines 729-770).
  Future<void> connectWifi([String? rawIp]) async {
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer before changing connection');
      return;
    }
    final ip = (rawIp ?? _ipInput)
        .trim()
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .replaceAll(RegExp(r'/+$'), '');
    if (ip.isEmpty) return;
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(ip)) {
      showMsg('Enter only the board IP address or hostname');
      return;
    }

    _ipInput = ip;
    try {
      await _prefs?.setString('ip', ip);
    } catch (_) {}

    await _disposeTransport();
    _resetConnectionData();

    _baseUrl = 'http://$ip';
    _mode = 'wifi';
    final httpTransport = HttpTransport(baseUrl: _baseUrl);
    _transport = httpTransport;
    _setConn('WiFi: $_baseUrl', true);

    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      pollStatus();
    });

    await _authenticate();
  }

  /// Connects to a selected BLE device (`bleConnect` + `bleOpen`, lines 789-864).
  Future<void> connectBleDevice(BluetoothDevice device) async {
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer before changing connection');
      return;
    }
    await _disposeTransport();
    _resetConnectionData();

    late final BleTransport bleTransport;
    bleTransport = BleTransport(
      device: device,
      onConnectionStatus: (text, connected) {
        _setConn(text, connected);
      },
      onUnrecoverableDisconnect: () {
        _ready = false;
        _connectionEpoch++;
        _mode = '';
        notifyListeners();
      },
      onReconnected: () async {
        _mode = 'ble';
        _boardBleName = bleTransport.boardBleName;
        await _authenticate();
      },
    );

    _transport = bleTransport;
    _statusSub = bleTransport.statusStream.listen((ev) {
      if (_ready) {
        applyStatus(ev.data);
      }
    });
    _consoleSub = bleTransport.consoleStream.listen(_appendConsoleLine);

    try {
      await bleTransport.open();
      _mode = 'ble';
      _baseUrl = '';
      _boardBleName = bleTransport.boardBleName;
      await _authenticate();
    } catch (e) {
      if (_mode == 'ble') _mode = '';
      _setConn('Bluetooth: $e', false);
      showMsg('Bluetooth error: $e');
    }
  }

  /// Disconnects active BLE connection (`function bleDisconnect()`, lines 903-918).
  Future<void> disconnectBle() async {
    if (_upBusy || _dlBusy) {
      showMsg('Finish or cancel the transfer before disconnecting');
      return;
    }
    _ready = false;
    _connectionEpoch++;
    await _disposeTransport();
    _mode = '';
    _setConn('Bluetooth disconnected', false);
  }

  void _appendConsoleLine(String line) {
    _bleConsoleLines.add(line);
    while (_bleConsoleLines.length > 300) {
      _bleConsoleLines.removeAt(0);
    }
    notifyListeners();
  }

  void clearBleConsole() {
    _bleConsoleLines.clear();
    notifyListeners();
  }

  Future<void> sendBleConsoleCommand(String rawCmd) async {
    final v = rawCmd.trim();
    if (v.isEmpty || _mode != 'ble') return;
    if (_upBusy || _dlBusy) {
      showMsg('Wait for the Bluetooth transfer to finish');
      return;
    }
    try {
      await _transport?.sendConsoleLine(v);
    } catch (e) {
      showMsg('Bluetooth console error: $e');
    }
  }

  /// `function start()` (lines 1010-1019).
  Future<void> _startSession() async {
    _ready = true;
    _fsDone = false;
    _lastCfg = null;
    notifyListeners();

    unawaited(pollStatus());
    unawaited(_ipFillFromBle());
    try {
      await loadSettings();
      await loadAlarms();
      await loadPlaylist();
    } catch (_) {}
    _onTabActivated(_activeTabIndex);
  }

  Future<void> _ipFillFromBle() async {
    if (_mode != 'ble' || !_ready) return;
    try {
      final d = await api('/api/wifi');
      if (d is Map) {
        final ip = d['ip']?.toString() ?? '';
        if (ip.isNotEmpty) {
          await _prefs?.setString('ip', ip);
          _ipInput = ip;
        } else {
          await _prefs?.remove('ip');
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  /// `function st()` (lines 1095-1101).
  Future<void> pollStatus() async {
    if (_mode != 'wifi' || _busy || !_ready || _upBusy || _fwBusy || _mtGo) {
      return;
    }
    _busy = true;
    try {
      final d = await api('/api/status');
      if (d is Map) {
        applyStatus(Map<String, dynamic>.from(d));
      }
    } catch (e) {
      if (e is P4TransportException && e.statusCode == 0) return;
      _boardUnreachable = true;
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  /// `function applyStatus(d)` (lines 1056-1093).
  void applyStatus(Map<String, dynamic> d) {
    _lastSt = d;
    _boardUnreachable = false;

    final wifiStr = d['wifi']?.toString();
    if (wifiStr != _lastWifi && !anyTransferBusy) {
      _lastWifi = wifiStr;
      unawaited(_ipFillFromBle());
    }

    final src = d['src']?.toString() ?? 'none';
    final isTest = d['test'] == true || d['test'] == 1;
    final isAlarmOrAzan = (src == 'alarm' || src == 'azan') && !isTest;
    final title = d['title']?.toString() ?? '';

    if (isAlarmOrAzan) {
      final key = '$src:$title';
      if (_lastNotifiedEventKey != key) {
        _lastNotifiedEventKey = key;
        unawaited(
          _notifications.showBoardEventNotification(
            isAlarm: src == 'alarm',
            title: title,
          ),
        );
      }
    } else {
      _lastNotifiedEventKey = '';
    }

    _currentTrackIndex = (src == 'music' && d['track'] is num)
        ? (d['track'] as num).toInt()
        : -1;

    final cfg = (d['cfg'] is num) ? (d['cfg'] as num).toInt() : null;
    if (cfg != null && cfg != _lastCfg) {
      final first = _lastCfg == null;
      _lastCfg = cfg;
      if (!first) {
        unawaited(_refreshFromBoard());
      }
    }

    notifyListeners();
  }

  Future<void> _refreshFromBoard() async {
    if (_cfgBusy || anyTransferBusy) return;
    _cfgBusy = true;
    try {
      await loadAlarms();
      await loadSettings();
      await loadPlaylist();
    } catch (_) {
    } finally {
      _cfgBusy = false;
    }
  }

  /// Tab switching (`switchTab` & `tabLoad`, lines 1165-1184).
  void switchTab(int index) {
    _activeTabIndex = index;
    notifyListeners();
    _onTabActivated(index);
  }

  void _onTabActivated(int index) {
    if (!_ready || anyTransferBusy) return;
    if (index == 6 && !_fsDone) {
      _fsDone = true;
      unawaited(loadFiles(_cwd));
      unawaited(loadFsInfo());
    }
    if (index == 5) {
      unawaited(loadWifi());
    }
  }

  void openFilesTab(String path) {
    _fsDone = true;
    _activeTabIndex = 6;
    notifyListeners();
    unawaited(loadFiles(path.isEmpty ? '/' : path));
    unawaited(loadFsInfo());
  }

  /// `function c(cmd, v)` (lines 1021-1027).
  Future<void> sendCmd(String cmd, [dynamic v]) async {
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    final params = <String, dynamic>{'c': cmd};
    if (v != null) {
      params['v'] = v;
    }
    try {
      final d = await api('/api/cmd', params);
      if (d is Map && d['ok'] != true && d['err'] != null) {
        showMsg(d['err'].toString());
      }
      Future<void>.delayed(const Duration(milliseconds: 300), pollStatus);
    } catch (e) {
      if (e is P4TransportException && e.statusCode == 0) return;
      showMsg(e.toString());
    }
  }

  /// `function vol(v)` (lines 1029-1034).
  void setVolumeDebounced(int v) {
    _lastVolumeDrag = DateTime.now();
    if (_lastSt != null) {
      _lastSt = Map<String, dynamic>.from(_lastSt!)..['vol'] = v;
      notifyListeners();
    }
    _volDebounceTimer?.cancel();
    _volDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      sendCmd('vol', v);
    });
  }

  /// `function bri(v)` (lines 1036-1045).
  void setBrightnessDebounced(int v) {
    if (_setD != null) {
      _setD = Map<String, dynamic>.from(_setD!)..['bright'] = v;
      notifyListeners();
    }
    _briDebounceTimer?.cancel();
    _briDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
      if (!_ready) return;
      try {
        final d = await api('/api/settings', {'bright': v, 'live': 1}, true);
        if (d is Map && d['ok'] != true && d['err'] != null) {
          showMsg(d['err'].toString());
        }
      } catch (_) {}
    });
  }

  /// `function list()` (lines 1152-1161).
  Future<void> loadPlaylist() async {
    try {
      final a = await api('/api/list');
      if (a is List) {
        _playlist = a.map((e) => e.toString()).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// `function loadSet()` (lines 1206-1272).
  Future<void> loadSettings() async {
    final params = _setD != null ? <String, dynamic>{'lists': 0} : <String, dynamic>{};
    final d = await api('/api/settings', params);
    if (d is! Map) return;
    final map = Map<String, dynamic>.from(d);

    if (map['methods'] is List) {
      _methods = (map['methods'] as List).map((e) => e.toString()).toList();
    }
    if (map['mang'] is List) {
      _methodAngles = (map['mang'] as List)
          .map((e) => double.tryParse(e.toString()) ?? 0.0)
          .toList();
    }
    if (map['tzs'] is List) {
      _tzList = (map['tzs'] as List).map((e) => e.toString()).toList();
    }

    _setD = map;
    final ble = map['ble']?.toString() ??
        map['bname']?.toString() ??
        map['defble']?.toString() ??
        'P4-Clock';
    _boardBleName = ble.isNotEmpty ? ble : 'P4-Clock';
    if (_mode == 'ble') {
      _setConn('Bluetooth: connected to $_boardBleName', true);
    }

    _keep0 = map['keep'] == true || map['keep'] == 1;
    _settingsFormVersion++;
    notifyListeners();
  }

  /// `function saveSet()` (lines 1274-1329).
  Future<void> saveGeneralSettings({
    required String bname,
    required int method,
    required int hijri,
    required bool h24,
    required String locksecRaw,
  }) async {
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    if (_setSaving) return;

    final n = bname.trim();
    if (!validClockName(n)) {
      showMsg('Invalid clock name');
      return;
    }
    final lock = locksecRaw.trim();
    final lockNum = int.tryParse(lock);
    if (!RegExp(r'^\d+$').hasMatch(lock) || lockNum == null || lockNum > 600) {
      showMsg('Auto-lock must be 0 - 600 seconds');
      return;
    }

    final oldHost = _setD?['host']?.toString();
    _setSaving = true;
    notifyListeners();

    try {
      final d = await api(
        '/api/settings',
        {
          'bname': n,
          'method': method,
          'hijri': hijri,
          'h24': h24 ? 1 : 0,
          'locksec': lock,
        },
        true,
      );
      if (d is Map) {
        final newHost = d['host']?.toString();
        final changed = newHost != null &&
            oldHost != null &&
            oldHost.isNotEmpty &&
            newHost != oldHost;
        String text = d['ok'] == true
            ? 'Settings saved'
            : (d['err']?.toString() ?? 'Save failed');
        if (newHost != null && newHost.isNotEmpty) {
          text += '. WiFi address: http://$newHost.local/';
          if (_setD != null) {
            _setD!['bname'] = n;
            _setD!['host'] = newHost;
            final bleName = d['ble']?.toString() ??
                (n.isNotEmpty ? n : (_setD!['defble']?.toString() ?? 'P4-Clock'));
            _setD!['ble'] = bleName;
            _boardBleName = bleName;
            if (_mode == 'ble') {
              _setConn('Bluetooth: connected to $_boardBleName', true);
            }
          }
        }
        if (changed) {
          text +=
              ' If this WiFi connection stops responding, open the new address or use the board IP.';
        }
        if (_mode == 'ble' && d['ble'] != null) {
          text += ' Scan again after disconnecting to see the new advertised name.';
        }
        showMsg(text);
        if (d['ok'] == true) {
          dirtySet = false;
          await loadSettings();
          await loadAlarms();
        }
      }
    } catch (e) {
      if (e is P4TransportException && e.statusCode == 0) return;
      showMsg('Could not save settings. Check the connection.');
    } finally {
      _setSaving = false;
      notifyListeners();
    }
  }

  /// `function savePray()` (lines 1331-1353).
  Future<void> savePrayerSettings({
    required List<bool> azEnabled,
    required String azFajrFile,
    required String azDhuhrFile,
    required String azMaghribFile,
    required String azVol,
    required String lead,
    required bool useMethodDefaultFajr,
    required String customFajrAngle,
    required String magh,
    required bool azbg,
  }) async {
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    final payload = <String, dynamic>{
      'azvol': azVol,
      'lead': lead,
      'magh': magh,
      'fangle': useMethodDefaultFajr ? 0 : customFajrAngle,
      'az0': (azEnabled.isNotEmpty && azEnabled[0]) ? 1 : 0,
      'az1': (azEnabled.length > 1 && azEnabled[1]) ? 1 : 0,
      'az2': (azEnabled.length > 2 && azEnabled[2]) ? 1 : 0,
      'azbg': azbg ? 1 : 0,
    };
    if (azDhuhrFile.isNotEmpty) {
      payload['azfile'] = azDhuhrFile;
      payload['azfajr'] = azFajrFile;
      payload['azmag'] = azMaghribFile;
    }

    try {
      final d = await api('/api/settings', payload, true);
      if (d is Map) {
        showMsg(d['ok'] == true ? 'Prayer settings saved' : (d['err']?.toString() ?? 'Error'));
        if (d['ok'] == true) {
          dirtyPray = false;
          await loadSettings();
          await loadAlarms();
        }
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  /// `function azTest(k)` (lines 1355-1361).
  Future<void> testAzan(int k, String file, String vol) async {
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    try {
      final d = await api(
        '/api/azan/test',
        {'k': k, 'file': file, 'vol': vol},
        true,
      );
      if (d is Map && d['ok'] != true && d['err'] != null) {
        showMsg(d['err'].toString());
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  /// `function saveLoc()` (lines 1363-1379).
  Future<void> saveLocationSettings({
    required String city,
    required String lat,
    required String lon,
    required int tzsel,
    required String tzval,
    required bool savecity,
  }) async {
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    try {
      final d = await api(
        '/api/settings',
        {
          'city': city,
          'lat': lat,
          'lon': lon,
          'tzsel': tzsel,
          'tzval': tzval,
          'savecity': savecity ? 1 : 0,
        },
        true,
      );
      if (d is Map) {
        final extra = (d['msg'] != null && d['msg'].toString().isNotEmpty)
            ? ' - ${d['msg']}'
            : '';
        showMsg(d['ok'] == true ? 'Location saved$extra' : (d['err']?.toString() ?? 'Error'));
        if (d['ok'] == true) {
          dirtyLoc = false;
          await loadSettings();
          await loadAlarms();
        }
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  /// `function clist()` (lines 1381-1399).
  Future<void> searchCities(String query) async {
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    try {
      final d = await api('/api/cities', {'q': query.trim()});
      if (d is Map) {
        final match = (d['match'] is num) ? (d['match'] as num).toInt() : 0;
        final total = (d['total'] is num) ? (d['total'] as num).toInt() : 0;
        final file = d['file']?.toString() ?? 'cities';
        final rawList = (d['list'] is List) ? (d['list'] as List) : const [];
        _geoResults = <GeoCandidate>[];
        _cityResults = rawList.whereType<Map>().map((x) {
          return CityEntry(
            name: x['n']?.toString() ?? '',
            lat: double.tryParse(x['lat']?.toString() ?? '0') ?? 0.0,
            lon: double.tryParse(x['lon']?.toString() ?? '0') ?? 0.0,
            tz: x['tz']?.toString() ?? '',
          );
        }).toList();
        _citySearchMessage = '$match of $total cities in $file'
            '${match > _cityResults.length ? ' - first ${_cityResults.length} shown, type to search' : ''}';
        notifyListeners();
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  /// `function useCity(n)` (lines 1401-1411).
  Future<void> useCity(String name) async {
    try {
      final d = await api('/api/city', {'a': 'use', 'name': name}, true);
      if (d is Map) {
        showMsg(d['ok'] == true ? 'Using $name' : (d['err']?.toString() ?? 'Error'));
        if (d['ok'] == true) {
          _cityResults = <CityEntry>[];
          _citySearchMessage = '';
          dirtyLoc = false;
          notifyListeners();
          await loadSettings();
          await loadAlarms();
        }
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> deleteCity(String name, String currentQuery) async {
    try {
      final r = await api('/api/city', {'a': 'del', 'name': name}, true);
      if (r is Map) {
        showMsg(r['ok'] == true ? 'Deleted' : (r['err']?.toString() ?? 'Error'));
        await searchCities(currentQuery);
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  /// `function geo()` & `function gpoll()` (lines 1413-1453).
  Future<void> startOnlineGeo(String query) async {
    final gq = query.trim();
    if (gq.isEmpty) {
      showMsg('Type a city name first');
      return;
    }
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    _lastGeoQuery = gq;
    try {
      final d = await api('/api/geo/start', {'q': gq}, true);
      if (d is Map) {
        if (d['ok'] != true) {
          showMsg(d['err']?.toString() ?? 'Failed');
          return;
        }
        _cityResults = <CityEntry>[];
        _geoResults = <GeoCandidate>[];
        notifyListeners();
        await _pollGeo();
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> _pollGeo() async {
    _geoPollTimer?.cancel();
    try {
      final d = await api('/api/geo');
      if (d is! Map) return;
      _citySearchMessage = d['msg']?.toString() ?? '';
      final state = d['state']?.toString() ?? '';
      if (state == 'busy') {
        notifyListeners();
        _geoPollTimer = Timer(const Duration(seconds: 1), _pollGeo);
        return;
      }
      if (state != 'done') {
        notifyListeners();
        return;
      }
      final list = (d['list'] is List) ? (d['list'] as List) : const [];
      if (list.length == 1) {
        await useOnlineGeo(0);
        return;
      }
      _geoResults = list.whereType<Map>().map((r) {
        return GeoCandidate(
          label: r['label']?.toString() ?? '',
          lat: double.tryParse(r['lat']?.toString() ?? '0') ?? 0.0,
          lon: double.tryParse(r['lon']?.toString() ?? '0') ?? 0.0,
          tz: r['tz']?.toString() ?? '',
        );
      }).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> useOnlineGeo(int index) async {
    try {
      final d = await api(
        '/api/geo/use',
        {'i': index, 'name': _lastGeoQuery},
        true,
      );
      if (d is Map) {
        final extra = (d['msg'] != null && d['msg'].toString().isNotEmpty)
            ? ' - ${d['msg']}'
            : '';
        showMsg(d['ok'] == true ? 'Location set$extra' : (d['err']?.toString() ?? 'Error'));
        if (d['ok'] == true) {
          _geoResults = <GeoCandidate>[];
          _citySearchMessage = '';
          dirtyLoc = false;
          notifyListeners();
          await loadSettings();
          await loadAlarms();
        }
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> cancelOnlineGeo() async {
    _geoPollTimer?.cancel();
    _geoResults = <GeoCandidate>[];
    _citySearchMessage = '';
    notifyListeners();
    try {
      await api('/api/geo/cancel', const <String, dynamic>{}, true);
    } catch (_) {}
  }

  // ---------- Alarms (lines 1535-1703) ----------

  Future<void> loadAlarms() async {
    try {
      final a = await api('/api/alarms');
      if (a is List) {
        _rawAlarms = a
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> toggleAlarm(int index, bool on) async {
    try {
      final d = await api('/api/alarm', {'i': index, 'on': on ? 1 : 0}, true);
      if (d is Map && d['ok'] != true && d['err'] != null) {
        showMsg(d['err'].toString());
      }
      await loadAlarms();
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> openAlarmEditor(int index) async {
    if (index < 0 || index >= _rawAlarms.length) return;
    _editingAlarmIndex = index;
    notifyListeners();
    await loadAlarmSounds();
  }

  Future<void> loadAlarmSounds() async {
    try {
      final d = await api('/api/fs/list', {'path': '/alarms'});
      if (d is Map && d['files'] is List) {
        final names = (d['files'] as List)
            .whereType<Map>()
            .map((x) => x['n']?.toString() ?? '')
            .where((n) => isAudioFile(n))
            .toList();
        names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _alarmSounds = names.map((n) => joinPath('/alarms', n)).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  void setAlarmTestVolumeDebounced(int vol) {
    _alarmVolDebounceTimer?.cancel();
    final isTesting = _lastSt?['test'] == true || _lastSt?['test'] == 1;
    if (isTesting) {
      _alarmVolDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        api('/api/alarm/test', {'a': 'vol', 'vol': vol}, true).catchError((_) {});
      });
    }
  }

  Future<void> testAlarmPlay(String soundPath, int vol) async {
    try {
      final d = await api(
        '/api/alarm/test',
        {'a': 'play', 'path': soundPath, 'vol': vol},
        true,
      );
      if (d is Map && d['ok'] != true && d['err'] != null) {
        showMsg(d['err'].toString());
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> testAlarmStop() async {
    try {
      await api('/api/alarm/test', {'a': 'stop'}, true);
    } catch (_) {}
  }

  void closeAlarmEditor() {
    _alarmVolDebounceTimer?.cancel();
    final isTesting = _lastSt?['test'] == true || _lastSt?['test'] == 1;
    if (isTesting) {
      unawaited(testAlarmStop());
    }
    _editingAlarmIndex = -1;
    notifyListeners();
  }

  Future<void> saveAlarm(Map<String, dynamic> payload) async {
    try {
      final d = await api('/api/alarm', payload, true);
      if (d is Map) {
        showMsg(d['ok'] == true ? 'Alarm saved' : (d['err']?.toString() ?? 'Error'));
        if (d['ok'] == true) {
          closeAlarmEditor();
        }
        await loadAlarms();
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> deleteEditingAlarm() async {
    final idx = _editingAlarmIndex;
    if (idx < 0) return;
    try {
      final d = await api('/api/alarm', {'i': idx, 'a': 'del'}, true);
      if (d is Map) {
        showMsg(d['ok'] == true ? 'Alarm deleted' : (d['err']?.toString() ?? 'Error'));
        if (d['ok'] == true) {
          closeAlarmEditor();
        }
        await loadAlarms();
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  // ---------- WiFi tab (lines 1707-1776) ----------

  Future<void> loadWifi() async {
    if (!_ready || _mtGo || anyTransferBusy) return;
    _wifiPollTimer?.cancel();
    try {
      final d = await api('/api/wifi');
      if (d is Map) {
        _wifiData = Map<String, dynamic>.from(d);
        _keep0 = d['keep'] == true || d['keep'] == 1;
        notifyListeners();
        if (_activeTabIndex == 5) {
          final isBusyScan = d['scan'] == 'busy';
          _wifiPollTimer = Timer(
            Duration(milliseconds: isBusyScan ? 1500 : 4000),
            loadWifi,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _wifiPost(Map<String, dynamic> params, String okMessage) async {
    try {
      final d = await api('/api/wifi', params, true);
      if (d is Map) {
        showMsg(d['ok'] == true ? okMessage : (d['err']?.toString() ?? 'Error'));
      }
      Future<void>.delayed(const Duration(milliseconds: 600), loadWifi);
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> scanWifi() async {
    await _wifiPost({'a': 'scan'}, 'Scanning...');
  }

  Future<void> joinWifi(String ssid, String pass) async {
    await _wifiPost(
      {'a': 'join', 'ssid': ssid, 'pass': pass},
      'Connecting to $ssid ...',
    );
  }

  Future<void> toggleWifiConnection(bool currentlyConnected) async {
    await _wifiPost(
      {'a': currentlyConnected ? 'disconnect' : 'connect'},
      currentlyConnected ? 'Disconnected' : 'Connecting...',
    );
  }

  Future<void> clearSavedWifi() async {
    await _wifiPost({'a': 'clear'}, 'Saved network erased');
  }

  Future<void> setWifiKeep(bool keep) async {
    await _wifiPost({'a': 'keep', 'v': keep ? 1 : 0}, 'Saved');
  }

  // ---------- Files tab (lines 1780-2061) ----------

  Future<void> loadFiles([String? path]) async {
    if (_upBusy || _dlBusy) return;
    final targetPath = path ?? _cwd;
    try {
      final d = await api('/api/fs/list', {'path': targetPath});
      if (d is! Map) return;
      if (d['ok'] != true) {
        showMsg(d['err']?.toString() ?? 'Failed to list files');
        return;
      }
      _cwd = d['path']?.toString() ?? targetPath;
      selectFile(null);
      _fsSizes.clear();

      final dirs = (d['dirs'] is List)
          ? (d['dirs'] as List).map((e) => e.toString()).toList()
          : <String>[];
      dirs.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _fsDirs = dirs;

      final files = <FsFileEntry>[];
      if (d['files'] is List) {
        for (final item in (d['files'] as List)) {
          if (item is Map) {
            final name = item['n']?.toString() ?? '';
            final sz = (item['s'] is num) ? (item['s'] as num).toInt() : 0;
            final fullPath = joinPath(_cwd, name);
            _fsSizes[fullPath] = sz;
            files.add(FsFileEntry(name: name, size: sz));
          }
        }
      }
      files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _fsFiles = files;

      if (d['more'] == true) {
        showMsg('Big folder - only the first part is shown');
      }
      notifyListeners();
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> loadFsInfo() async {
    try {
      final d = await api('/api/fs/info');
      if (d is Map && d['ok'] == true) {
        _fsTotal = (d['total'] is num) ? (d['total'] as num).toInt() : null;
        _fsUsed = (d['used'] is num) ? (d['used'] as num).toInt() : null;
        notifyListeners();
      }
    } catch (_) {}
  }

  void selectFile(String? path, {bool isDir = false}) {
    _selectedPath = path;
    _selectedIsDir = isDir;
    notifyListeners();
  }

  Future<void> _fsOp(String op, Map<String, dynamic> params, String okMsg) async {
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer first');
      return;
    }
    try {
      final d = await api('/api/fs/$op', params, true);
      if (d is Map) {
        showMsg(d['ok'] == true ? okMsg : (d['err']?.toString() ?? 'Error'));
        await loadFiles(_cwd);
        await loadFsInfo();
        if (d['ok'] == true) {
          await loadPlaylist();
        }
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> createFolder(String rawName) async {
    final n = rawName.trim();
    if (!validFileName(n)) {
      showMsg('Enter a name without slashes or control characters');
      return;
    }
    await _fsOp('mkdir', {'path': joinPath(_cwd, n)}, 'Folder created');
  }

  Future<void> deleteSelectedFile() async {
    final sel = _selectedPath;
    if (sel == null) return;
    await _fsOp('delete', {'path': sel}, 'Deleted');
  }

  Future<void> renameSelectedFile(String rawNewName) async {
    final sel = _selectedPath;
    if (sel == null) return;
    final n = rawNewName.trim();
    if (!validFileName(n)) {
      showMsg('Enter a name without slashes or control characters');
      return;
    }
    if (n != baseName(sel)) {
      await _fsOp(
        'move',
        {'from': sel, 'to': joinPath(parentPath(sel), n)},
        'Renamed',
      );
    }
  }

  void setClipboard({required bool cut}) {
    final sel = _selectedPath;
    if (sel == null) return;
    _clipboardPath = sel;
    _clipboardIsCut = cut;
    showMsg('${cut ? 'Cut: ' : 'Copied: '}$sel - open a folder and press Paste');
    notifyListeners();
  }

  Future<void> pasteClipboard() async {
    final clipPath = _clipboardPath;
    if (clipPath == null) return;
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer first');
      return;
    }
    final isCut = _clipboardIsCut;
    showMsg('${isCut ? 'Moving ' : 'Copying '}${baseName(clipPath)} ...');
    try {
      final d = await api(
        '/api/fs/${isCut ? 'move' : 'copy'}',
        {'from': clipPath, 'to': _cwd},
        true,
      );
      if (d is Map) {
        showMsg(d['ok'] == true
            ? (isCut ? 'Moved' : 'Copied')
            : (d['err']?.toString() ?? 'Error'));
        if (d['ok'] == true && isCut) {
          _clipboardPath = null;
        }
        await loadFiles(_cwd);
        await loadFsInfo();
        if (d['ok'] == true) {
          await loadPlaylist();
        }
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> playSelectedFile() async {
    final sel = _selectedPath;
    if (sel == null) return;
    try {
      final d = await api('/api/fs/play', {'path': sel}, true);
      if (d is Map) {
        showMsg(d['ok'] == true
            ? 'Playing ${baseName(sel)}'
            : (d['err']?.toString() ?? 'Error'));
        Future<void>.delayed(const Duration(milliseconds: 500), pollStatus);
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  void cancelTransfer() {
    _upStop = true;
    notifyListeners();
  }

  /// Downloads a file over BLE (`/api/fs/read` chunks) or WiFi (`/api/fs/get`)
  /// and opens the iOS Share / Save to Files sheet (`fdlPath` & `bleDownload`, lines 1899-1960).
  Future<void> downloadFile(String path) async {
    if (_dlBusy) {
      showMsg('A download is already running - wait or press Cancel');
      return;
    }
    if (_upBusy || _fwBusy) {
      showMsg('An upload is running - wait or press Cancel');
      return;
    }
    if (!_ready || _transport == null) {
      showMsg('Not connected or not unlocked');
      return;
    }

    _dlBusy = true;
    _upStop = false;
    _wifiPollTimer?.cancel();
    _transferProgress = 'Downloading ${baseName(path)}...';
    notifyListeners();

    final t0 = DateTime.now();
    try {
      Uint8List fileBytes;
      if (_mode == 'ble') {
        final builder = BytesBuilder(copy: false);
        int off = 0;
        int totalSize = _fsSizes[path] ?? 0;
        for (;;) {
          if (_upStop) throw const P4TransportException('cancelled');
          final d = await api('/api/fs/read', {'path': path, 'off': off});
          if (d is! Map || d['ok'] != true) {
            throw P4TransportException(
              (d is Map ? d['err']?.toString() : null) ?? 'Read failed',
            );
          }
          totalSize = (d['size'] is num) ? (d['size'] as num).toInt() : totalSize;
          final b64 = d['b64']?.toString() ?? '';
          final chunk = base64Decode(b64);
          final eof = d['eof'] == true || d['eof'] == 1;
          if (chunk.isEmpty && !eof) {
            throw const P4TransportException('Download made no progress');
          }
          builder.add(chunk);
          off += chunk.length;
          final elapsedSec =
              DateTime.now().difference(t0).inMilliseconds / 1000.0;
          final kbPerSec =
              (off / 1024.0) / (elapsedSec < 0.1 ? 0.1 : elapsedSec);
          final pct = totalSize > 0 ? ((off * 100) / totalSize).round() : 100;
          _transferProgress =
              'Downloading ${baseName(path)}  $pct%  (${kbPerSec.toStringAsFixed(1)} KB/s)';
          notifyListeners();
          if (eof) break;
        }
        fileBytes = builder.takeBytes();
      } else {
        fileBytes = await _transport!.downloadHttpFile(
          path,
          _pin,
          isCancelled: () async => _upStop,
          onProgress: (loaded, total) {
            final elapsedSec =
                DateTime.now().difference(t0).inMilliseconds / 1000.0;
            final kbPerSec =
                (loaded / 1024.0) / (elapsedSec < 0.1 ? 0.1 : elapsedSec);
            final pct = (total != null && total > 0)
                ? ((loaded * 100) / total).round()
                : 0;
            _transferProgress =
                'Downloading ${baseName(path)}  $pct%  (${kbPerSec.toStringAsFixed(1)} KB/s)';
            notifyListeners();
          },
        );
      }

      await saveOrShareBytes(fileBytes, baseName(path));
      showMsg('Saved ${baseName(path)} (${formatSize(fileBytes.length)})');
    } catch (e) {
      if (e is P4TransportException && e.statusCode == 0) return;
      showMsg('Download stopped: $e');
    } finally {
      _dlBusy = false;
      _transferProgress = '';
      notifyListeners();
      if (_activeTabIndex == 5) {
        unawaited(loadWifi());
      }
    }
  }

  /// Uploads one or more files over BLE (3072-byte chunks) or WiFi (`upl`, lines 1966-2061).
  Future<void> uploadFiles(List<UploadItem> files) async {
    if (files.isEmpty) return;
    if (!_ready || _mode.isEmpty || _transport == null) {
      showMsg('Unlock and connect first');
      return;
    }
    if (anyTransferBusy) {
      showMsg('Another transfer is running - wait or press Cancel');
      return;
    }

    final dir = _cwd;
    _upBusy = true;
    _upStop = false;
    _wifiPollTimer?.cancel();
    notifyListeners();

    try {
      for (int i = 0; i < files.length && !_upStop; i++) {
        if (_mode == 'ble') {
          await _bleUploadSingle(files[i], dir, i + 1, files.length);
        } else {
          await _webUploadSingle(files[i], dir, i + 1, files.length);
        }
      }
    } catch (e) {
      _upStop = true;
      if (e is! P4TransportException || e.statusCode != 0) {
        showMsg('Upload stopped: $e');
      }
    } finally {
      _upBusy = false;
      _transferProgress = '';
      notifyListeners();
      await loadFiles(_cwd);
      await loadFsInfo();
      await loadPlaylist();
      await pollStatus();
      if (_activeTabIndex == 5) {
        unawaited(loadWifi());
      }
    }
  }

  Future<void> _webUploadSingle(
    UploadItem item,
    String dir,
    int index,
    int totalCount,
  ) async {
    if (_upStop) return;
    final beginRes = await api(
      '/api/fs/upbegin',
      {'dir': dir, 'name': item.name},
      true,
    );
    if (beginRes is! Map || beginRes['ok'] != true) {
      throw P4TransportException(
        '${item.name}: ${(beginRes is Map ? beginRes['err'] : null) ?? 'failed'}',
      );
    }
    if (_upStop) return;

    final t0 = DateTime.now();
    await _transport!.uploadHttpFile(
      item.bytes,
      onProgress: (loaded, total) {
        final elapsedSec =
            DateTime.now().difference(t0).inMilliseconds / 1000.0;
        final kb = (loaded / 1024.0) / (elapsedSec < 0.1 ? 0.1 : elapsedSec);
        final pct = total > 0 ? ((loaded * 100) / total).round() : 0;
        _transferProgress =
            'Uploading ${item.name}  $pct%  (${kb.toStringAsFixed(0)} KB/s, $index of $totalCount)';
        notifyListeners();
      },
    );
  }

  Future<void> _bleUploadSingle(
    UploadItem item,
    String dir,
    int index,
    int totalCount,
  ) async {
    const int chunkBytes = 3072; // `const CH=3072;` (line 2035)
    final t0 = DateTime.now();
    bool begun = false;
    bool ended = false;
    try {
      final rBegin = await api(
        '/api/fs/up',
        {'a': 'begin', 'dir': dir, 'name': item.name},
        true,
      );
      if (rBegin is! Map || rBegin['ok'] != true) {
        throw P4TransportException(
          '${item.name}: ${(rBegin is Map ? rBegin['err'] : null) ?? 'failed'}',
        );
      }
      begun = true;

      final bytes = item.bytes;
      for (int off = 0; off < bytes.length; off += chunkBytes) {
        if (_upStop) {
          throw const P4TransportException('Upload cancelled');
        }
        final end =
            (off + chunkBytes < bytes.length) ? off + chunkBytes : bytes.length;
        final slice = Uint8List.sublistView(bytes, off, end);
        final b64 = base64Encode(slice);
        final rData = await api(
          '/api/fs/up',
          {'a': 'data', 'off': off, 'b64': b64},
          true,
        );
        if (rData is! Map || rData['ok'] != true) {
          throw P4TransportException(
            '${item.name}: ${(rData is Map ? rData['err'] : null) ?? 'failed'}',
          );
        }
        final done = end;
        final elapsedSec =
            DateTime.now().difference(t0).inMilliseconds / 1000.0;
        final kb = (done / 1024.0) / (elapsedSec < 0.1 ? 0.1 : elapsedSec);
        final pct = bytes.isNotEmpty ? ((done * 100) / bytes.length).round() : 100;
        _transferProgress =
            'Uploading ${item.name}  $pct%  (${kb.toStringAsFixed(1)} KB/s, $index of $totalCount)';
        notifyListeners();
      }

      if (_upStop) {
        throw const P4TransportException('Upload cancelled');
      }
      final rEnd = await api('/api/fs/up', {'a': 'end'}, true);
      if (rEnd is! Map || rEnd['ok'] != true) {
        throw P4TransportException(
          '${item.name}: ${(rEnd is Map ? rEnd['err'] : null) ?? 'failed'}',
        );
      }
      ended = true;
    } finally {
      if (begun && !ended && _mode == 'ble' && _ready) {
        try {
          await api('/api/fs/up', {'a': 'abort'}, true);
        } catch (_) {}
      }
    }
  }

  // ---------- System tab (lines 1455-1531, 2065-2110) ----------

  Future<void> setNewPin(String rawPin) async {
    final p = rawPin.trim();
    try {
      final d = await api('/api/settings', {'newpin': p}, true);
      if (d is Map) {
        if (d['pin'] != null) {
          _pin = d['pin'].toString();
        }
        showMsg(
          d['ok'] == true
              ? (p.isNotEmpty ? 'PIN changed' : 'PIN removed')
              : (d['err']?.toString() ?? 'Error'),
        );
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> setBoardClockFromPhone() async {
    if (!_ready) {
      showMsg('Unlock and connect first');
      return;
    }
    final unixSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      final d = await api('/api/time', {'t': unixSec}, true);
      if (d is Map) {
        if (d['ok'] == true) {
          final hasRtc = d['rtc'] == true || d['rtc'] == 1;
          showMsg(
            hasRtc
                ? 'Board clock set'
                : 'Clock set, but the RTC chip was not written',
          );
        } else {
          showMsg(d['err']?.toString() ?? 'Error');
        }
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> restartBoard() async {
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer first');
      return;
    }
    try {
      final d = await api('/api/restart', const <String, dynamic>{}, true);
      if (d is Map) {
        showMsg(d['ok'] == true ? 'Restarting...' : (d['err']?.toString() ?? 'Error'));
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> startMaintenanceMode() async {
    if (_mode != 'wifi') {
      showMsg('Maintenance mode works over WiFi only');
      return;
    }
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer first');
      return;
    }
    if (_mtGo) return;

    try {
      final d = await api('/api/maint', const <String, dynamic>{}, true);
      if (d is! Map || d['ok'] != true) {
        showMsg((d is Map ? d['err']?.toString() : null) ?? 'Failed');
        return;
      }
      _mtGo = true;
      _wifiPollTimer?.cancel();
      _geoPollTimer?.cancel();
      int secondsLeft = 20;
      final targetUrl = '$_baseUrl/';
      _maintStatus =
          'Restarting in maintenance mode... the maintenance page opens in $secondsLeft s';
      showMsg(_maintStatus);
      notifyListeners();

      _maintCountdownTimer?.cancel();
      _maintCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        secondsLeft--;
        if (secondsLeft <= 0) {
          timer.cancel();
          _maintStatus = 'Opening the maintenance page...';
          showMsg(_maintStatus);
          notifyListeners();
          launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication);
        } else {
          _maintStatus =
              'Restarting in maintenance mode... the maintenance page opens in $secondsLeft s';
          notifyListeners();
        }
      });
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> startVideoMode() async {
    if (anyTransferBusy) {
      showMsg('Finish or cancel the transfer first');
      return;
    }
    try {
      final d = await api('/api/video', const <String, dynamic>{}, true);
      if (d is! Map || d['ok'] != true) {
        showMsg((d is Map ? d['err']?.toString() : null) ?? 'Failed');
        return;
      }
      final t =
          'Restarting in video mode...${_mode == 'wifi' ? ' the video page opens in 20 s' : ' control it on the clock screen'}';
      _videoStatus = t;
      showMsg(t);
      notifyListeners();
      if (_mode == 'wifi') {
        _wifiPollTimer?.cancel();
        _geoPollTimer?.cancel();
        final targetUrl = '$_baseUrl/';
        Timer(const Duration(seconds: 20), () {
          launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication);
        });
      }
    } catch (e) {
      showMsg(e.toString());
    }
  }

  Future<void> installOtaFirmware(String fileName, Uint8List bytes) async {
    if (_mode != 'wifi' || !_ready || _transport == null) {
      showMsg('Firmware update needs an unlocked WiFi connection');
      return;
    }
    if (anyTransferBusy) {
      showMsg('Another transfer is running');
      return;
    }
    if (!RegExp(r'\.bin$', caseSensitive: false).hasMatch(fileName)) {
      showMsg('That is not a .bin file');
      return;
    }

    _fwBusy = true;
    _wifiPollTimer?.cancel();
    _geoPollTimer?.cancel();
    _otaStatus = 'Uploading 0% - do not close this page';
    notifyListeners();

    try {
      await _transport!.uploadOtaFirmware(
        fileName,
        bytes,
        _pin,
        onProgress: (loaded, total) {
          final pct = total > 0 ? ((loaded * 100) / total).round() : 0;
          _otaStatus = 'Uploading $pct% - do not close this page';
          notifyListeners();
        },
      );
      _mtGo = true;
      _otaStatus = 'Done - the clock restarts now. Reconnect after the restart.';
    } catch (e) {
      _otaStatus = e.toString();
    } finally {
      _fwBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _msgClearTimer?.cancel();
    _volDebounceTimer?.cancel();
    _briDebounceTimer?.cancel();
    _alarmVolDebounceTimer?.cancel();
    _geoPollTimer?.cancel();
    _wifiPollTimer?.cancel();
    _maintCountdownTimer?.cancel();
    _disposeTransport();
    super.dispose();
  }
}

