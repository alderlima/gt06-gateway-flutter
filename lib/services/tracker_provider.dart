import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gt06_client.dart';
import 'gt06_protocol.dart';
import 'gps_service.dart';
import 'arduino_service.dart';
import '../models/tracker_state.dart';

/// ============================================================================
/// TRACKER PROVIDER - Gerenciamento de Estado do Rastreador
/// ============================================================================
/// 
/// Provider principal que coordena todos os serviços:
/// - Cliente GT06 (conexão TCP com Traccar)
/// - Serviço GPS (localização do celular)
/// - Serviço Arduino (comunicação USB)
/// ============================================================================

class TrackerProvider extends ChangeNotifier {
  // Serviços
  final GT06Client _gt06Client = GT06Client();
  final GpsService _gpsService = GpsService();
  final ArduinoService _arduinoService = ArduinoService();
  
  // Estado
  TrackerStatus _status = TrackerStatus.disconnected;
  TrackerConfig _config = TrackerConfig();
  TrackerStats _stats = TrackerStats();
  ArduinoState _arduinoState = ArduinoState();
  GpsPosition? _currentPosition;
  
  // Logs
  final List<LogEntry> _logs = [];
  static const int maxLogs = 500;
  
  // Timers
  Timer? _locationTimer;
  
  // Subscriptions
  StreamSubscription? _clientEventSub;
  StreamSubscription? _clientCommandSub;
  StreamSubscription? _gpsPositionSub;
  StreamSubscription? _arduinoMessageSub;
  StreamSubscription? _arduinoStateSub;

  // Getters
  TrackerStatus get status => _status;
  TrackerConfig get config => _config;
  TrackerStats get stats => _stats;
  ArduinoState get arduinoState => _arduinoState;
  GpsPosition? get currentPosition => _currentPosition;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  ArduinoService get arduinoService => _arduinoService;
  
  bool get isOnline => _status == TrackerStatus.online;
  bool get isConnecting => _status == TrackerStatus.connecting || 
                           _status == TrackerStatus.connected || 
                           _status == TrackerStatus.loggingIn;
  bool get isConnected => _status == TrackerStatus.connected || 
                          _status == TrackerStatus.loggingIn || 
                          _status == TrackerStatus.online;
  bool get isArduinoConnected => _arduinoState.status == ArduinoStatus.connected;
  
  String get statusText {
    switch (_status) {
      case TrackerStatus.disconnected: return 'Desconectado';
      case TrackerStatus.connecting: return 'Conectando...';
      case TrackerStatus.connected: return 'Conectado';
      case TrackerStatus.loggingIn: return 'Autenticando...';
      case TrackerStatus.online: return 'ONLINE';
      case TrackerStatus.error: return 'Erro';
    }
  }
  
  Color get statusColor {
    switch (_status) {
      case TrackerStatus.online: return Colors.green;
      case TrackerStatus.connecting:
      case TrackerStatus.loggingIn: return Colors.orange;
      case TrackerStatus.connected: return Colors.blue;
      case TrackerStatus.error: return Colors.red;
      case TrackerStatus.disconnected: return Colors.grey;
    }
  }
  
  IconData get statusIcon {
    switch (_status) {
      case TrackerStatus.online: return Icons.check_circle;
      case TrackerStatus.connecting:
      case TrackerStatus.loggingIn: return Icons.sync;
      case TrackerStatus.connected: return Icons.cloud_done;
      case TrackerStatus.error: return Icons.error;
      case TrackerStatus.disconnected: return Icons.cloud_off;
    }
  }

  /// ==========================================================================
  /// INICIALIZAÇÃO
  /// ==========================================================================

  TrackerProvider() {
    print('[TRACKER_PROVIDER] Inicializando...');
    _init();
  }

  Future<void> _init() async {
    print('[TRACKER_PROVIDER] _init()');
    await _loadConfig();
    _setupListeners();
    
    if (_config.imei.isEmpty) {
      print('[TRACKER_PROVIDER] Gerando IMEI inicial');
      generateNewIMEI();
    }
    
    notifyListeners();
    print('[TRACKER_PROVIDER] Inicialização completa');
  }

  void _setupListeners() {
    print('[TRACKER_PROVIDER] Configurando listeners...');
    
    // Eventos do cliente GT06
    _clientEventSub = _gt06Client.eventStream.listen(
      _onClientEvent,
      onError: (e) => print('[TRACKER_PROVIDER] Erro no eventStream: $e'),
      onDone: () => print('[TRACKER_PROVIDER] eventStream encerrado'),
    );
    print('[TRACKER_PROVIDER] Listener de eventos configurado');
    
    // Comandos do servidor - AGORA USANDO GT06Command
    _clientCommandSub = _gt06Client.commandStream.listen(
      _onServerCommand,
      onError: (e) => print('[TRACKER_PROVIDER] Erro no commandStream: $e'),
      onDone: () => print('[TRACKER_PROVIDER] commandStream encerrado'),
    );
    print('[TRACKER_PROVIDER] Listener de comandos configurado');
    
    // Posições GPS
    _gpsPositionSub = _gpsService.positionStream.listen(_onGpsPosition);
    
    // Mensagens do Arduino
    _arduinoMessageSub = _arduinoService.messageStream.listen(_onArduinoMessage);
    
    // Estado do Arduino
    _arduinoStateSub = _arduinoService.stateStream.listen(_onArduinoState);
  }

  /// ==========================================================================
  /// CONFIGURAÇÃO
  /// ==========================================================================

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('tracker_config');
      
      if (json != null) {
        _config = TrackerConfig.fromJson(
          Map<String, dynamic>.from(jsonDecode(json) as Map),
        );
        print('[TRACKER_PROVIDER] Config carregada: IMEI=${_config.imei}');
      }
    } catch (e) {
      _addLog(LogType.error, 'Erro ao carregar configuração', e.toString());
    }
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tracker_config', jsonEncode(_config.toJson()));
    } catch (e) {
      _addLog(LogType.error, 'Erro ao salvar configuração', e.toString());
    }
  }

  void updateConfig({
    String? serverAddress,
    int? serverPort,
    String? imei,
    int? heartbeatInterval,
    int? locationInterval,
    bool? autoConnect,
  }) {
    _config = TrackerConfig(
      serverAddress: serverAddress ?? _config.serverAddress,
      serverPort: serverPort ?? _config.serverPort,
      imei: imei ?? _config.imei,
      heartbeatInterval: heartbeatInterval ?? _config.heartbeatInterval,
      locationInterval: locationInterval ?? _config.locationInterval,
      autoConnect: autoConnect ?? _config.autoConnect,
    );
    
    _saveConfig();
    notifyListeners();
  }

  void generateNewIMEI() {
    final newImei = GT06Protocol.generateRandomIMEI();
    updateConfig(imei: newImei);
    _addLog(LogType.info, 'Novo IMEI gerado: $newImei');
  }

  /// ==========================================================================
  /// CONEXÃO
  /// ==========================================================================

  Future<void> connect() async {
    print('[TRACKER_PROVIDER] connect() chamado');
    print('[TRACKER_PROVIDER] Status atual: $_status');
    
    if (_status == TrackerStatus.connecting || 
        _status == TrackerStatus.loggingIn ||
        _status == TrackerStatus.online) {
      print('[TRACKER_PROVIDER] Já está conectado ou conectando, ignorando');
      _addLog(LogType.warning, 'Já está conectado ou conectando');
      return;
    }
    
    if (_config.serverAddress.isEmpty) {
      print('[TRACKER_PROVIDER] Servidor não configurado');
      _addLog(LogType.error, 'Configure o servidor antes de conectar');
      return;
    }
    
    if (_config.imei.isEmpty || _config.imei.length != 15) {
      print('[TRACKER_PROVIDER] IMEI inválido: ${_config.imei}');
      _addLog(LogType.error, 'IMEI inválido. Deve ter 15 dígitos.');
      return;
    }
    
    print('[TRACKER_PROVIDER] Atualizando status para CONNECTING');
    _updateStatus(TrackerStatus.connecting);
    
    // Inicia GPS
    print('[TRACKER_PROVIDER] Iniciando GPS...');
    await _gpsService.startTracking(
      intervalSeconds: _config.locationInterval,
    );
    
    // Conecta ao servidor
    print('[TRACKER_PROVIDER] Conectando ao servidor GT06...');
    await _gt06Client.connect(
      serverAddress: _config.serverAddress,
      serverPort: _config.serverPort,
      imei: _config.imei,
      heartbeatInterval: _config.heartbeatInterval,
    );
  }

  Future<void> disconnect() async {
    print('[TRACKER_PROVIDER] disconnect() chamado');
    _stopLocationTimer();
    await _gpsService.stopTracking();
    await _gt06Client.disconnect();
    _updateStatus(TrackerStatus.disconnected);
    _stats.reset();
    notifyListeners();
  }

  /// ==========================================================================
  /// EVENTOS DO CLIENTE GT06
  /// ==========================================================================

  void _onClientEvent(ClientEvent event) {
    print('[TRACKER_PROVIDER] Evento recebido: ${event.type} - ${event.message}');
    
    switch (event.type) {
      case ClientEventType.connecting:
        print('[TRACKER_PROVIDER] >>> Estado: CONNECTING <<<');
        _updateStatus(TrackerStatus.connecting);
        break;
        
      case ClientEventType.connected:
        print('[TRACKER_PROVIDER] >>> Estado: CONNECTED <<<');
        _updateStatus(TrackerStatus.connected);
        _stats.connectedSince = DateTime.now();
        break;
        
      case ClientEventType.loggingIn:
        print('[TRACKER_PROVIDER] >>> Estado: LOGGING_IN <<<');
        _updateStatus(TrackerStatus.loggingIn);
        break;
        
      case ClientEventType.loggedIn:
        print('[TRACKER_PROVIDER] >>> Estado: ONLINE <<<');
        print('[TRACKER_PROVIDER] ==========================================');
        print('[TRACKER_PROVIDER] = LOGIN ACEITO! DISPOSITIVO ONLINE!      =');
        print('[TRACKER_PROVIDER] ==========================================');
        _updateStatus(TrackerStatus.online);
        _startLocationTimer();
        break;
        
      case ClientEventType.disconnected:
        print('[TRACKER_PROVIDER] >>> Estado: DISCONNECTED <<<');
        _updateStatus(TrackerStatus.disconnected);
        _stopLocationTimer();
        break;
        
      case ClientEventType.error:
        print('[TRACKER_PROVIDER] >>> Estado: ERROR <<<');
        _updateStatus(TrackerStatus.error);
        _addLog(LogType.error, event.message);
        break;
        
      case ClientEventType.packetSent:
        _stats.packetsSent++;
        _addLog(LogType.sent, event.message, event.data?['hex']);
        break;
        
      case ClientEventType.packetReceived:
        _stats.packetsReceived++;
        _addLog(LogType.received, event.message, event.data?['hex']);
        break;
        
      case ClientEventType.heartbeatAck:
        _stats.heartbeatsSent++;
        _addLog(LogType.info, event.message);
        break;
        
      case ClientEventType.locationAck:
        _stats.locationsSent++;
        _addLog(LogType.info, event.message);
        break;
        
      case ClientEventType.commandReceived:
        print('[TRACKER_PROVIDER] >>> Comando recebido no evento! <<<');
        _stats.commandsReceived++;
        _addLog(LogType.command, event.message, event.data?['raw']);
        break;
        
      default:
        _addLog(LogType.info, event.message);
    }
    
    _stats.lastActivity = DateTime.now();
    notifyListeners();
  }

  /// ==========================================================================
  /// COMANDOS DO SERVIDOR - IGUAL AO EXEMPLO PYTHON
  /// ==========================================================================

  void _onServerCommand(GT06Command command) {
    print('[TRACKER_PROVIDER] ==========================================');
    print('[TRACKER_PROVIDER] >>> COMANDO DO SERVIDOR RECEBIDO <<<');
    print('[TRACKER_PROVIDER] Tipo: ${command.commandType}');
    print('[TRACKER_PROVIDER] Raw: "${command.rawCommand}"');
    print('[TRACKER_PROVIDER] Arduino: "${command.arduinoCommand}"');
    print('[TRACKER_PROVIDER] Arduino conectado: ${_arduinoService.isConnected}');
    print('[TRACKER_PROVIDER] ==========================================');
    
    _addLog(LogType.command, 'Comando Traccar: ${command.rawCommand}');
    
    // Se for um comando conhecido (ENGINE_STOP ou ENGINE_RESUME)
    if (command.commandType == 'ENGINE_STOP' || command.commandType == 'ENGINE_RESUME') {
      print('[TRACKER_PROVIDER] Comando conhecido: ${command.commandType}');
      String arduinoCmd = command.arduinoCommand;
      _sendToArduinoWithRetry(arduinoCmd, command.rawCommand);
    } else {
      // Caso contrário, tenta detectar manualmente
      _detectAndSendCommand(command.rawCommand);
    }
  }

  /// Detectar comando manualmente (fallback)
  void _detectAndSendCommand(String rawCommand) {
    print('[TRACKER_PROVIDER] Tentando detectar comando manualmente...');
    String upper = rawCommand.toUpperCase();
    
    String arduinoCmd = '';
    
    if (upper.contains("RELAY")) {
      if (upper.contains(",1") || upper.contains("1#")) {
        arduinoCmd = 'ENGINE_STOP';
        print('[TRACKER_PROVIDER] Detectado manualmente: ENGINE_STOP');
      } else if (upper.contains(",0") || upper.contains("0#")) {
        arduinoCmd = 'ENGINE_RESUME';
        print('[TRACKER_PROVIDER] Detectado manualmente: ENGINE_RESUME');
      }
    } else if (upper.contains("STOP") || upper.contains("DESLIGAR") || upper.contains("BLOQUEAR")) {
      arduinoCmd = 'ENGINE_STOP';
    } else if (upper.contains("START") || upper.contains("LIGAR") || upper.contains("DESBLOQUEAR")) {
      arduinoCmd = 'ENGINE_RESUME';
    }
    
    if (arduinoCmd.isNotEmpty) {
      _sendToArduinoWithRetry(arduinoCmd, rawCommand);
    } else {
      print('[TRACKER_PROVIDER] Nenhum comando detectado');
      _addLog(LogType.warning, 'Comando não reconhecido: $rawCommand');
    }
  }

  /// Envia comando para Arduino com tentativa de reconexão
  Future<void> _sendToArduinoWithRetry(String arduinoCmd, String originalCmd) async {
    print('[TRACKER_PROVIDER] ==========================================');
    print('[TRACKER_PROVIDER] >>> ENVIANDO PARA ARDUINO <<<');
    print('[TRACKER_PROVIDER] Comando: $arduinoCmd');
    print('[TRACKER_PROVIDER] Arduino conectado: ${_arduinoService.isConnected}');
    print('[TRACKER_PROVIDER] ==========================================');
    
    if (!_arduinoService.isConnected) {
      print('[TRACKER_PROVIDER] Arduino não conectado, tentando conectar...');
      _addLog(LogType.warning, 'Arduino desconectado, tentando conectar...');
      
      final connected = await _arduinoService.autoConnect();
      
      if (!connected) {
        print('[TRACKER_PROVIDER] Falha ao conectar Arduino');
        _addLog(LogType.error, 'Falha ao conectar Arduino - comando perdido: $arduinoCmd');
        return;
      }
      
      // Aguarda um pouco para estabilizar conexão
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    // Envia comando
    print('[TRACKER_PROVIDER] Enviando comando para Arduino: $arduinoCmd');
    final success = await _arduinoService.sendCommand(arduinoCmd);
    
    if (success) {
      print('[TRACKER_PROVIDER] >>> COMANDO ENVIADO COM SUCESSO! <<<');
      _addLog(LogType.success, 'Arduino: $arduinoCmd - OK');
    } else {
      print('[TRACKER_PROVIDER] >>> FALHA AO ENVIAR COMANDO <<<');
      _addLog(LogType.error, 'Falha ao enviar para Arduino: $arduinoCmd');
      
      // Tenta reconectar e enviar novamente
      print('[TRACKER_PROVIDER] Tentando reconectar e reenviar...');
      await Future.delayed(const Duration(seconds: 1));
      
      await _arduinoService.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      
      final reconnected = await _arduinoService.autoConnect();
      if (reconnected) {
        await Future.delayed(const Duration(milliseconds: 500));
        final retrySuccess = await _arduinoService.sendCommand(arduinoCmd);
        
        if (retrySuccess) {
          print('[TRACKER_PROVIDER] >>> SUCESSO NA TENTATIVA 2 <<<');
          _addLog(LogType.success, 'Arduino: $arduinoCmd - OK (tentativa 2)');
        } else {
          print('[TRACKER_PROVIDER] >>> FALHA NA TENTATIVA 2 <<<');
          _addLog(LogType.error, 'Falha na tentativa 2: $arduinoCmd');
        }
      }
    }
  }

  /// ==========================================================================
  /// GPS
  /// ==========================================================================

  void _onGpsPosition(GpsPosition position) {
    _currentPosition = position;
    
    if (position.isValid) {
      _addLog(
        LogType.gps,
        'GPS: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        'Velocidade: ${position.speed.toStringAsFixed(1)} km/h',
      );
    }
    
    notifyListeners();
  }

  void _startLocationTimer() {
    print('[TRACKER_PROVIDER] Iniciando timer de localização');
    _stopLocationTimer();
    
    _sendCurrentLocation();
    
    _locationTimer = Timer.periodic(
      Duration(seconds: _config.locationInterval),
      (_) => _sendCurrentLocation(),
    );
  }

  void _stopLocationTimer() {
    print('[TRACKER_PROVIDER] Parando timer de localização');
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _sendCurrentLocation() async {
    if (_currentPosition == null || !_currentPosition!.isValid) {
      final position = await _gpsService.getCurrentPosition();
      if (position == null || !position.isValid) return;
      _currentPosition = position;
    }
    
    await _gt06Client.sendLocation(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      speed: _currentPosition!.speed,
      course: _currentPosition!.heading,
    );
  }

  /// ==========================================================================
  /// ARDUINO
  /// ==========================================================================

  Future<void> connectArduino() async {
    print('[TRACKER_PROVIDER] Conectando Arduino...');
    final connected = await _arduinoService.autoConnect();
    
    if (connected) {
      print('[TRACKER_PROVIDER] Arduino conectado com sucesso');
      _addLog(LogType.arduino, 'Arduino conectado');
    } else {
      print('[TRACKER_PROVIDER] Falha ao conectar Arduino');
      _addLog(LogType.warning, 'Falha ao conectar Arduino');
    }
  }

  Future<void> disconnectArduino() async {
    print('[TRACKER_PROVIDER] Desconectando Arduino...');
    await _arduinoService.disconnect();
    _addLog(LogType.arduino, 'Arduino desconectado');
  }

  Future<void> sendToArduino(String command) async {
    print('[TRACKER_PROVIDER] Enviando comando manual ao Arduino: $command');
    final success = await _arduinoService.sendCommand(command);
    if (success) {
      _addLog(LogType.arduino, 'Comando manual enviado: $command');
    } else {
      _addLog(LogType.error, 'Falha ao enviar comando manual');
    }
  }

  void _onArduinoMessage(ArduinoMessage message) {
    LogType logType;
    switch (message.type) {
      case ArduinoMessageType.sent:
        logType = LogType.arduino;
        break;
      case ArduinoMessageType.received:
        logType = LogType.arduino;
        break;
      case ArduinoMessageType.error:
        logType = LogType.error;
        break;
      case ArduinoMessageType.warning:
        logType = LogType.warning;
        break;
      default:
        logType = LogType.info;
    }
    
    _addLog(logType, '[Arduino] ${message.message}');
  }

  void _onArduinoState(ArduinoState state) {
    print('[TRACKER_PROVIDER] Estado do Arduino mudou: ${state.status}');
    _arduinoState = state;
    notifyListeners();
  }

  /// ==========================================================================
  /// LOGS
  /// ==========================================================================

  void _addLog(LogType type, String message, [String? details]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      type: type,
      message: message,
      details: details,
    );
    
    _logs.add(entry);
    
    if (_logs.length > maxLogs) {
      _logs.removeAt(0);
    }
    
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// ==========================================================================
  /// UTILIDADES
  /// ==========================================================================

  void _updateStatus(TrackerStatus status) {
    print('[TRACKER_PROVIDER] _updateStatus: $_status -> $status');
    _status = status;
    notifyListeners();
  }

  /// Envia alarme SOS
  Future<void> sendSosAlarm() async {
    if (_currentPosition != null) {
      await _gt06Client.sendAlarm(
        alarmType: GT06Protocol.ALARM_SOS,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        speed: _currentPosition!.speed,
      );
      _addLog(LogType.warning, 'Alarme SOS enviado!');
    }
  }

  /// Libera recursos
  @override
  void dispose() {
    print('[TRACKER_PROVIDER] Dispose');
    _clientEventSub?.cancel();
    _clientCommandSub?.cancel();
    _gpsPositionSub?.cancel();
    _arduinoMessageSub?.cancel();
    _arduinoStateSub?.cancel();
    
    _locationTimer?.cancel();
    
    _gt06Client.dispose();
    _gpsService.dispose();
    _arduinoService.dispose();
    
    super.dispose();
  }
}