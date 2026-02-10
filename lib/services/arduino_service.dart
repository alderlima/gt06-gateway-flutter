import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';
import '../models/tracker_state.dart';

/// ============================================================================
/// SERVIÇO ARDUINO - Comunicação USB Serial
/// ============================================================================
/// 
/// Gerencia a comunicação com Arduino via cabo USB-OTG.
/// Envia comandos recebidos do Traccar para o Arduino.
/// 
/// COMANDOS SUPORTADOS:
/// - ENGINE_STOP → Desliga o relé (bloqueia motor)
/// - ENGINE_RESUME → Liga o relé (libera motor)
/// - GET_POSITION → Solicita posição GPS
/// - GET_STATUS → Solicita status do dispositivo
/// ============================================================================

class ArduinoService {
  // Porta serial
  UsbPort? _port;
  
  // Stream subscriptions
  StreamSubscription<String>? _transactionSubscription;
  Transaction<String>? _transaction;
  
  // Stream controllers
  final StreamController<ArduinoMessage> _messageController = StreamController<ArduinoMessage>.broadcast();
  final StreamController<ArduinoState> _stateController = StreamController<ArduinoState>.broadcast();
  
  // Estado
  ArduinoState _state = ArduinoState();
  
  // Contadores de estatísticas
  int _commandsSent = 0;
  int _messagesReceived = 0;
  
  // Baud rates disponíveis
  static const List<int> availableBaudRates = [
    9600,
    19200,
    38400,
    57600,
    115200,
  ];
  
  // Getters
  ArduinoState get state => _state;
  bool get isConnected => _state.status == ArduinoStatus.connected;
  int get commandsSent => _commandsSent;
  int get messagesReceived => _messagesReceived;
  Stream<ArduinoMessage> get messageStream => _messageController.stream;
  Stream<ArduinoState> get stateStream => _stateController.stream;

  /// ==========================================================================
  /// DISPOSITIVOS
  /// ==========================================================================

  /// Lista dispositivos USB disponíveis
  Future<List<UsbDevice>> listDevices() async {
    try {
      print('[ARDUINO_SERVICE] Listando dispositivos USB...');
      final devices = await UsbSerial.listDevices();
      print('[ARDUINO_SERVICE] ${devices.length} dispositivo(s) encontrado(s)');
      for (var d in devices) {
        print('[ARDUINO_SERVICE]   - ${d.productName} (${d.manufacturerName}) - VID:${d.vid} PID:${d.pid}');
      }
      return devices;
    } catch (e) {
      _notifyMessage('Erro ao listar dispositivos: $e', ArduinoMessageType.error);
      return [];
    }
  }

  /// ==========================================================================
  /// CONEXÃO
  /// ==========================================================================

  /// Conecta a um dispositivo específico
  Future<bool> connect(UsbDevice device, {int baudRate = 9600}) async {
    print('[ARDUINO_SERVICE] Conectando a ${device.productName} @ $baudRate bps');
    
    if (_state.status == ArduinoStatus.connected) {
      print('[ARDUINO_SERVICE] Já conectado, desconectando primeiro...');
      await disconnect();
    }
    
    _updateState(status: ArduinoStatus.connecting);
    
    try {
      // Abre porta
      print('[ARDUINO_SERVICE] Criando porta...');
      _port = await device.create();
      if (_port == null) {
        _updateState(status: ArduinoStatus.error);
        _notifyMessage('Não foi possível criar porta USB', ArduinoMessageType.error);
        return false;
      }
      
      // Abre conexão
      print('[ARDUINO_SERVICE] Abrindo porta...');
      bool openResult = await _port!.open();
      if (!openResult) {
        _updateState(status: ArduinoStatus.error);
        _notifyMessage('Não foi possível abrir porta USB', ArduinoMessageType.error);
        return false;
      }
      
      // Configura porta
      print('[ARDUINO_SERVICE] Configurando porta (DTR, RTS)...');
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      
      print('[ARDUINO_SERVICE] Configurando parâmetros: $baudRate, 8N1');
      await _port!.setPortParameters(
        baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      
      // Configura listener de mensagens
      print('[ARDUINO_SERVICE] Configurando listener...');
      _setupMessageListener();
      
      _updateState(
        status: ArduinoStatus.connected,
        deviceName: device.productName ?? 'Arduino',
        baudRate: baudRate,
      );
      
      _notifyMessage(
        'Conectado a ${device.productName ?? "Arduino"} @ $baudRate bps',
        ArduinoMessageType.info,
      );
      
      print('[ARDUINO_SERVICE] >>> CONECTADO COM SUCESSO! <<<');
      return true;
      
    } catch (e) {
      print('[ARDUINO_SERVICE] Erro ao conectar: $e');
      _updateState(status: ArduinoStatus.error);
      _notifyMessage('Erro ao conectar: $e', ArduinoMessageType.error);
      return false;
    }
  }

  /// Conecta automaticamente ao primeiro Arduino disponível
  Future<bool> autoConnect({int baudRate = 9600}) async {
    print('[ARDUINO_SERVICE] AutoConnect iniciado');
    final devices = await listDevices();
    
    if (devices.isEmpty) {
      _notifyMessage('Nenhum dispositivo USB encontrado', ArduinoMessageType.warning);
      return false;
    }
    
    // Tenta encontrar um dispositivo que pareça ser Arduino
    for (final device in devices) {
      final name = (device.productName ?? '').toLowerCase();
      final manufacturer = (device.manufacturerName ?? '').toLowerCase();
      
      print('[ARDUINO_SERVICE] Verificando: $name ($manufacturer)');
      
      if (name.contains('arduino') || 
          name.contains('ch340') || 
          name.contains('ftdi') ||
          name.contains('cp210') ||
          name.contains('usb-serial') ||
          name.contains('serial') ||
          manufacturer.contains('arduino')) {
        print('[ARDUINO_SERVICE] Dispositivo Arduino encontrado!');
        return await connect(device, baudRate: baudRate);
      }
    }
    
    // Se não encontrou Arduino específico, tenta o primeiro
    print('[ARDUINO_SERVICE] Arduino específico não encontrado, tentando primeiro dispositivo');
    return await connect(devices.first, baudRate: baudRate);
  }

  /// Desconecta do Arduino
  Future<void> disconnect() async {
    print('[ARDUINO_SERVICE] Desconectando...');
    await _transactionSubscription?.cancel();
    _transactionSubscription = null;
    _transaction = null;
    
    if (_port != null) {
      try {
        await _port!.close();
      } catch (e) {
        // Ignora erro ao fechar
      }
      _port = null;
    }
    
    _commandsSent = 0;
    _messagesReceived = 0;
    _updateState(status: ArduinoStatus.disconnected);
    _notifyMessage('Desconectado do Arduino', ArduinoMessageType.info);
    print('[ARDUINO_SERVICE] Desconectado');
  }

  /// Configura listener de mensagens
  void _setupMessageListener() {
    if (_port == null) {
      print('[ARDUINO_SERVICE] Porta nula, não pode configurar listener');
      return;
    }
    
    try {
      print('[ARDUINO_SERVICE] Configurando transação de strings...');
      
      // Cria a transação para ler strings terminadas em LF (\n)
      _transaction = Transaction.stringTerminated(
        _port!.inputStream!,
        Uint8List.fromList([0x0A]),  // LF - Line Feed (\n)
      );

      // Escuta mensagens recebidas
      _transactionSubscription = _transaction!.stream.listen(
        (String line) {
          print('[ARDUINO_SERVICE] Dados recebidos: "$line"');
          _onMessageReceived(line);
        },
        onError: (error) {
          print('[ARDUINO_SERVICE] Erro na transação: $error');
          _notifyMessage('Erro na comunicação: $error', ArduinoMessageType.error);
        },
        onDone: () {
          print('[ARDUINO_SERVICE] Transação encerrada');
          _notifyMessage('Conexão encerrada', ArduinoMessageType.info);
          _updateState(status: ArduinoStatus.disconnected);
        },
      );
      
      print('[ARDUINO_SERVICE] Listener configurado com sucesso');
    } catch (e) {
      print('[ARDUINO_SERVICE] Erro ao configurar listener: $e');
      _notifyMessage('Erro ao configurar listener: $e', ArduinoMessageType.error);
    }
  }


  /// ==========================================================================
  /// ENVIO DE MENSAGENS
  /// ==========================================================================

  /// Envia comando para o Arduino
  /// 
  /// Comandos suportados:
  /// - ENGINE_STOP → Desliga o relé (bloqueia motor)
  /// - ENGINE_RESUME → Liga o relé (libera motor)
  /// - GET_POSITION → Solicita posição GPS
  /// - GET_STATUS → Solicita status do dispositivo
  /// 
  /// O comando é enviado com \n ao final para compatibilidade com
  /// Serial.readStringUntil('\n') no Arduino
  Future<bool> sendCommand(String command) async {
    print('[ARDUINO_SERVICE] ==========================================');
    print('[ARDUINO_SERVICE] >>> sendCommand() chamado <<<');
    print('[ARDUINO_SERVICE] Comando: "$command"');
    print('[ARDUINO_SERVICE] Porta: ${_port != null ? "OK" : "NULL"}');
    print('[ARDUINO_SERVICE] Status: ${_state.status}');
    print('[ARDUINO_SERVICE] ==========================================');
    
    if (_port == null) {
      print('[ARDUINO_SERVICE] ERRO: Porta é nula!');
      _notifyMessage('Arduino não conectado (porta nula)', ArduinoMessageType.warning);
      return false;
    }
    
    if (_state.status != ArduinoStatus.connected) {
      print('[ARDUINO_SERVICE] ERRO: Status não é connected!');
      _notifyMessage('Arduino não conectado (status: ${_state.status})', ArduinoMessageType.warning);
      return false;
    }
    
    if (command.isEmpty) {
      print('[ARDUINO_SERVICE] ERRO: Comando vazio!');
      _notifyMessage('Comando vazio - não enviado', ArduinoMessageType.warning);
      return false;
    }
    
    try {
      // Adiciona newline se não tiver
      String message = command;
      if (!message.endsWith('\n')) {
        message += '\n';
      }
      
      print('[ARDUINO_SERVICE] Enviando: ${message.length} bytes');
      print('[ARDUINO_SERVICE] Hex: ${message.codeUnits.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
      
      final data = Uint8List.fromList(utf8.encode(message));
      
      // O método write do usb_serial retorna Future<void>, não a quantidade de bytes.
      await _port!.write(data);
      
      _commandsSent++;
      _notifyMessage('Enviado: $command', ArduinoMessageType.sent);
      _updateState(lastMessage: command, lastMessageTime: DateTime.now());
      print('[ARDUINO_SERVICE] >>> ENVIADO COM SUCESSO! <<<');
      return true;
      
    } catch (e) {
      print('[ARDUINO_SERVICE] ERRO ao enviar: $e');
      _notifyMessage('Erro ao enviar: $e', ArduinoMessageType.error);
      return false;
    }
  }


  /// Envia comando para parar o motor (ENGINE_STOP)
  Future<bool> sendEngineStop() async {
    print('[ARDUINO_SERVICE] Enviando ENGINE_STOP');
    return await sendCommand('ENGINE_STOP');
  }

  /// Envia comando para liberar o motor (ENGINE_RESUME)
  Future<bool> sendEngineResume() async {
    print('[ARDUINO_SERVICE] Enviando ENGINE_RESUME');
    return await sendCommand('ENGINE_RESUME');
  }

  /// ==========================================================================
  /// RECEBIMENTO DE MENSAGENS
  /// ==========================================================================

  void _onMessageReceived(String message) {
    // Remove caracteres de controle (\r, \n)
    final cleanMessage = message.replaceAll(RegExp(r'[\r\n]'), '').trim();
    
    if (cleanMessage.isEmpty) return;
    
    _messagesReceived++;
    _notifyMessage('Recebido: $cleanMessage', ArduinoMessageType.received);
    
    _updateState(lastMessage: cleanMessage, lastMessageTime: DateTime.now());
  }

  /// ==========================================================================
  /// NOTIFICAÇÕES
  /// ==========================================================================

  void _notifyMessage(String message, ArduinoMessageType type) {
    print('[ARDUINO_SERVICE] Notify: [$type] $message');
    _messageController.add(ArduinoMessage(
      message: message,
      type: type,
      timestamp: DateTime.now(),
    ));
  }

  void _updateState({
    ArduinoStatus? status,
    String? deviceName,
    int? baudRate,
    String? lastMessage,
    DateTime? lastMessageTime,
  }) {
    _state = _state.copyWith(
      status: status,
      deviceName: deviceName,
      baudRate: baudRate,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
    );
    _stateController.add(_state);
  }

  /// ==========================================================================
  /// UTILIDADES - Conversão de comandos Traccar
  /// ==========================================================================

  /// Converte comando Traccar para comando Arduino
  /// 
  /// Comandos Traccar comuns:
  /// - "Relay,1#" → ENGINE_STOP (bloqueia motor)
  /// - "Relay,0#" → ENGINE_RESUME (libera motor)
  /// - "where", "position", "gps" → GET_POSITION
  /// - "status" → GET_STATUS
  String convertTraccarCommand(String traccarCommand) {
    print('[ARDUINO_SERVICE] Convertendo comando: "$traccarCommand"');
    
    final upper = traccarCommand.toUpperCase().trim();
    
    // Comandos de bloqueio/desbloqueio de motor
    if (upper.contains('Relay,1#') || 
        upper.contains('STOP') || 
        upper.contains('CUT') || 
        upper.contains('BLOQUEAR') ||
        upper.contains('BLOCK') ||
        upper.contains('KILL') ||
        upper.contains('DESLIGAR')) {
      print('[ARDUINO_SERVICE] Convertido: ENGINE_STOP');
      return 'ENGINE_STOP';
    } 
    else if (upper.contains('Relay,0#') || 
             upper.contains('RESUME') || 
             upper.contains('RESTORE') || 
             upper.contains('DESBLOQUEAR') ||
             upper.contains('UNBLOCK') ||
             upper.contains('START') ||
             upper.contains('LIGAR')) {
      print('[ARDUINO_SERVICE] Convertido: ENGINE_RESUME');
      return 'ENGINE_RESUME';
    } 
    // Comandos de localização
    else if (upper.contains('WHERE') || 
             upper.contains('LOCATE') || 
             upper.contains('POSICAO') ||
             upper.contains('POSITION') ||
             upper.contains('GPS')) {
      print('[ARDUINO_SERVICE] Convertido: GET_POSITION');
      return 'GET_POSITION';
    } 
    // Comandos de status
    else if (upper.contains('STATUS') || 
             upper.contains('ESTADO') ||
             upper.contains('INFO')) {
      print('[ARDUINO_SERVICE] Convertido: GET_STATUS');
      return 'GET_STATUS';
    }
    
    // Se não reconheceu, passa o comando original
    print('[ARDUINO_SERVICE] Convertido: $traccarCommand (original)');
    return traccarCommand;
  }

  /// Libera recursos
  void dispose() {
    print('[ARDUINO_SERVICE] Dispose');
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}

/// Mensagem do Arduino
class ArduinoMessage {
  final String message;
  final ArduinoMessageType type;
  final DateTime timestamp;

  ArduinoMessage({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}

enum ArduinoMessageType {
  info,
  sent,
  received,
  error,
  warning,
}
