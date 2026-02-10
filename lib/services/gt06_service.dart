import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class GT06Service {
  Socket? _traccarSocket;
  Socket? _arduinoSocket;
  int _serial = 1;
  Timer? _heartbeatTimer;
  Timer? _arduinoReconnectTimer;

  final String traccarHost;
  final int traccarPort;
  final String arduinoHost;
  final int arduinoPort;
  final String imei;
  final int heartbeatInterval;

  // Callbacks para atualizar a UI
  final Function(bool)? onTraccarStatusChanged;
  final Function(bool)? onArduinoStatusChanged;
  final Function(String)? onLog;

  bool _isTraccarConnected = false;
  bool _isArduinoConnected = false;

  GT06Service({
    required this.traccarHost,
    required this.traccarPort,
    required this.arduinoHost,
    required this.arduinoPort,
    required this.imei,
    this.heartbeatInterval = 10,
    this.onTraccarStatusChanged,
    this.onArduinoStatusChanged,
    this.onLog,
  });

  void _log(String msg) {
    debugPrint(msg);
    onLog?.call(msg);
  }

  /* ================= CRC16 X25 ================= */
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

  /* ================= IMEI → BCD ================= */
  Uint8List _imeiToBcd(String imei) {
    String tempImei = imei;
    if (tempImei.length % 2 != 0) {
      tempImei = "0$tempImei";
    }

    final bytes = Uint8List(tempImei.length ~/ 2);
    for (int i = 0; i < tempImei.length; i += 2) {
      bytes[i ~/ 2] =
          ((tempImei.codeUnitAt(i) - 48) << 4) |
          (tempImei.codeUnitAt(i + 1) - 48);
    }
    return bytes;
  }

  /* ================= PACKET BUILDER ================= */
  Uint8List _buildPacket(int protocol, Uint8List payload) {
    final body = BytesBuilder();
    final length = 1 + payload.length + 2;
    body.addByte(length);
    body.addByte(protocol);
    body.add(payload);
    body.addByte((_serial >> 8) & 0xFF);
    body.addByte(_serial & 0xFF);

    final crc = _crc16(body.toBytes());

    final packet = BytesBuilder();
    packet.addByte(0x78);
    packet.addByte(0x78);
    packet.add(body.toBytes());
    packet.addByte((crc >> 8) & 0xFF);
    packet.addByte(crc & 0xFF);
    packet.addByte(0x0D);
    packet.addByte(0x0A);

    _serial = (_serial + 1) & 0xFFFF;
    return packet.toBytes();
  }

  /* ================= CONNECT ALL ================= */
  Future<void> connect() async {
    await connectTraccar();
    await connectArduino();
  }

  /* ================= TRACCAR CONNECTION ================= */
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
      _log("Conectado ao Traccar com sucesso!");
    } catch (e) {
      _isTraccarConnected = false;
      onTraccarStatusChanged?.call(false);
      _log("Erro na conexão Traccar: $e");
      rethrow;
    }
  }

  /* ================= ARDUINO CONNECTION ================= */
  Future<void> connectArduino() async {
    try {
      _log("Conectando ao Arduino: $arduinoHost:$arduinoPort");
      _arduinoSocket = await Socket.connect(
        arduinoHost,
        arduinoPort,
        timeout: const Duration(seconds: 10),
      );

      _arduinoSocket!.listen(
        (data) => _log("Arduino: ${String.fromCharCodes(data).trim()}"),
        onDone: () => _onArduinoDisconnected(),
        onError: (e) => _onArduinoError(e),
        cancelOnError: false,
      );

      _isArduinoConnected = true;
      onArduinoStatusChanged?.call(true);
      _arduinoReconnectTimer?.cancel();
      _log("Conectado ao Arduino com sucesso!");
    } catch (e) {
      _isArduinoConnected = false;
      onArduinoStatusChanged?.call(false);
      _log("Erro na conexão Arduino: $e");
      _scheduleArduinoReconnect();
    }
  }

  void _scheduleArduinoReconnect() {
    _arduinoReconnectTimer?.cancel();
    _arduinoReconnectTimer = Timer(const Duration(seconds: 10), () {
      if (!_isArduinoConnected) {
        connectArduino();
      }
    });
  }

  /* ================= LOGIN ================= */
  void _sendLogin() {
    try {
      final imeiBytes = _imeiToBcd(imei);
      final packet = _buildPacket(0x01, imeiBytes);
      _traccarSocket?.add(packet);
    } catch (e) {
      _log("Erro ao enviar login: $e");
    }
  }

  /* ================= HEARTBEAT ================= */
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatInterval),
      (_) {
        try {
          if (_traccarSocket != null && _isTraccarConnected) {
            final payload = Uint8List.fromList([0x00, 0x00, 0x00]);
            _traccarSocket?.add(_buildPacket(0x13, payload));
          }
        } catch (e) {
          _log("Erro no heartbeat: $e");
        }
      },
    );
  }

  /* ================= RECEIVE TRACCAR ================= */
  void _onTraccarData(Uint8List data) {
    if (data.length < 10) return;
    
    int index = 0;
    while (index < data.length - 1) {
      if (data[index] == 0x78 && data[index + 1] == 0x78) {
        if (index + 2 >= data.length) break;
        
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
      _log("Traccar: Login aceito");
    } else if (protocol == 0x13) {
      // Heartbeat ACK
    }
  }

  /* ================= COMMAND HANDLING ================= */
  Future<void> _handleCommand(Uint8List payload, int serial) async {
    final clean = payload.where((b) => b != 0).toList();
    final text = String.fromCharCodes(clean);
    _log("Comando recebido do Traccar: $text");

    if (text.contains("Relay,1")) {
      await sendToArduino("ENGINE_STOP");
    } else if (text.contains("Relay,0")) {
      await sendToArduino("ENGINE_RESUME");
    }

    // Enviar ACK para o Traccar
    _traccarSocket?.add(_buildPacket(0x80, Uint8List(0)));
  }

  /* ================= SEND TO ARDUINO ================= */
  Future<void> sendToArduino(String cmd) async {
    if (_arduinoSocket != null && _isArduinoConnected) {
      try {
        _log("Enviando para Arduino: $cmd");
        _arduinoSocket!.write("$cmd\n");
        await _arduinoSocket!.flush();
      } catch (e) {
        _log("Erro ao enviar para Arduino: $e");
        _onArduinoDisconnected();
      }
    } else {
      _log("Arduino desconectado. Tentando reconectar e enviar...");
      await connectArduino();
      if (_isArduinoConnected) {
        sendToArduino(cmd);
      }
    }
  }

  /* ================= STATUS HANDLERS ================= */
  void _onTraccarError(error) {
    _log("Erro no socket Traccar: $error");
    _onTraccarDisconnected();
  }

  void _onTraccarDisconnected() {
    _isTraccarConnected = false;
    onTraccarStatusChanged?.call(false);
    _log("Traccar desconectado");
  }

  void _onArduinoError(error) {
    _log("Erro no socket Arduino: $error");
    _onArduinoDisconnected();
  }

  void _onArduinoDisconnected() {
    _isArduinoConnected = false;
    onArduinoStatusChanged?.call(false);
    _log("Arduino desconectado");
    _scheduleArduinoReconnect();
  }

  /* ================= CLEANUP ================= */
  void dispose() {
    _heartbeatTimer?.cancel();
    _arduinoReconnectTimer?.cancel();
    _traccarSocket?.destroy();
    _arduinoSocket?.destroy();
    _traccarSocket = null;
    _arduinoSocket = null;
    _isTraccarConnected = false;
    _isArduinoConnected = false;
  }
}
