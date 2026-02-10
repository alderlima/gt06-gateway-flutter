import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
  int _crc16X25(Uint8List data) {
    int crc = 0xFFFF;
    for (final b in data) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0x8408;
        } else {
          crc >>= 1;
        }
      }
    }
    return (~crc) & 0xFFFF;
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
    final length = payload.length + 5;

    final body = BytesBuilder();
    body.add([length]);
    body.add([protocol]);
    body.add(payload);
    body.add([( _serial >> 8 ) & 0xFF, _serial & 0xFF]);

    final crc = _crc16X25(body.toBytes());

    final packet = BytesBuilder();
    packet.add([0x78, 0x78]);
    packet.add(body.toBytes());
    packet.add([(crc >> 8) & 0xFF, crc & 0xFF]);
    packet.add([0x0D, 0x0A]);

    _serial++;
    return packet.toBytes();
  }

  /* ================= CONNECT ================= */
  Future<void> connect() async {
    _socket = await Socket.connect(
      traccarHost,
      traccarPort,
      timeout: const Duration(seconds: 10),
    );

    _socket!.listen(
      _onData,
      onDone: _onDisconnected,
      onError: _onError,
      cancelOnError: true,
    );

    _sendLogin();
    _startHeartbeat();
  }

  /* ================= LOGIN ================= */
  void _sendLogin() {
    final imeiBytes = _imeiToBcd(imei);
    final packet = _buildPacket(0x01, imeiBytes);
    _socket!.add(packet);
  }

  /* ================= HEARTBEAT ================= */
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: heartbeatInterval),
      (_) {
        if (_socket != null) {
          final payload = Uint8List.fromList([0x00, 0x00, 0x00]);
          _socket!.add(_buildPacket(0x13, payload));
        }
      },
    );
  }

  /* ================= RECEIVE ================= */
  void _onData(Uint8List data) {
    if (data.length < 6) return;
    if (data[0] != 0x78 || data[1] != 0x78) return;

    final protocol = data[3];
    final payloadLength = data[2] - 5;

    if (payloadLength < 0) return;

    final payload = data.sublist(4, 4 + payloadLength);
    final serial = (data[4 + payloadLength] << 8) |
        data[5 + payloadLength];

    if (protocol == 0x80) {
      _handleCommand(payload, serial);
    }
  }

  /* ================= COMMAND ================= */
  Future<void> _handleCommand(Uint8List payload, int serial) async {
    final clean = payload.where((b) => b != 0).toList();
    final text = String.fromCharCodes(clean);

    if (text.contains("Relay,1")) {
      await _sendToArduino("ENGINE_STOP");
    } else if (text.contains("Relay,0")) {
      await _sendToArduino("ENGINE_RESUME");
    }

    // ACK obrigatório
    _socket?.add(_buildPacket(0x80, Uint8List(0)));
  }

  /* ================= ARDUINO ================= */
  Future<void> _sendToArduino(String cmd) async {
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
