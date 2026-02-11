import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class GT06Service {
  UsbPort? _usbPort;
  StreamSubscription<Uint8List>? _usbSubscription;
  StreamSubscription<Position>? _gpsSubscription;
  Timer? _heartbeatTimer;

  final String traccarHost;
  final int traccarPort;  // Não usado no HTTP, mantido por compatibilidade
  final String imei;
  final int heartbeatInterval;

  final Function(bool)? onTraccarStatusChanged;
  final Function(bool)? onUsbStatusChanged;
  final Function(String)? onLog;
  final Function(Position)? onLocationChanged;

  bool _isTraccarConnected = false; // Agora indica se o HTTP está respondendo
  bool _isUsbConnected = false;
  bool _gpsPermissionGranted = false;

  GT06Service({
    required this.traccarHost,
    required this.traccarPort,
    required this.imei,
    this.heartbeatInterval = 30, // Aumentado para não floodar
    this.onTraccarStatusChanged,
    this.onUsbStatusChanged,
    this.onLog,
    this.onLocationChanged,
  });

  void _log(String msg) {
    debugPrint(msg);
    onLog?.call(msg);
  }

  // ========== CONEXÃO TRACCAR VIA HTTP (OSMAND) ==========
  Future<void> connectTraccar() async {
    _isTraccarConnected = true;
    onTraccarStatusChanged?.call(true);
    _log("✅ Modo Traccar HTTP ativado (OsmAnd)");
    _startGpsTracking();
    _startHeartbeat(); // Heartbeat apenas para manter status "online"
  }

  Future<void> disconnectTraccar() async {
    _isTraccarConnected = false;
    onTraccarStatusChanged?.call(false);
    _log("⛔ Traccar desconectado");
  }

  // ========== ENVIO DE LOCALIZAÇÃO VIA HTTP ==========
  Future<void> _sendLocationPacket(Position pos) async {
    if (!_isTraccarConnected || !_gpsPermissionGranted) return;

    // Validar posição
    if (pos.latitude == 0.0 && pos.longitude == 0.0) {
      _log("⚠️ Posição inválida (0,0) - ignorando");
      return;
    }

    try {
      // Monta URL no formato OsmAnd
      final url = Uri.parse(
        "http://$traccarHost:5055/?" +
        "id=$imei&" +
        "lat=${pos.latitude.toStringAsFixed(6)}&" +
        "lon=${pos.longitude.toStringAsFixed(6)}&" +
        "speed=${(pos.speed * 3.6).toStringAsFixed(1)}&" + // km/h
        "bearing=${pos.heading.toInt()}&" +
        "altitude=${pos.altitude.toStringAsFixed(1)}&" +
        "accuracy=${pos.accuracy.toStringAsFixed(1)}&" +
        "timestamp=${DateTime.now().millisecondsSinceEpoch}&" +
        "ignition=true" // Sempre true porque o serviço está ativo
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        _log("📡 Enviado: LAT ${pos.latitude.toStringAsFixed(6)}, "
             "LON ${pos.longitude.toStringAsFixed(6)}, "
             "VEL ${(pos.speed * 3.6).toStringAsFixed(1)} km/h");
      } else {
        _log("⚠️ Traccar respondeu com código ${response.statusCode}");
      }
    } catch (e) {
      _log("❌ Erro HTTP: $e");
      // Não desconecta, tenta novamente no próximo ciclo
    }
  }

  // ========== HEARTBEAT SIMULADO (mantém conexão ativa) ==========
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: heartbeatInterval), (_) {
      if (_isTraccarConnected) {
        _log("💓 Heartbeat Traccar");
        // Opcional: enviar uma requisição de ping ou apenas manter status
      }
    });
  }

  // ========== GPS TRACKING (mesmo código anterior) ==========
  Future<void> _startGpsTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _log("❌ Permissão de GPS negada");
        _gpsPermissionGranted = false;
        return;
      }
      _gpsPermissionGranted = true;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log("⚠️ GPS desativado no dispositivo");
        return;
      }

      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        onLocationChanged?.call(position);
        _sendLocationPacket(position);
      }, onError: (e) {
        _log("❌ Erro GPS: $e");
      });

      _log("✅ Rastreamento GPS iniciado");
    } catch (e) {
      _log("❌ Erro ao iniciar GPS: $e");
    }
  }

  void _stopGpsTracking() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _log("⏹️ Rastreamento GPS parado");
  }

  // ========== USB SERIAL (mesmo código anterior) ==========
  Future<bool> connectUsb() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      if (devices.isEmpty) {
        _log("❌ Nenhum dispositivo USB encontrado");
        return false;
      }

      _log("🔌 Dispositivo encontrado: ${devices.first.deviceName}");
      UsbPort? port = await devices.first.create();
      if (port == null) {
        _log("❌ Falha ao criar porta USB");
        return false;
      }

      bool openResult = await port.open();
      if (!openResult) {
        _log("❌ Falha ao abrir porta USB");
        return false;
      }

      await port.setDTR(true);
      await port.setRTS(true);
      port.setPortParameters(9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      _usbPort = port;
      _usbSubscription = _usbPort!.inputStream!.listen((Uint8List data) {
        String msg = String.fromCharCodes(data).trim();
        if (msg.isNotEmpty) _log("Arduino: $msg");
      }, onError: (e) {
        _log("❌ Erro leitura USB: $e");
        disconnectUsb();
      });

      _isUsbConnected = true;
      onUsbStatusChanged?.call(true);
      _log("✅ USB Serial conectado (9600 bps)");
      return true;
    } catch (e) {
      _log("❌ Erro USB: $e");
      return false;
    }
  }

  void disconnectUsb() {
    _usbSubscription?.cancel();
    _usbSubscription = null;
    _usbPort?.close();
    _usbPort = null;
    _isUsbConnected = false;
    onUsbStatusChanged?.call(false);
    _log("⛔ USB Serial desconectado");
  }

  // ========== ENVIO DE COMANDOS PARA ARDUINO ==========
  Future<void> sendToArduino(String cmd) async {
    if (_usbPort != null && _isUsbConnected) {
      try {
        _log("📤 Enviando USB: $cmd");
        await _usbPort!.write(Uint8List.fromList("$cmd\n".codeUnits));
      } catch (e) {
        _log("❌ Erro envio USB: $e");
        disconnectUsb();
      }
    } else {
      _log("⚠️ USB não conectado. Comando ignorado.");
    }
  }

  // ========== DISPOSE ==========
  void dispose() {
    _log("🛑 Dispositivo GT06Service descartado");
    _heartbeatTimer?.cancel();
    _stopGpsTracking();
    disconnectUsb();
    _isTraccarConnected = false;
    onTraccarStatusChanged?.call(false);
  }
}