import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'gt06_protocol.dart';

/// ============================================================================
/// CLIENTE GT06 - Conexão TCP com Servidor Traccar
/// ============================================================================
/// 
/// Implementa cliente TCP que se conecta ao servidor Traccar e se comporta
/// exatamente como um rastreador GT06 físico.
///
/// FLUXO:
/// 1. Conectar ao servidor
/// 2. Enviar LOGIN (0x01)
/// 3. Aguardar LOGIN_ACK (0x01)
/// 4. Iniciar heartbeat periódico
/// 5. Enviar posições GPS
/// 6. Receber comandos (0x80) e repassar para Arduino
/// ============================================================================

class GT06Client {
  final GT06Protocol _protocol = GT06Protocol();
  
  // Socket
  Socket? _socket;
  
  // Estado
  bool _isConnected = false;
  bool _isLoggedIn = false;
  String _serverAddress = '';
  int _serverPort = 5023;
  String _imei = '';
  int _heartbeatInterval = 30;
  
  // Timers
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  // Buffer de recepção
  final List<int> _receiveBuffer = [];
  
  // Stream controllers
  final StreamController<ClientEvent> _eventController = StreamController<ClientEvent>.broadcast();
  final StreamController<GT06Command> _commandController = StreamController<GT06Command>.broadcast();
  final StreamController<Uint8List> _rawDataController = StreamController<Uint8List>.broadcast();
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isLoggedIn => _isLoggedIn;
  String get serverAddress => _serverAddress;
  int get serverPort => _serverPort;
  String get imei => _imei;
  
  // Streams
  Stream<ClientEvent> get eventStream => _eventController.stream;
  Stream<GT06Command> get commandStream => _commandController.stream;
  Stream<Uint8List> get rawDataStream => _rawDataController.stream;

  /// ==========================================================================
  /// CONEXÃO
  /// ==========================================================================

  /// Conecta ao servidor Traccar
  Future<void> connect({
    required String serverAddress,
    required int serverPort,
    required String imei,
    int heartbeatInterval = 30,
  }) async {
    if (_isConnected) {
      await disconnect();
    }
    
    _serverAddress = serverAddress;
    _serverPort = serverPort;
    _imei = imei;
    _heartbeatInterval = heartbeatInterval;
    _protocol.resetSerial();
    
    _notifyEvent(ClientEventType.connecting, 'Conectando a $serverAddress:$serverPort...');
    print('[GT06_CLIENT] Iniciando conexão para $serverAddress:$serverPort');
    
    try {
      // Cria conexão TCP
      _socket = await Socket.connect(
        serverAddress,
        serverPort,
        timeout: const Duration(seconds: 30),
      );
      
      _isConnected = true;
      print('[GT06_CLIENT] Socket conectado com sucesso');
      _notifyEvent(ClientEventType.connected, 'Conectado a $serverAddress:$serverPort');
      
      // Configura listeners
      _setupSocketListeners();
      
      // Envia login
      await _sendLogin();
      
    } catch (e) {
      _isConnected = false;
      print('[GT06_CLIENT] Erro ao conectar: $e');
      _notifyEvent(ClientEventType.error, 'Erro ao conectar: $e');
      _scheduleReconnect(heartbeatInterval);
    }
  }

  /// Configura listeners do socket
  void _setupSocketListeners() {
    if (_socket == null) return;
    
    print('[GT06_CLIENT] Configurando listeners do socket');
    
    _socket!.listen(
      _onDataReceived,
      onError: _onSocketError,
      onDone: _onSocketClosed,
      cancelOnError: false,
    );
  }

  /// Desconecta do servidor
  Future<void> disconnect() async {
    print('[GT06_CLIENT] Desconectando...');
    _stopTimers();
    
    if (_socket != null) {
      try {
        await _socket!.close();
      } catch (e) {
        // Ignora erro ao fechar
      }
      _socket = null;
    }
    
    _isConnected = false;
    _isLoggedIn = false;
    _receiveBuffer.clear();
    
    _notifyEvent(ClientEventType.disconnected, 'Desconectado do servidor');
    print('[GT06_CLIENT] Desconectado');
  }

  /// ==========================================================================
  /// ENVIO DE PACOTES
  /// ==========================================================================

  /// Envia pacote de LOGIN
  Future<void> _sendLogin() async {
    if (!_isConnected) return;
    
    final packet = _protocol.createLoginPacket(_imei);
    print('[GT06_CLIENT] Enviando LOGIN: ${GT06Protocol.bytesToHex(packet)}');
    await _sendPacket(packet, 'LOGIN');
    
    _notifyEvent(ClientEventType.loggingIn, 'Enviando login com IMEI: $_imei');
  }

  /// Envia heartbeat
  Future<void> sendHeartbeat() async {
    if (!_isConnected || !_isLoggedIn) return;
    
    final packet = _protocol.createHeartbeatPacket();
    await _sendPacket(packet, 'HEARTBEAT');
  }

  /// Envia posição GPS
  Future<void> sendLocation({
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    DateTime? dateTime,
  }) async {
    if (!_isConnected || !_isLoggedIn) return;
    
    final packet = _protocol.createLocationPacket(
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      course: course,
      dateTime: dateTime,
    );
    
    await _sendPacket(packet, 'LOCATION');
  }

  /// Envia alarme
  Future<void> sendAlarm({
    required int alarmType,
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
  }) async {
    if (!_isConnected || !_isLoggedIn) return;
    
    final packet = _protocol.createAlarmPacket(
      alarmType: alarmType,
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      course: course,
    );
    
    await _sendPacket(packet, 'ALARM');
  }

  /// Envia ACK de comando (0x80) - IGUAL AO PYTHON
  Future<void> sendCommandAck(int serialNumber) async {
    if (!_isConnected) return;
    
    print('[GT06_CLIENT] Enviando ACK do comando (serial: $serialNumber)');
    
    // Constrói pacote ACK igual ao Python: build_packet(0x80, b"", serial)
    final builder = BytesBuilder();
    
    // Start bytes
    builder.add(GT06Protocol.START_BYTES);
    
    // Content length = protocol(1) + payload(0) + serial(2) = 3
    builder.addByte(0x03);
    
    // Protocol number (0x80 para ACK de comando)
    builder.addByte(GT06Protocol.PROTOCOL_COMMAND);
    
    // Payload vazio
    // Serial number (2 bytes, big-endian)
    builder.addByte((serialNumber >> 8) & 0xFF);
    builder.addByte(serialNumber & 0xFF);
    
    // Checksum
    final contentForChecksum = builder.toBytes().sublist(2);
    int checksum = 0;
    for (int byte in contentForChecksum) {
      checksum ^= byte;
    }
    builder.addByte(checksum);
    
    // Stop bytes
    builder.add(GT06Protocol.STOP_BYTES);
    
    final packet = Uint8List.fromList(builder.toBytes());
    
    print('[GT06_CLIENT] ACK hex: ${GT06Protocol.bytesToHex(packet)}');
    await _sendPacket(packet, 'CMD_ACK');
  }

  /// Envia pacote genérico
  Future<void> _sendPacket(Uint8List packet, String type) async {
    if (_socket == null || !_isConnected) {
      throw Exception('Socket não conectado');
    }
    
    try {
      _socket!.add(packet);
      await _socket!.flush();
      
      _notifyEvent(
        ClientEventType.packetSent, 
        'Enviado: $type',
        data: {'hex': GT06Protocol.bytesToHex(packet)},
      );
      
      _rawDataController.add(packet);
      
    } catch (e) {
      _notifyEvent(ClientEventType.error, 'Erro ao enviar $type: $e');
      _handleDisconnection();
    }
  }

  /// ==========================================================================
  /// RECEBIMENTO DE DADOS
  /// ==========================================================================

  /// Manipula dados recebidos
  void _onDataReceived(Uint8List data) {
    print('[GT06_CLIENT] Dados recebidos: ${data.length} bytes');
    print('[GT06_CLIENT] Hex: ${GT06Protocol.bytesToHex(data)}');
    
    _receiveBuffer.addAll(data);
    _rawDataController.add(data);
    
    _notifyEvent(
      ClientEventType.dataReceived,
      'Recebidos ${data.length} bytes',
      data: {'hex': GT06Protocol.bytesToHex(data)},
    );
    
    _processReceiveBuffer();
  }

  /// Processa buffer de recepção
  void _processReceiveBuffer() {
    print('[GT06_CLIENT] Processando buffer: ${_receiveBuffer.length} bytes');
    
    while (_receiveBuffer.length >= 9) {
      // Procura start bytes
      int startIndex = -1;
      for (int i = 0; i < _receiveBuffer.length - 1; i++) {
        if (_receiveBuffer[i] == GT06Protocol.START_BYTES[0] && 
            _receiveBuffer[i + 1] == GT06Protocol.START_BYTES[1]) {
          startIndex = i;
          break;
        }
      }
      
      if (startIndex == -1) {
        print('[GT06_CLIENT] Start bytes não encontrados, limpando buffer');
        _receiveBuffer.clear();
        return;
      }
      
      // Remove lixo antes do start
      if (startIndex > 0) {
        print('[GT06_CLIENT] Removendo $startIndex bytes de lixo');
        _receiveBuffer.removeRange(0, startIndex);
      }
      
      if (_receiveBuffer.length < 3) return;
      
      int contentLength = _receiveBuffer[2];
      int packetLength = 2 + 1 + contentLength + 2 + 2; // start + len + content + crc + stop
      
      print('[GT06_CLIENT] Content length: $contentLength, Packet length: $packetLength');
      
      if (_receiveBuffer.length < packetLength) {
        print('[GT06_CLIENT] Pacote incompleto, aguardando...');
        return;
      }
      
      // Extrai pacote
      final packet = Uint8List.fromList(_receiveBuffer.sublist(0, packetLength));
      _receiveBuffer.removeRange(0, packetLength);
      
      print('[GT06_CLIENT] Pacote extraído: ${GT06Protocol.bytesToHex(packet)}');
      
      // Processa pacote
      _processPacket(packet);
    }
  }

  /// Processa pacote recebido
  void _processPacket(Uint8List packet) {
    print('[GT06_CLIENT] Processando pacote...');
    final parsed = _protocol.parseServerPacket(packet);
    
    if (parsed == null) {
      print('[GT06_CLIENT] Pacote inválido');
      _notifyEvent(ClientEventType.warning, 'Pacote inválido recebido');
      return;
    }
    
    print('[GT06_CLIENT] Pacote: ${parsed.protocolName} (0x${parsed.protocolNumber.toRadixString(16)})');
    
    _notifyEvent(
      ClientEventType.packetReceived,
      'Recebido: ${parsed.protocolName}',
      data: {
        'protocol': parsed.protocolNumber,
        'serial': parsed.serialNumber,
        'hex': GT06Protocol.bytesToHex(packet),
      },
    );
    
    switch (parsed.protocolNumber) {
      case GT06Protocol.PROTOCOL_LOGIN:
        print('[GT06_CLIENT] >>> LOGIN_ACK recebido! <<<');
        _handleLoginAck(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_STATUS:
        _handleHeartbeatAck(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_LOCATION:
        _handleLocationAck(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_COMMAND:
        print('[GT06_CLIENT] >>> COMANDO (0x80) recebido! <<<');
        _handleCommand(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_COMMAND_RESPONSE:
        _handleCommandAck(parsed);
        break;
        
      default:
        print('[GT06_CLIENT] Protocolo desconhecido: 0x${parsed.protocolNumber.toRadixString(16)}');
    }
  }

  /// Manipula ACK de login
  void _handleLoginAck(GT06ServerPacket packet) {
    print('[GT06_CLIENT] >>> Processando LOGIN_ACK <<<');
    _isLoggedIn = true;
    _notifyEvent(ClientEventType.loggedIn, 'Login aceito pelo servidor!');
    print('[GT06_CLIENT] Estado: _isLoggedIn = true');
    
    // Inicia heartbeat automático
    print('[GT06_CLIENT] Iniciando heartbeat (${_heartbeatInterval}s)');
    startHeartbeat(_heartbeatInterval);
  }

  /// Manipula ACK de heartbeat
  void _handleHeartbeatAck(GT06ServerPacket packet) {
    print('[GT06_CLIENT] HEARTBEAT_ACK recebido');
    _notifyEvent(ClientEventType.heartbeatAck, 'Heartbeat confirmado');
  }

  /// Manipula ACK de location
  void _handleLocationAck(GT06ServerPacket packet) {
    print('[GT06_CLIENT] LOCATION_ACK recebido');
    _notifyEvent(ClientEventType.locationAck, 'Posição confirmada');
  }

  /// Manipula comando do servidor (0x80) - IGUAL AO PYTHON
  void _handleCommand(GT06ServerPacket packet) {
    print('[GT06_CLIENT] ==========================================');
    print('[GT06_CLIENT] >>> PROCESSANDO COMANDO (0x80) <<<');
    print('[GT06_CLIENT] Serial: ${packet.serialNumber}');
    print('[GT06_CLIENT] Content: ${GT06Protocol.bytesToHex(packet.content)}');
    
    final command = _protocol.parseCommand(packet);
    
    if (command != null) {
      print('[GT06_CLIENT] >>> COMANDO PARSEADO <<<');
      print('[GT06_CLIENT] Tipo: ${command.commandType}');
      print('[GT06_CLIENT] Raw: "${command.rawCommand}"');
      print('[GT06_CLIENT] Arduino: "${command.arduinoCommand}"');
      
      _notifyEvent(
        ClientEventType.commandReceived,
        'Comando: ${command.commandType}',
        data: {
          'raw': command.rawCommand,
          'type': command.commandType,
          'arduino': command.arduinoCommand,
        },
      );
      
      // Adiciona ao stream de comandos
      _commandController.add(command);
      print('[GT06_CLIENT] Comando adicionado ao stream');
      
      // Envia ACK para o Traccar (IMEDIATAMENTE, igual ao Python)
      print('[GT06_CLIENT] Enviando ACK do comando...');
      sendCommandAck(packet.serialNumber);
      
    } else {
      print('[GT06_CLIENT] Não foi possível parsear o comando');
      // Mesmo assim envia ACK (igual ao Python)
      print('[GT06_CLIENT] Enviando ACK mesmo sem parse');
      sendCommandAck(packet.serialNumber);
    }
    
    print('[GT06_CLIENT] ==========================================');
  }

  /// Manipula ACK de comando
  void _handleCommandAck(GT06ServerPacket packet) {
    print('[GT06_CLIENT] CMD_ACK recebido');
    _notifyEvent(ClientEventType.commandAck, 'Resposta de comando confirmada');
  }

  /// ==========================================================================
  /// HANDLERS DE SOCKET
  /// ==========================================================================

  void _onSocketError(error) {
    print('[GT06_CLIENT] Erro de socket: $error');
    _notifyEvent(ClientEventType.error, 'Erro de socket: $error');
    _handleDisconnection();
  }

  void _onSocketClosed() {
    print('[GT06_CLIENT] Socket fechado pelo servidor');
    _notifyEvent(ClientEventType.disconnected, 'Conexão fechada pelo servidor');
    _handleDisconnection();
  }

  void _handleDisconnection() {
    if (!_isConnected) return;
    
    print('[GT06_CLIENT] Processando desconexão');
    _isConnected = false;
    _isLoggedIn = false;
    _stopTimers();
    
    _notifyEvent(ClientEventType.disconnected, 'Desconectado');
  }

  /// ==========================================================================
  /// TIMERS E RECONEXÃO
  /// ==========================================================================

  /// Inicia heartbeat periódico
  void startHeartbeat(int intervalSeconds) {
    print('[GT06_CLIENT] Configurando heartbeat: ${intervalSeconds}s');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) {
        print('[GT06_CLIENT] Timer: enviando heartbeat');
        sendHeartbeat();
      },
    );
    
    // Envia heartbeat imediatamente
    print('[GT06_CLIENT] Enviando heartbeat inicial');
    sendHeartbeat();
  }

  /// Para timers
  void _stopTimers() {
    print('[GT06_CLIENT] Parando timers');
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer = null;
  }

  /// Agenda reconexão
  void _scheduleReconnect(int delaySeconds) {
    print('[GT06_CLIENT] Agendando reconexão em ${delaySeconds}s');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isConnected) {
        print('[GT06_CLIENT] Tentando reconectar...');
        connect(
          serverAddress: _serverAddress,
          serverPort: _serverPort,
          imei: _imei,
          heartbeatInterval: delaySeconds,
        );
      }
    });
  }

  /// ==========================================================================
  /// NOTIFICAÇÕES
  /// ==========================================================================

  void _notifyEvent(ClientEventType type, String message, {Map<String, dynamic>? data}) {
    print('[GT06_CLIENT] Evento: $type - $message');
    _eventController.add(ClientEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      data: data,
    ));
  }

  /// Libera recursos
  void dispose() {
    print('[GT06_CLIENT] Dispose');
    disconnect();
    _eventController.close();
    _commandController.close();
    _rawDataController.close();
  }
}

/// Evento do cliente
class ClientEvent {
  final ClientEventType type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  ClientEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

enum ClientEventType {
  connecting,
  connected,
  disconnected,
  error,
  loggingIn,
  loggedIn,
  packetSent,
  packetReceived,
  dataReceived,
  heartbeatAck,
  locationAck,
  commandReceived,
  commandAck,
  warning,
}