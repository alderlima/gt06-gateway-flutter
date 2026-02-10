import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class GT06Service {
  Socket? _socket;
  int _serial = 1;
  Timer? _heartbeatTimer;

  String traccarHost;
  int traccarPort;
  String arduinoHost;
  int arduinoPort;
  String imei;
  int heartbeatInterval;

  GT06Service({
    required this.traccarHost,
    required this.traccarPort,
    required this.arduinoHost,
    required this.arduinoPort,
    required this.imei,
    this.heartbeatInterval = 10,
  });

  // ================= CRC16 X25 =================
  int crc16X25(Uint8List data) {
    int crc = 0xFFFF;
    for (var b in data) {
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

  // ================= PACKET =================
  Uint8List buildPacket(int protocol, Uint8List payload) {
    int length = payload.length + 5;

    final body = BytesBuilder();
    body.add([length]);
    body.add([protocol]);
    body.add(payload);
    body.addByte((_serial >> 8) & 0xFF);
    body.addByte(_serial & 0xFF);

    final crc = crc16X25(body.toBytes());

    final packet = BytesBuilder();
    packet.add([0x78, 0x78]);
    packet.add(body.toBytes());
    packet.addByte((crc >> 8) & 0xFF);
    packet.addByte(crc & 0xFF);
    packet.add([0x0D, 0x0A]);

    _serial++;
    return packet.toBytes();
  }

  // ================= CONNECT =================
  Future<void> connect() async {
    _socket = await Socket.connect(traccarHost, traccarPort);
    _socket!.listen(_onData);
    sendLogin();
    _startHeartbeat();
    print("[GT06] Conectado ao Traccar");
  }

  // ================= LOGIN =================
  void sendLogin() {
    final imeiBytes = Uint8List.fromList(
      List<int>.generate(imei.length ~/ 2, (i) {
        return int.parse(imei.substring(i * 2, i * 2 + 2));
      }),
    );
    _socket!.add(buildPacket(0x01, imeiBytes));
    print("[GT06] Login enviado");
  }

  // ================= HEARTBEAT =================
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer =
        Timer.periodic(Duration(seconds: heartbeatInterval), (_) {
      final payload = Uint8List.fromList([0x00, 0x00, 0x00]);
      _socket!.add(buildPacket(0x13, payload));
      print("[GT06] Heartbeat");
    });
  }

  // ================= RECEIVE =================
  void _onData(Uint8List data) {
    if (data.length < 5) return;
    if (data[0] != 0x78 || data[1] != 0x78) return;

    final protocol = data[3];
    final payloadLen = data[2] - 5;
    final payload = data.sublist(4, 4 + payloadLen);
    final serial = (data[4 + payloadLen] << 8) | data[5 + payloadLen];

    if (protocol == 0x80) {
      _handleCommand(payload, serial);
    }
  }

  // ================= COMMAND =================
  void _handleCommand(Uint8List payload, int serial) async {
    final text = String.fromCharCodes(payload.where((b) => b != 0));

    if (text.contains("Relay,1")) {
      await _sendToArduino("ENGINE_STOP");
    } else if (text.contains("Relay,0")) {
      await _sendToArduino("ENGINE_RESUME");
    }

    // ACK
    _socket!.add(buildPacket(0x80, Uint8List(0)));
    print("[GT06] ACK enviado");
  }

  // ================= ARDUINO =================
  Future<void> _sendToArduino(String cmd) async {
    try {
      final s = await Socket.connect(arduinoHost, arduinoPort);
      s.write("$cmd\n");
      await s.flush();
      await s.close();
      print("[ARDUINO] $cmd");
    } catch (e) {
      print("[ARDUINO ERROR] $e");
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _socket?.close();
  }
}
