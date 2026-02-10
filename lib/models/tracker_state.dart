import 'dart:typed_data';

/// Estado do Rastreador GT06
enum TrackerStatus {
  disconnected,
  connecting,
  connected,
  loggingIn,
  online,
  error,
}

/// Posição GPS
class GpsPosition {
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double heading;
  final double accuracy;
  final DateTime timestamp;
  final bool isValid;

  GpsPosition({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.accuracy,
    required this.timestamp,
    this.isValid = true,
  });

  factory GpsPosition.invalid() => GpsPosition(
    latitude: 0,
    longitude: 0,
    altitude: 0,
    speed: 0,
    heading: 0,
    accuracy: 0,
    timestamp: DateTime.now(),
    isValid: false,
  );

  @override
  String toString() => 
    'GpsPosition(lat: ${latitude.toStringAsFixed(6)}, '
    'lon: ${longitude.toStringAsFixed(6)}, '
    'speed: ${speed.toStringAsFixed(1)} km/h)';
}

/// Comando recebido do servidor
class ServerCommand {
  final String rawCommand;
  final String commandType;
  final String description;
  final DateTime receivedAt;
  final bool acknowledged;

  ServerCommand({
    required this.rawCommand,
    required this.commandType,
    required this.description,
    required this.receivedAt,
    this.acknowledged = false,
  });

  ServerCommand copyWith({bool? acknowledged}) => ServerCommand(
    rawCommand: rawCommand,
    commandType: commandType,
    description: description,
    receivedAt: receivedAt,
    acknowledged: acknowledged ?? this.acknowledged,
  );
}

/// Log entry
class LogEntry {
  final DateTime timestamp;
  final LogType type;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.type,
    required this.message,
    this.details,
  });
}

enum LogType {
  info,
  success,
  warning,
  error,
  sent,
  received,
  command,
  gps,
  arduino,
}

/// Configuração do rastreador
class TrackerConfig {
  String serverAddress;
  int serverPort;
  String imei;
  int heartbeatInterval;
  int locationInterval;
  bool autoConnect;
  String protocol;

  TrackerConfig({
    this.serverAddress = '',
    this.serverPort = 5023,
    this.imei = '',
    this.heartbeatInterval = 30,
    this.locationInterval = 10,
    this.autoConnect = false,
    this.protocol = 'GT06',
  });

  Map<String, dynamic> toJson() => {
    'serverAddress': serverAddress,
    'serverPort': serverPort,
    'imei': imei,
    'heartbeatInterval': heartbeatInterval,
    'locationInterval': locationInterval,
    'autoConnect': autoConnect,
    'protocol': protocol,
  };

  factory TrackerConfig.fromJson(Map<String, dynamic> json) => TrackerConfig(
    serverAddress: json['serverAddress'] ?? '',
    serverPort: json['serverPort'] ?? 5023,
    imei: json['imei'] ?? '',
    heartbeatInterval: json['heartbeatInterval'] ?? 30,
    locationInterval: json['locationInterval'] ?? 10,
    autoConnect: json['autoConnect'] ?? false,
    protocol: json['protocol'] ?? 'GT06',
  );
}

/// Estatísticas do rastreador
class TrackerStats {
  int packetsSent;
  int packetsReceived;
  int heartbeatsSent;
  int locationsSent;
  int commandsReceived;
  DateTime? connectedSince;
  DateTime? lastActivity;

  TrackerStats({
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.heartbeatsSent = 0,
    this.locationsSent = 0,
    this.commandsReceived = 0,
    this.connectedSince,
    this.lastActivity,
  });

  void reset() {
    packetsSent = 0;
    packetsReceived = 0;
    heartbeatsSent = 0;
    locationsSent = 0;
    commandsReceived = 0;
    connectedSince = null;
    lastActivity = null;
  }
}

/// Estado do Arduino
enum ArduinoStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Dados do Arduino
class ArduinoState {
  final ArduinoStatus status;
  final String? deviceName;
  final int baudRate;
  final String lastMessage;
  final DateTime? lastMessageTime;

  ArduinoState({
    this.status = ArduinoStatus.disconnected,
    this.deviceName,
    this.baudRate = 9600,
    this.lastMessage = '',
    this.lastMessageTime,
  });

  ArduinoState copyWith({
    ArduinoStatus? status,
    String? deviceName,
    int? baudRate,
    String? lastMessage,
    DateTime? lastMessageTime,
  }) => ArduinoState(
    status: status ?? this.status,
    deviceName: deviceName ?? this.deviceName,
    baudRate: baudRate ?? this.baudRate,
    lastMessage: lastMessage ?? this.lastMessage,
    lastMessageTime: lastMessageTime ?? this.lastMessageTime,
  );
}
