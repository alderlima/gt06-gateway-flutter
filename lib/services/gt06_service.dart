import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class GT06Service {
  Socket? _socket;
  int _serial = 1;
  Timer? _heartbeatTimer;

  final String traccarHost;
  final int traccarPort;
  final String arduinoHost;
  final int arduinoPort;
  final String imei;
  final int heartbeatInterval;

  GT06Service({
    required this.traccarHost,
    required this.traccarPort,
    required this.arduinoHost,
    required this.arduinoPort,
    required this.imei,
    this.heartbeatInterval = 10,
  });

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
    if (imei.length % 2 != 0) {
      imei = "0$imei";
    }

    final bytes = Uint8List(imei.length ~/ 2);
    for (int i = 0; i < imei.length; i += 2) {
      bytes[i ~/ 2] =
          ((imei.codeUnitAt(i) - 48) << 4) |
          (imei.codeUnitAt(i + 1) - 48);
    }
    return bytes;
  }

  /* ================= PACKET BUILDER ================= */
  Uint8List _buildPacket(int protocol, Uint8List payload) {
    final body = BytesBuilder();
    // Protocol + Payload + Serial (2 bytes)
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

  /* ================= CONNECT ================= */
  Future<void> connect() async {
    try {
      _socket = await Socket.connect(
        traccarHost,
        traccarPort,
        timeout: const Duration(seconds: 10),
      );

      _socket!.listen(
        _onData,
        onDone: _onDisconnected,
        onError: _onError,
        cancelOnError: false, // Não cancelar para permitir reconexão manual ou log
      );

      _sendLogin();
      _startHeartbeat();
    } catch (e) {
      debugPrint("Erro na conexão Socket: $e");
      rethrow;
    }
  }

  /* ================= LOGIN ================= */
  void _sendLogin() {
    try {
      final imeiBytes = _imeiToBcd(imei);
      final packet = _buildPacket(0x01, imeiBytes);
      _socket?.add(packet);
    } catch (e) {
      debugPrint("Erro ao enviar login: $e");
    }
  }

  /* ================= HEARTBEAT ================= */
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatInterval),
      (_) {
        try {
          if (_socket != null) {
            final payload = Uint8List.fromList([0x00, 0x00, 0x00]);
            _socket?.add(_buildPacket(0x13, payload));
          }
        } catch (e) {
          debugPrint("Erro no heartbeat: $e");
        }
      },
    );
  }

  /* ================= RECEIVE ================= */
  void _onData(Uint8List data) {
    // Pacote mínimo GT06: 0x78 0x78 [Length] [Protocol] [SerialH] [SerialL] [CRC H] [CRC L] 0x0D 0x0A
    // Total mínimo: 10 bytes
    if (data.length < 10) return;
    
    int index = 0;
    while (index < data.length - 1) {
      if (data[index] == 0x78 && data[index + 1] == 0x78) {
        if (index + 2 >= data.length) break;
        
        final length = data[index + 2];
        final totalPacketLength = length + 5; // 2 start + 1 length + length + 2 stop
        
        if (index + totalPacketLength > data.length) break;
        
        final protocol = data[index + 3];
        // O payload começa em index + 4 e termina antes do serial (2 bytes) e CRC (2 bytes)
        // length = 1 (protocol) + payload + 2 (serial)
        final payloadLength = length - 3; 
        
        if (payloadLength >= 0) {
          final payload = data.sublist(index + 4, index + 4 + payloadLength);
          final serial = (data[index + 4 + payloadLength] << 8) | data[index + 5 + payloadLength];
          
          if (protocol == 0x80 || protocol == 0x01 || protocol == 0x13) {
            _handleResponse(protocol, payload, serial);
          }
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
      debugPrint("Login bem sucedido");
    } else if (protocol == 0x13) {
      debugPrint("Heartbeat OK");
    }
  }

  /* ================= COMMAND ================= */
  Future<void> _handleCommand(Uint8List payload, int serial) async {
    final clean = payload.where((b) => b != 0).toList();
    final text = String.fromCharCodes(clean);

    if (text.contains("Relay,1")) {
      await sendToArduino("ENGINE_STOP");
    } else if (text.contains("Relay,0")) {
      await sendToArduino("ENGINE_RESUME");
    }

    // ACK obrigatório
    _socket?.add(_buildPacket(0x80, Uint8List(0)));
  }

  /* ================= ARDUINO ================= */
  Future<void> sendToArduino(String cmd) async {
    try {
      final s = await Socket.connect(
        arduinoHost,
        arduinoPort,
        timeout: const Duration(seconds: 5),
      );
      s.write("$cmd\n");
      await s.flush();
      await s.close();
    } catch (_) {
      // nunca crasha o app
    }
  }

  /* ================= ERROR / DISCONNECT ================= */
  void _onError(error) {
    dispose();
  }

  void _onDisconnected() {
    dispose();
  }

  /* ================= CLEANUP ================= */
  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket?.destroy();
    _socket = null;
  }
}
