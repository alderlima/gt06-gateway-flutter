import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GT06Service {
  static Socket? _traccarSocket;
  static UsbPort? _usbPort;
  static StreamSubscription<Uint8List>? _usbSubscription;
  static StreamSubscription<Position>? _gpsSubscription;
  
  static int serial = 1;
  static Timer? _heartbeatTimer;
  static bool _isTraccarConnected = false;
  static bool _isUsbConnected = false;

  // Instância singleton para UI
  static final GT06Service _instance = GT06Service._internal();
  factory GT06Service() => _instance;
  GT06Service._internal();

  // Callbacks para UI
  Function(bool)? onTraccarStatusChanged;
  Function(bool)? onUsbStatusChanged;
  Function(String)? onLog;
  Function(Position)? onLocationChanged;

  void _log(String msg) {
    debugPrint(msg);
    onLog?.call(msg);
    // Envia log para o serviço de background se necessário
    FlutterBackgroundService().invoke("log", {"message": msg});
  }

  /* ================= BACKGROUND SERVICE INIT ================= */
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'gt06_tracker',
        initialNotificationTitle: 'Rastreador GT06',
        initialNotificationContent: 'Serviço de Rastreamento Ativo',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Lógica de rastreamento no Background
    final prefs = await SharedPreferences.getInstance();
    String host = prefs.getString('traccarHost') ?? '';
    int port = prefs.getInt('traccarPort') ?? 5023;
    String imei = prefs.getString('imei') ?? '';

    if (host.isEmpty || imei.isEmpty) return;

    try {
      _traccarSocket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      _isTraccarConnected = true;
      
      // Enviar Login
      final loginPacket = _buildStaticPacket(0x01, _imeiToBcd(imei));
      _traccarSocket?.add(loginPacket);

      // Heartbeat
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (_isTraccarConnected) {
          _traccarSocket?.add(_buildStaticPacket(0x13, Uint8List.fromList([0x00, 0x00, 0x00])));
        }
      });

      // GPS Stream
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: "Rastreador GT06",
            notificationText: "Rastreando localização em tempo real...",
            enableWakeLock: true,
          ),
        ),
      ).listen((Position position) {
        _sendStaticLocationPacket(position);
        service.invoke("update", {
          "latitude": position.latitude,
          "longitude": position.longitude,
        });
      });

    } catch (e) {
      service.invoke("log", {"message": "Erro Background: $e"});
    }
  }

  /* ================= PROTOCOL HELPERS (STATIC FOR BG) ================= */
  static int _crc16(Uint8List data) {
    int crc = 0xFFFF;
    for (int b in data) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0x8408;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFF;
  }

  static Uint8List _imeiToBcd(String imei) {
    String tempImei = imei;
    if (tempImei.length % 2 != 0) tempImei = "0$tempImei";
    final bytes = Uint8List(tempImei.length ~/ 2);
    for (int i = 0; i < tempImei.length; i += 2) {
      bytes[i ~/ 2] = ((tempImei.codeUnitAt(i) - 48) << 4) | (tempImei.codeUnitAt(i + 1) - 48);
    }
    return bytes;
  }

  static Uint8List _buildStaticPacket(int protocol, Uint8List payload) {
    final body = BytesBuilder();
    body.addByte(1 + payload.length + 2);
    body.addByte(protocol);
    body.add(payload);
    body.addByte((serial >> 8) & 0xFF);
    body.addByte(serial & 0xFF);
    final crc = _crc16(body.toBytes());
    final packet = BytesBuilder();
    packet.add([0x78, 0x78]);
    packet.add(body.toBytes());
    packet.addByte((crc >> 8) & 0xFF);
    packet.addByte(crc & 0xFF);
    packet.add([0x0D, 0x0A]);
    serial = (serial + 1) & 0xFFFF;
    return packet.toBytes();
  }

  static void _sendStaticLocationPacket(Position pos) {
    if (_traccarSocket == null) return;
    final payload = BytesBuilder();
    final now = DateTime.now().toUtc();
    payload.add([now.year % 100, now.month, now.day, now.hour, now.minute, now.second]);
    payload.addByte(0xCC);
    int lat = (pos.latitude * 60 * 30000).abs().toInt();
    payload.add([ (lat >> 24) & 0xFF, (lat >> 16) & 0xFF, (lat >> 8) & 0xFF, lat & 0xFF ]);
    int lon = (pos.longitude * 60 * 30000).abs().toInt();
    payload.add([ (lon >> 24) & 0xFF, (lon >> 16) & 0xFF, (lon >> 8) & 0xFF, lon & 0xFF ]);
    payload.addByte((pos.speed * 3.6).toInt());
    int status = 0x4000;
    if (pos.latitude < 0) status |= 0x0400;
    if (pos.longitude > 0) status |= 0x0800;
    int courseStatus = status | (pos.heading.toInt() & 0x3FF);
    payload.addByte((courseStatus >> 8) & 0xFF);
    payload.addByte(courseStatus & 0xFF);
    payload.add(Uint8List(9)); // Cell info
    payload.add([0x01, 0x01, 0x01]);
    _traccarSocket?.add(_buildStaticPacket(0x22, payload.toBytes()));
  }

  /* ================= USB SERIAL (UI CONTEXT) ================= */
  Future<bool> connectUsb() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      if (devices.isEmpty) return false;
      UsbDevice device = devices.first;
      UsbPort? port = await device.create();
      if (port == null) return false;
      if (!await port.open()) return false;
      port.setPortParameters(9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      _usbPort = port;
      _usbSubscription = _usbPort!.inputStream!.listen((data) {
        _log("Arduino: ${String.fromCharCodes(data).trim()}");
      });
      _isUsbConnected = true;
      onUsbStatusChanged?.call(true);
      return true;
    } catch (e) {
      _log("Erro USB: $e");
      return false;
    }
  }

  void disconnectUsb() {
    _usbSubscription?.cancel();
    _usbPort?.close();
    _usbPort = null;
    _isUsbConnected = false;
    onUsbStatusChanged?.call(false);
  }

  Future<void> sendToArduino(String cmd) async {
    if (_usbPort != null && _isUsbConnected) {
      await _usbPort!.write(Uint8List.fromList("$cmd\n".codeUnits));
      _log("Enviado USB: $cmd");
    }
  }

  /* ================= CONTROL ================= */
  Future<void> startTracking() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  Future<void> stopTracking() async {
    FlutterBackgroundService().invoke("stopService");
  }

  void dispose() {
    stopTracking();
    disconnectUsb();
    _gpsSubscription?.cancel();
    _heartbeatTimer?.cancel();
  }
}
