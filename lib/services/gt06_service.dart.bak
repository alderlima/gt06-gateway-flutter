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

  // CRC16 X25
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

  // IMEI → BCD
  Uint8List _imeiToBcd(String imei) {
    String tempImei = imei;
    if (tempImei.length % 2 != 0) tempImei = "0$tempImei";
    final bytes = Uint8List(tempImei.length ~/ 2);
    for (int i = 0; i < tempImei.length; i += 2) {
      bytes[i ~/ 2] = ((tempImei.codeUnitAt(i) - 48) << 4) | (tempImei.codeUnitAt(i + 1) - 48);
    }
    return bytes;
  }

  // Construtor de pacotes GT06
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

  // Conexão Traccar
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

  // GPS Tracking
  Future<void> _startGpsTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
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

  // Envio do pacote de localização (protocolo 0x22)
  void _sendLocationPacket(Position pos) {
    if (!_isTraccarConnected || !_gpsPermissionGranted) return;

    // Validar posição - ignorar se for zero (posição inválida)
    if (pos.latitude == 0.0 && pos.longitude == 0.0) {
      _log("Posição inválida (0,0) - ignorando");
      return;
    }

    try {
      final payload = BytesBuilder();
      final now = DateTime.now().toUtc();

      // Data/Hora (6 bytes)
      payload.addByte(now.year % 100);
      payload.addByte(now.month);
      payload.addByte(now.day);
      payload.addByte(now.hour);
      payload.addByte(now.minute);
      payload.addByte(now.second);

      // Satélites (1 byte) - 0xCC = 12 satélites, comprimento 12
      payload.addByte(0xCC);

      // Latitude (4 bytes) - valor absoluto em graus * 60 * 30000
      int lat = (pos.latitude * 1800000).abs().toInt();
      payload.addByte((lat >> 24) & 0xFF);
      payload.addByte((lat >> 16) & 0xFF);
      payload.addByte((lat >> 8) & 0xFF);
      payload.addByte(lat & 0xFF);

      // Longitude (4 bytes)
      int lon = (pos.longitude * 1800000).abs().toInt();
      payload.addByte((lon >> 24) & 0xFF);
      payload.addByte((lon >> 16) & 0xFF);
      payload.addByte((lon >> 8) & 0xFF);
      payload.addByte(lon & 0xFF);

      // Velocidade (1 byte) - km/h
      int speedKph = (pos.speed * 3.6).round().clamp(0, 255);
      payload.addByte(speedKph);

      // Curso e Status (2 bytes)
      int course = (pos.heading % 360).toInt() & 0x3FF; // 0-359, máximo 1023
      int status = 0xC000; // GPS Online, Normal

      if (pos.latitude >= 0) status |= 0x1000; // Norte
      if (pos.longitude >= 0) status |= 0x2000; // Leste

      int courseStatus = status | course;
      payload.addByte((courseStatus >> 8) & 0xFF);
      payload.addByte(courseStatus & 0xFF);

      // LBS Data (9 bytes dummy)
      payload.add(Uint8List(9));

      // ACC, Upload Mode, Real-time
      payload.addByte(0x01); // ACC ON
      payload.addByte(0x01); // Upload mode
      payload.addByte(0x01); // Real-time

      final packet = _buildPacket(0x22, payload.toBytes());
      _traccarSocket?.add(packet);
      
      // Log detalhado para depuração
      _log("Enviado: LAT ${pos.latitude.toStringAsFixed(6)} (${pos.latitude >= 0 ? 'N' : 'S'}), "
           "LON ${pos.longitude.toStringAsFixed(6)} (${pos.longitude >= 0 ? 'E' : 'W'}), "
           "SPD $speedKph km/h, CURSO ${pos.heading.toInt()}°, "
           "VALORES: latInt=$lat, lonInt=$lon, status=${status.toRadixString(16)}");
    } catch (e) {
      _log("Erro ao enviar pacote GPS: $e");
    }
  }

  // USB Serial
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
      port.setPortParameters(9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      _usbPort = port;
      _usbSubscription = _usbPort!.inputStream!.listen((Uint8List data) {
        String msg = String.fromCharCodes(data).trim();
        if (msg.isNotEmpty) _log("Arduino: $msg");
      }, onError: (e) {
        _log("Erro leitura USB: $e");
        disconnectUsb();
      });

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

  // Login
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

  // Heartbeat
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

  // Processamento de dados recebidos do Traccar
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
          final serial = (data[index + 4 + payloadLength] << 8) | data[index + 5 + payloadLength];
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
    } else if (text.contains("Relay,0")) {
      await sendToArduino("ENGINE_RESUME");
    }

    try {
      _traccarSocket?.add(_buildPacket(0x80, Uint8List(0)));
    } catch (e) {
      _log("Erro ao responder comando: $e");
    }
  }

  // Envio de comandos para Arduino via USB
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

  void dispose() {
    _log("Dispositivo GT06Service descartado");
    _heartbeatTimer?.cancel();
    _stopGpsTracking();
    _traccarSocket?.destroy();
    disconnectUsb();
    _isTraccarConnected = false;
  }
}