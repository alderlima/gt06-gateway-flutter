import 'dart:typed_data';
import 'dart:convert';

/// ============================================================================
/// PROTOCOLO GT06 - Implementação Cliente
/// ============================================================================
/// 
/// Protocolo Concox GT06 para rastreadores GPS
///
/// ESTRUTURA DO PACOTE:
/// [Start: 0x78 0x78] [Length: 1] [Protocol: 1] [Info: n] [Serial: 2] [CRC: 2] [Stop: 0x0D 0x0A]
///
/// Length = tamanho de (Protocol + Info + Serial)
/// CRC16 X.25 (do Length até o final do Serial)
/// ============================================================================

class GT06Protocol {
  // Start e Stop bytes
  static const List<int> START_BYTES = [0x78, 0x78];
  static const List<int> STOP_BYTES = [0x0D, 0x0A];

  // Protocol Numbers
  static const int PROTOCOL_LOGIN = 0x01;
  static const int PROTOCOL_LOCATION = 0x12;
  static const int PROTOCOL_STATUS = 0x13;  // Heartbeat
  static const int PROTOCOL_STRING = 0x15;
  static const int PROTOCOL_ALARM = 0x16;
  static const int PROTOCOL_COMMAND = 0x80;  // Server -> Client (Comando)
  static const int PROTOCOL_COMMAND_RESPONSE = 0x21;  // Client -> Server
  static const int PROTOCOL_TIME_REQUEST = 0x32;
  static const int PROTOCOL_INFO = 0x98;

  // Tipos de alarme
  static const int ALARM_NORMAL = 0x00;
  static const int ALARM_SOS = 0x01;
  static const int ALARM_POWER_CUT = 0x02;
  static const int ALARM_VIBRATION = 0x03;
  static const int ALARM_GEO_FENCE_IN = 0x04;
  static const int ALARM_GEO_FENCE_OUT = 0x05;
  static const int ALARM_OVERSPEED = 0x06;
  static const int ALARM_ACC_ON = 0x09;
  static const int ALARM_ACC_OFF = 0x0A;
  static const int ALARM_LOW_BATTERY = 0x0E;

  /// Serial number incremental
  int _serialNumber = 1;

  int get nextSerialNumber {
    final serial = _serialNumber;
    _serialNumber = (_serialNumber + 1) & 0xFFFF;
    if (_serialNumber == 0) _serialNumber = 1;
    return serial;
  }

  void resetSerial() => _serialNumber = 1;

  /// ==========================================================================
  /// CRIAÇÃO DE PACOTES - CLIENTE -> SERVIDOR
  /// ==========================================================================

  /// Cria pacote de LOGIN (0x01)
  Uint8List createLoginPacket(String imei) {
    final builder = BytesBuilder();
    
    // Start bytes
    builder.add(START_BYTES);
    
    // Content length (protocol + imei + serial = 1 + 8 + 2 = 11)
    builder.addByte(0x0B);
    
    // Protocol number
    builder.addByte(PROTOCOL_LOGIN);
    
    // IMEI em BCD (8 bytes para 15 dígitos)
    builder.add(_imeiToBCD(imei));
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Calcula checksum (XOR de tudo após start bytes)
    final packetWithoutChecksum = builder.toBytes();
    final checksum = _calculateChecksum(packetWithoutChecksum.sublist(2));
    builder.addByte(checksum);
    
    // Stop bytes
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria pacote de HEARTBEAT (0x13)
  Uint8List createHeartbeatPacket({
    bool accOn = true,
    bool gpsPositioned = true,
    int voltageLevel = 4,
    int gsmSignal = 4,
    int alarmType = 0,
  }) {
    final builder = BytesBuilder();
    
    builder.add(START_BYTES);
    builder.addByte(0x08); // Content length
    builder.addByte(PROTOCOL_STATUS);
    
    // Terminal Info
    int terminalInfo = 0x00;
    if (accOn) terminalInfo |= 0x01;
    if (gpsPositioned) terminalInfo |= 0x02;
    terminalInfo |= 0x40;
    builder.addByte(terminalInfo);
    
    builder.addByte(voltageLevel.clamp(0, 6));
    builder.addByte(gsmSignal.clamp(0, 4));
    builder.add([alarmType & 0xFF, 0x00]);
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Checksum
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria pacote de LOCATION/GPS (0x12)
  Uint8List createLocationPacket({
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    DateTime? dateTime,
    int satellites = 8,
    bool gpsValid = true,
  }) {
    dateTime ??= DateTime.now().toUtc();
    
    final builder = BytesBuilder();
    
    builder.add(START_BYTES);
    builder.addByte(0x15); // Content length
    builder.addByte(PROTOCOL_LOCATION);
    
    // Date/Time (6 bytes): YY MM DD HH MM SS
    builder.addByte(dateTime.year - 2000);
    builder.addByte(dateTime.month);
    builder.addByte(dateTime.day);
    builder.addByte(dateTime.hour);
    builder.addByte(dateTime.minute);
    builder.addByte(dateTime.second);
    
    builder.addByte(satellites);
    
    // Latitude
    final latValue = (_coordinateToGT06(latitude)).toInt();
    builder.add(_intToBytes(latValue, 4));
    
    // Longitude
    final lonValue = (_coordinateToGT06(longitude)).toInt();
    builder.add(_intToBytes(lonValue, 4));
    
    builder.addByte(speed.clamp(0, 255).toInt());
    
    // Course/Status
    int courseStatus = ((course ~/ 10) & 0x03FF);
    if (gpsValid) courseStatus |= 0x1000;
    if (latitude < 0) courseStatus |= 0x0400;
    if (longitude < 0) courseStatus |= 0x0800;
    builder.add(_intToBytes(courseStatus, 2));
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Checksum
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria pacote de ALARM (0x16)
  Uint8List createAlarmPacket({
    required int alarmType,
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    DateTime? dateTime,
  }) {
    dateTime ??= DateTime.now().toUtc();
    
    final builder = BytesBuilder();
    
    builder.add(START_BYTES);
    builder.addByte(0x19);
    builder.addByte(PROTOCOL_ALARM);
    
    // Date/Time
    builder.addByte(dateTime.year - 2000);
    builder.addByte(dateTime.month);
    builder.addByte(dateTime.day);
    builder.addByte(dateTime.hour);
    builder.addByte(dateTime.minute);
    builder.addByte(dateTime.second);
    
    builder.addByte(alarmType);
    builder.addByte(8);
    
    final latValue = (_coordinateToGT06(latitude)).toInt();
    builder.add(_intToBytes(latValue, 4));
    
    final lonValue = (_coordinateToGT06(longitude)).toInt();
    builder.add(_intToBytes(lonValue, 4));
    
    builder.addByte(speed.clamp(0, 255).toInt());
    
    int courseStatus = ((course ~/ 10) & 0x03FF) | 0x1000;
    builder.add(_intToBytes(courseStatus, 2));
    
    builder.add([0x00, 0x00, 0x00, 0x00]);
    
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria resposta de comando (0x21)
  Uint8List createCommandResponse(String responseText) {
    final textBytes = utf8.encode(responseText);
    final builder = BytesBuilder();
    
    builder.add(START_BYTES);
    builder.addByte(5 + textBytes.length);
    builder.addByte(PROTOCOL_COMMAND_RESPONSE);
    builder.addByte(0x00); // Server flag
    builder.addByte(0x01); // Command type = texto
    builder.add(_intToBytes(textBytes.length, 2));
    builder.add(textBytes);
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// ==========================================================================
  /// PARSING DE PACOTES - SERVIDOR -> CLIENTE
  /// ==========================================================================

  /// Parse de pacote recebido do servidor
  GT06ServerPacket? parseServerPacket(Uint8List data) {
    try {
      // Verifica tamanho mínimo
      if (data.length < 9) {
        print('[GT06_PROTOCOL] Pacote muito curto: ${data.length} bytes');
        return null;
      }
      
      // Procura start bytes
      int startIndex = -1;
      for (int i = 0; i < data.length - 1; i++) {
        if (data[i] == START_BYTES[0] && data[i + 1] == START_BYTES[1]) {
          startIndex = i;
          break;
        }
      }
      
      if (startIndex == -1) {
        print('[GT06_PROTOCOL] Start bytes não encontrados');
        return null;
      }
      
      if (startIndex + 3 >= data.length) {
        print('[GT06_PROTOCOL] Dados insuficientes');
        return null;
      }
      
      // Pega content length (byte após start bytes)
      int contentLength = data[startIndex + 2];
      
      // Calcula tamanho total do pacote
      // start(2) + len(1) + content(contentLength) + crc(2) + stop(2)
      int packetLength = 2 + 1 + contentLength + 2 + 2;
      
      print('[GT06_PROTOCOL] Start: $startIndex, ContentLen: $contentLength, PacketLen: $packetLength, DataLen: ${data.length}');
      
      if (startIndex + packetLength > data.length) {
        print('[GT06_PROTOCOL] Pacote incompleto');
        return null;
      }
      
      // Extrai o pacote completo
      final packet = data.sublist(startIndex, startIndex + packetLength);
      
      // Verifica stop bytes
      if (packet[packet.length - 2] != STOP_BYTES[0] || 
          packet[packet.length - 1] != STOP_BYTES[1]) {
        print('[GT06_PROTOCOL] Stop bytes inválidos');
        return null;
      }
      
      // Extrai campos
      int protocolNumber = packet[3];
      
      // Info = content sem o protocol (1 byte) e sem o serial (2 bytes)
      int infoLength = contentLength - 3;
      Uint8List info;
      if (infoLength > 0) {
        info = packet.sublist(4, 4 + infoLength);
      } else {
        info = Uint8List(0);
      }
      
      // Serial number (2 bytes antes do CRC)
      int serialIndex = 2 + contentLength - 1;
      int serialNumber = (packet[serialIndex] << 8) | packet[serialIndex + 1];
      
      // Verifica CRC (XOR simples para GT06)
      int expectedChecksum = packet[packet.length - 3];
      Uint8List contentForChecksum = packet.sublist(2, packet.length - 3);
      int calculatedChecksum = _calculateChecksum(contentForChecksum);
      
      bool checksumValid = expectedChecksum == calculatedChecksum;
      
      print('[GT06_PROTOCOL] Protocol: 0x${protocolNumber.toRadixString(16).padLeft(2, "0")}, '
            'Serial: $serialNumber, InfoLen: $infoLength, CRC: $checksumValid');
      
      return GT06ServerPacket(
        protocolNumber: protocolNumber,
        content: info,
        serialNumber: serialNumber,
        checksumValid: checksumValid,
        rawData: packet,
      );
      
    } catch (e, stackTrace) {
      print('[GT06_PROTOCOL] Erro no parse: $e');
      print('[GT06_PROTOCOL] Stack: $stackTrace');
      return null;
    }
  }

  /// Parse de comando do servidor (0x80) - ESTILO PYTHON
  /// 
  /// Implementação igual ao exemplo Python:
  /// 1. Remove bytes nulos (\x00)
  /// 2. Decodifica como ASCII
  /// 3. Procura por "Relay" no texto
  GT06Command? parseCommand(GT06ServerPacket packet) {
    if (packet.protocolNumber != PROTOCOL_COMMAND) {
      print('[GT06_PROTOCOL] Não é comando (protocolo: ${packet.protocolNumber})');
      return null;
    }
    
    try {
      print('[GT06_PROTOCOL] =========== DEBUG PARSE COMMAND ===========');
      print('[GT06_PROTOCOL] Bytes crus: ${bytesToHex(packet.content)}');
      
      // Mostra cada byte e seu caractere
      print('[GT06_PROTOCOL] Análise byte a byte:');
      for (int i = 0; i < packet.content.length; i++) {
        int byte = packet.content[i];
        String char = (byte >= 32 && byte <= 126) ? String.fromCharCode(byte) : '.';
        print('[GT06_PROTOCOL]   [$i]: 0x${byte.toRadixString(16).padLeft(2, '0')} -> $char');
      }
      
      // Remove bytes nulos
      final cleanBytes = <int>[];
      for (int byte in packet.content) {
        if (byte != 0) cleanBytes.add(byte);
      }
      
      print('[GT06_PROTOCOL] Bytes limpos: ${bytesToHex(Uint8List.fromList(cleanBytes))}');
      
      if (cleanBytes.isEmpty) {
        print('[GT06_PROTOCOL] Payload vazio');
        return null;
      }
      
      // Tenta decodificar de várias formas
      String text = String.fromCharCodes(cleanBytes);
      text = text.trim();
      
      print('[GT06_PROTOCOL] Texto decodificado: "$text"');
      print('[GT06_PROTOCOL] Comprimento: ${text.length}');
      
      // Verifica todas as possibilidades
      String upper = text.toUpperCase();
      print('[GT06_PROTOCOL] Upper: "$upper"');
      print('[GT06_PROTOCOL] Contém "RELAY"? ${upper.contains("RELAY")}');
      print('[GT06_PROTOCOL] Contém ",1"? ${upper.contains(",1")}');
      print('[GT06_PROTOCOL] Contém ",0"? ${upper.contains(",0")}');
      print('[GT06_PROTOCOL] ==========================================');
      
      // Detecta o comando
      String commandType = 'UNKNOWN';
      
      if (upper.contains("RELAY")) {
        if (upper.contains(",1") || upper.contains("1#")) {
          commandType = 'ENGINE_STOP';
          print('[GT06_PROTOCOL] Detectado: ENGINE_STOP');
        } else if (upper.contains(",0") || upper.contains("0#")) {
          commandType = 'ENGINE_RESUME';
          print('[GT06_PROTOCOL] Detectado: ENGINE_RESUME');
        }
      } else if (upper.contains("STOP") || upper.contains("DESLIGAR") || upper.contains("BLOQUEAR")) {
        commandType = 'ENGINE_STOP';
      } else if (upper.contains("START") || upper.contains("LIGAR") || upper.contains("DESBLOQUEAR")) {
        commandType = 'ENGINE_RESUME';
      }
      
      if (commandType != 'UNKNOWN') {
        return GT06Command(
          rawCommand: text,
          commandType: commandType,
          serialNumber: packet.serialNumber,
        );
      }
      
      print('[GT06_PROTOCOL] Comando não reconhecido');
      return null;
      
    } catch (e, stackTrace) {
      print('[GT06_PROTOCOL] Erro no parse: $e');
      print('[GT06_PROTOCOL] Stack: $stackTrace');
      return null;
    }
  }

  /// ==========================================================================
  /// HELPERS
  /// ==========================================================================

  /// Converte IMEI para BCD (8 bytes para 15 dígitos)
  Uint8List _imeiToBCD(String imei) {
    final cleanImei = imei.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (cleanImei.length != 15) {
      throw Exception('IMEI deve ter 15 dígitos');
    }
    
    final padded = '0$cleanImei';
    
    final bytes = <int>[];
    
    for (int i = 0; i < padded.length; i += 2) {
      final high = padded.codeUnitAt(i) - 0x30;
      final low = padded.codeUnitAt(i + 1) - 0x30;
      bytes.add((high << 4) | low);
    }
    
    return Uint8List.fromList(bytes);
  }

  /// Converte coordenada para formato GT06
  double _coordinateToGT06(double coordinate) {
    return coordinate.abs() * 30000.0 * 60.0;
  }

  /// Converte inteiro para bytes (big-endian)
  Uint8List _intToBytes(int value, int length) {
    final bytes = <int>[];
    for (int i = length - 1; i >= 0; i--) {
      bytes.add((value >> (i * 8)) & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }

  /// Calcula checksum (XOR de todos os bytes)
  int _calculateChecksum(Uint8List data) {
    int checksum = 0;
    for (int byte in data) {
      checksum ^= byte;
    }
    return checksum;
  }

  /// Gera IMEI aleatório válido
  static String generateRandomIMEI() {
    final buffer = StringBuffer();
    
    buffer.write('35963208');
    
    for (int i = 0; i < 6; i++) {
      buffer.write((DateTime.now().millisecond + i) % 10);
    }
    
    String imei14 = buffer.toString();
    int sum = 0;
    bool doubleDigit = false;
    
    for (int i = imei14.length - 1; i >= 0; i--) {
      int digit = imei14[i].codeUnitAt(0) - 0x30;
      if (doubleDigit) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      doubleDigit = !doubleDigit;
    }
    
    int checkDigit = (10 - (sum % 10)) % 10;
    buffer.write(checkDigit);
    
    return buffer.toString();
  }

  /// Formata bytes para hex string
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }
}

/// Pacote recebido do servidor
class GT06ServerPacket {
  final int protocolNumber;
  final Uint8List content;
  final int serialNumber;
  final bool checksumValid;
  final Uint8List rawData;

  GT06ServerPacket({
    required this.protocolNumber,
    required this.content,
    required this.serialNumber,
    required this.checksumValid,
    required this.rawData,
  });

  String get protocolName {
    switch (protocolNumber) {
      case GT06Protocol.PROTOCOL_LOGIN: return 'LOGIN_ACK';
      case GT06Protocol.PROTOCOL_LOCATION: return 'LOCATION_ACK';
      case GT06Protocol.PROTOCOL_STATUS: return 'HEARTBEAT_ACK';
      case GT06Protocol.PROTOCOL_COMMAND: return 'COMMAND';
      case GT06Protocol.PROTOCOL_COMMAND_RESPONSE: return 'CMD_ACK';
      default: return 'UNKNOWN(0x${protocolNumber.toRadixString(16)})';
    }
  }
}

/// Comando parseado do Traccar
class GT06Command {
  final String rawCommand;
  final String commandType;
  final int serialNumber;

  GT06Command({
    required this.rawCommand,
    required this.commandType,
    required this.serialNumber,
  });

  /// Retorna o comando para enviar ao Arduino (igual ao Python)
  String get arduinoCommand {
    if (rawCommand.contains("Relay,1") || rawCommand.toUpperCase().contains("RELAY,1")) {
      return 'ENGINE_STOP';
    } else if (rawCommand.contains("Relay,0") || rawCommand.toUpperCase().contains("RELAY,0")) {
      return 'ENGINE_RESUME';
    }
    return rawCommand; // Para outros comandos, envia o texto original
  }

  @override
  String toString() => 'GT06Command(type: $commandType, raw: "$rawCommand")';
}