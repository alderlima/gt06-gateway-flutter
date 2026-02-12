import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:geolocator/geolocator.dart';

class GT06Service {
  Socket? _traccarSocket;
  UsbPort? _usbPort;
  StreamSubscription<Uint8List>? _usbSubscription;
  StreamSubscription<Position>? _gpsSubscription;

  int serial = 1;
  Timer? _heartbeatTimer;

  final String traccarHost;
  final int traccarPort;
  final String imei;
  final int heartbeatInterval;

  final Function(bool)? onTraccarStatusChanged;
  final Function(bool)? onUsbStatusChanged;
  final Function(String)? onLog;
  final Function(Position)? onLocationChanged;

  bool _isTraccarConnected = false;
  bool _isUsbConnected = false;
  bool _gpsPermissionGranted = false;

  // Estado da ignição (pode ser controlado externamente futuramente)
  bool _ignition = true; // assumimos ligado durante rastreamento

  GT06Service({
    required this.traccarHost,
    required this.traccarPort,
    required this.imei,
    this.heartbeatInterval = 10,
    this.onTraccarStatusChanged,
    this.onUsbStatusChanged,
    this.onLog,
    this.onLocationChanged,
  });

  void _log(String msg) {
    debugPrint(msg);
    onLog?.call(msg);
  }

  // ================= CRC16 X25 =================
  int _crc16(Uint8List data) {
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

  // ================= IMEI → BCD =================
  Uint8List _imeiToBcd(String imei) {
    String tempImei = imei;
    if (tempImei.length % 2 != 0) tempImei = "0$tempImei";
    final bytes = Uint8List(tempImei.length ~/ 2);
    for (int i = 0; i < tempImei.length; i += 2) {
      bytes[i ~/ 2] = ((tempImei.codeUnitAt(i) - 48) << 4) |
          (tempImei.codeUnitAt(i + 1) - 48);
    }
    return bytes;
  }

  // ================= PACKET BUILDER =================
  Uint8List _buildPacket(int protocol, Uint8List payload) {
    final body = BytesBuilder();
    final length = 1 + payload.length + 2;
    body.addByte(length);
    body.addByte(protocol);
    body.add(payload);
    body.addByte((serial >> 8) & 0xFF);
    body.addByte(serial & 0xFF);

    final crc = _crc16(body.toBytes());

    final packet = BytesBuilder();
    packet.addByte(0x78);
    packet.addByte(0x78);
    packet.add(body.toBytes());
    packet.addByte((crc >> 8) & 0xFF);
    packet.addByte(crc & 0xFF);
    packet.addByte(0x0D);
    packet.addByte(0x0A);

    serial = (serial + 1) & 0xFFFF;
    return packet.toBytes();
  }

  // ================= TRACCAR CONNECTION =================
  Future<void> connectTraccar() async {
    try {
      _log("Conectando ao Traccar: $traccarHost:$traccarPort");
      _traccarSocket = await Socket.connect(
        traccarHost,
        traccarPort,
        timeout: const Duration(seconds: 10),
      );

      _traccarSocket!.listen(
        _onTraccarData,
        onDone: () => _onTraccarDisconnected(),
        onError: (e) => _onTraccarError(e),
        cancelOnError: false,
      );

      _isTraccarConnected = true;
      onTraccarStatusChanged?.call(true);
      _sendLogin();
      _startHeartbeat();
      _startGpsTracking();
      _log("Conectado ao Traccar!");
    } catch (e) {
      _isTraccarConnected = false;
      onTraccarStatusChanged?.call(false);
      _log("Erro Traccar: $e");
      rethrow;
    }
  }

  void _onTraccarDisconnected() {
    _isTraccarConnected = false;
    onTraccarStatusChanged?.call(false);
    _heartbeatTimer?.cancel();
    _stopGpsTracking();
    _log("Traccar desconectado");
  }

  void _onTraccarError(dynamic e) {
    _log("Erro Socket Traccar: $e");
    _onTraccarDisconnected();
  }

  // ================= GPS TRACKING (GT06 0x22) =================
  Future<void> _startGpsTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _log("Permissão de GPS não concedida");
        _gpsPermissionGranted = false;
        return;
      }
      _gpsPermissionGranted = true;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _log("GPS desativado no dispositivo");
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
        _log("Erro GPS: $e");
      });

      _log("Rastreamento GPS iniciado");
    } catch (e) {
      _log("Erro ao iniciar GPS: $e");
    }
  }

  void _stopGpsTracking() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _log("Rastreamento GPS parado");
  }

  // ================= ENVIO DO PACOTE DE LOCALIZAÇÃO (0x22) =================
  void _sendLocationPacket(Position pos) {
    if (!_isTraccarConnected || !_gpsPermissionGranted) return;

    // --- VALIDAÇÕES RIGOROSAS CONTRA POSIÇÃO INVÁLIDA ---
    if (pos.latitude == 0.0 && pos.longitude == 0.0) {
      _log("⚠️ Posição inválida (0,0) – ignorando");
      return;
    }
    if (pos.latitude < -90 || pos.latitude > 90) {
      _log("❌ Latitude fora do intervalo: ${pos.latitude}");
      return;
    }
    if (pos.longitude < -180 || pos.longitude > 180) {
      _log("❌ Longitude fora do intervalo: ${pos.longitude}");
      return;
    }

    try {
      final payload = BytesBuilder();
      final now = DateTime.now().toUtc();

      // 1. Data/Hora (6 bytes: YY MM DD HH MM SS)
      payload.addByte(now.year % 100);
      payload.addByte(now.month);
      payload.addByte(now.day);
      payload.addByte(now.hour);
      payload.addByte(now.minute);
      payload.addByte(now.second);

      // 2. Satélites (1 byte) – 0xCC = 12 satélites, info length = 12
      payload.addByte(0xCC);

      // --- CONVERSÃO PRECISA (round em vez de toInt) ---
      int latInt = (pos.latitude * 1800000).round();
      int lonInt = (pos.longitude * 1800000).round();
      int latAbs = latInt.abs();
      int lonAbs = lonInt.abs();

      // LOG DETALHADO PARA DEPURAÇÃO
      _log("📍 POSIÇÃO REAL: ${pos.latitude.toStringAsFixed(6)} "
          "(${pos.latitude >= 0 ? 'N' : 'S'}), "
          "${pos.longitude.toStringAsFixed(6)} (${pos.longitude >= 0 ? 'E' : 'W'})");
      _log("🔢 CONVERTIDO: latInt=$latInt, lonInt=$lonInt");
      _log("📦 HEX LAT: ${latAbs.toRadixString(16).padLeft(8, '0')}, "
          "HEX LON: ${lonAbs.toRadixString(16).padLeft(8, '0')}");

      // 3. Latitude (4 bytes)
      payload.addByte((latAbs >> 24) & 0xFF);
      payload.addByte((latAbs >> 16) & 0xFF);
      payload.addByte((latAbs >> 8) & 0xFF);
      payload.addByte(latAbs & 0xFF);

      // 4. Longitude (4 bytes)
      payload.addByte((lonAbs >> 24) & 0xFF);
      payload.addByte((lonAbs >> 16) & 0xFF);
      payload.addByte((lonAbs >> 8) & 0xFF);
      payload.addByte(lonAbs & 0xFF);

      // 5. Velocidade (1 byte) – km/h, clamp entre 0-255
      int speedKph = (pos.speed * 3.6).round().clamp(0, 255);
      payload.addByte(speedKph);

      // ================= CORREÇÃO CRÍTICA DOS BITS DE HEMISFÉRIO =================
      // Conforme Gt06ProtocolDecoder.java:
      // - bit 10 (0x0400): latitude sign (1 = North, 0 = South)
      // - bit 11 (0x0800): longitude sign (1 = West, 0 = East)  <-- OESTE = 1
      // - bit 12 (0x1000): GPS fix valid (1 = válido)
      // - bit 14 (0x4000): ignition info present
      // - bit 15 (0x8000): ignition status (se bit14 = 1)
      // - bits 0-9: course (0-1023)

      int course = (pos.heading % 360).toInt() & 0x3FF; // 0-359, máximo 1023

      int status = 0;
      status |= 0x1000;                          // GPS válido (bit12)
      if (pos.latitude >= 0) status |= 0x0400;  // bit10 = 1 (Norte)
      if (pos.longitude < 0) status |= 0x0800;  // bit11 = 1 (Oeste) – importante!
      status |= 0x4000;                         // bit14 = 1 (ignition present)
      if (_ignition) status |= 0x8000;          // bit15 = estado da ignição (1 = ligada)

      status |= course;                         // bits 0-9

      int courseStatus = status;
      // ========================================================================

      payload.addByte((courseStatus >> 8) & 0xFF);
      payload.addByte(courseStatus & 0xFF);

      // 7. LBS Data (9 bytes dummy)
      payload.add(Uint8List(9));

      // 8. ACC, Upload Mode, Real-time (3 bytes)
      payload.addByte(0x01); // ACC ON
      payload.addByte(0x01); // Upload mode
      payload.addByte(0x01); // Real-time

      final packet = _buildPacket(0x22, payload.toBytes());
      _traccarSocket?.add(packet);

      _log("📤 Pacote GT06 enviado: LAT ${pos.latitude.toStringAsFixed(6)}, "
          "LON ${pos.longitude.toStringAsFixed(6)}, SPD $speedKph km/h, "
          "CRS ${pos.heading.toInt()}°, STATUS: ${status.toRadixString(16).padLeft(4, '0')} "
          "(bits: ${status.toRadixString(2).padLeft(16, '0')})");
    } catch (e) {
      _log("❌ Erro ao enviar pacote GPS: $e");
    }
  }

  // ================= USB SERIAL =================
  Future<bool> connectUsb() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      if (devices.isEmpty) {
        _log("Nenhum dispositivo USB encontrado");
        return false;
      }

      _log("Dispositivo encontrado: ${devices.first.deviceName}");
      UsbPort? port = await devices.first.create();
      if (port == null) {
        _log("Falha ao criar porta USB");
        return false;
      }

      bool openResult = await port.open();
      if (!openResult) {
        _log("Falha ao abrir porta USB");
        return false;
      }

      await port.setDTR(true);
      await port.setRTS(true);
      port.setPortParameters(
          9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      _usbPort = port;
      _usbSubscription = _usbPort!.inputStream!.listen(
        (Uint8List data) {
          String msg = String.fromCharCodes(data).trim();
          if (msg.isNotEmpty) _log("Arduino: $msg");
        },
        onError: (e) {
          _log("Erro leitura USB: $e");
          disconnectUsb();
        },
      );

      _isUsbConnected = true;
      onUsbStatusChanged?.call(true);
      _log("USB Serial conectado (9600 bps)");
      return true;
    } catch (e) {
      _log("Erro USB: $e");
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
    _log("USB Serial desconectado");
  }

  // ================= PROTOCOL LOGIC =================
  void _sendLogin() {
    try {
      final imeiBytes = _imeiToBcd(imei);
      final packet = _buildPacket(0x01, imeiBytes);
      _traccarSocket?.add(packet);
      _log("Login enviado (IMEI: $imei)");
    } catch (e) {
      _log("Erro login: $e");
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: heartbeatInterval), (_) {
      if (_isTraccarConnected) {
        try {
          final payload = Uint8List.fromList([0x00, 0x00, 0x00]);
          _traccarSocket?.add(_buildPacket(0x13, payload));
          _log("Heartbeat enviado");
        } catch (e) {
          _log("Erro heartbeat: $e");
        }
      }
    });
  }

  void _onTraccarData(Uint8List data) {
    if (data.length < 10) return;

    int index = 0;
    while (index < data.length - 1) {
      if (data[index] == 0x78 && data[index + 1] == 0x78) {
        final length = data[index + 2];
        final totalPacketLength = length + 5;
        if (index + totalPacketLength > data.length) break;
        final protocol = data[index + 3];
        final payloadLength = length - 3;
        if (payloadLength >= 0) {
          final payload = data.sublist(index + 4, index + 4 + payloadLength);
          final serial = (data[index + 4 + payloadLength] << 8) |
              data[index + 5 + payloadLength];
          _handleResponse(protocol, payload, serial);
        }
        index += totalPacketLength;
      } else {
        index++;
      }
    }
  }

  void _handleResponse(int protocol, Uint8List payload, int serial) {
    if (protocol == 0x80) {
      _handleCommand(payload, serial);
    } else if (protocol == 0x01) {
      _log("Traccar: Login OK");
    }
  }

  Future<void> _handleCommand(Uint8List payload, int serial) async {
    final text = String.fromCharCodes(payload.where((b) => b != 0));
    _log("Comando Traccar: $text");

    if (text.contains("Relay,1")) {
      await sendToArduino("ENGINE_STOP");
      _ignition = false; // desliga ignição
    } else if (text.contains("Relay,0")) {
      await sendToArduino("ENGINE_RESUME");
      _ignition = true; // liga ignição
    }

    try {
      _traccarSocket?.add(_buildPacket(0x80, Uint8List(0)));
    } catch (e) {
      _log("Erro ao responder comando: $e");
    }
  }

  // ================= ENVIO PARA ARDUINO =================
  Future<void> sendToArduino(String cmd) async {
    if (_usbPort != null && _isUsbConnected) {
      try {
        _log("Enviando USB: $cmd");
        await _usbPort!.write(Uint8List.fromList("$cmd\n".codeUnits));
      } catch (e) {
        _log("Erro envio USB: $e");
        disconnectUsb();
      }
    } else {
      _log("USB não conectado. Comando ignorado.");
    }
  }

  // ================= DISPOSE =================
  void dispose() {
    _log("Dispositivo GT06Service descartado");
    _heartbeatTimer?.cancel();
    _stopGpsTracking();
    _traccarSocket?.destroy();
    disconnectUsb();
    _isTraccarConnected = false;
  }
}