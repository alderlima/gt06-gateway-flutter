import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/tracker_state.dart';

/// ============================================================================
/// SERVIÇO DE GPS
/// ============================================================================
/// 
/// Gerencia a localização do dispositivo usando o GPS do celular.
/// Fornece posições em tempo real para envio ao servidor Traccar.
/// ============================================================================

class GpsService {
  // Stream de posição
  StreamSubscription<Position>? _positionStream;
  
  // Stream controller
  final StreamController<GpsPosition> _positionController = StreamController<GpsPosition>.broadcast();
  final StreamController<String> _statusController = StreamController<String>.broadcast();
  
  // Estado
  bool _isTracking = false;
  GpsPosition? _lastPosition;
  
  // Configuração
  LocationSettings? _locationSettings;
  
  // Getters
  bool get isTracking => _isTracking;
  GpsPosition? get lastPosition => _lastPosition;
  Stream<GpsPosition> get positionStream => _positionController.stream;
  Stream<String> get statusStream => _statusController.stream;

  /// ==========================================================================
  /// PERMISSÕES
  /// ==========================================================================

  /// Verifica e solicita permissões de localização
  Future<bool> checkPermissions() async {
    // Verifica se o serviço de localização está habilitado
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _statusController.add('Serviço de GPS desabilitado');
      return false;
    }
    
    // Verifica permissão
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _statusController.add('Permissão de localização negada');
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      _statusController.add('Permissão de localização negada permanentemente');
      return false;
    }
    
    return true;
  }

  /// ==========================================================================
  /// RASTREAMENTO
  /// ==========================================================================

  /// Inicia rastreamento de localização
  Future<bool> startTracking({
    int intervalSeconds = 10,
    int distanceFilter = 0,  // metros
    bool highAccuracy = true,
  }) async {
    if (_isTracking) return true;
    
    // Verifica permissões
    final hasPermission = await checkPermissions();
    if (!hasPermission) return false;
    
    // Configura settings baseado na plataforma
    if (highAccuracy) {
      _locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        forceLocationManager: false,
        intervalDuration: Duration(seconds: intervalSeconds),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Rastreador GT06 está ativo',
          notificationTitle: 'Serviço de Rastreamento',
          enableWakeLock: true,
        ),
      );
    } else {
      _locationSettings = LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: distanceFilter,
      );
    }
    
    try {
      // Inicia stream de posição
      _positionStream = Geolocator.getPositionStream(
        locationSettings: _locationSettings,
      ).listen(
        _onPositionUpdate,
        onError: _onPositionError,
      );
      
      _isTracking = true;
      _statusController.add('Rastreamento iniciado');
      
      // Pega posição atual imediatamente
      await getCurrentPosition();
      
      return true;
      
    } catch (e) {
      _statusController.add('Erro ao iniciar rastreamento: $e');
      return false;
    }
  }

  /// Para rastreamento
  Future<void> stopTracking() async {
    await _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    _statusController.add('Rastreamento parado');
  }

  /// Obtém posição atual única
  Future<GpsPosition?> getCurrentPosition() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) return null;
    
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final gpsPosition = _convertPosition(position);
      _lastPosition = gpsPosition;
      _positionController.add(gpsPosition);
      
      return gpsPosition;
      
    } catch (e) {
      _statusController.add('Erro ao obter posição: $e');
      return null;
    }
  }

  /// ==========================================================================
  /// HANDLERS
  /// ==========================================================================

  void _onPositionUpdate(Position position) {
    final gpsPosition = _convertPosition(position);
    _lastPosition = gpsPosition;
    _positionController.add(gpsPosition);
  }

  void _onPositionError(error) {
    _statusController.add('Erro de GPS: $error');
  }

  /// ==========================================================================
  /// CONVERSÃO
  /// ==========================================================================

  GpsPosition _convertPosition(Position position) {
    return GpsPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      speed: position.speed * 3.6,  // m/s para km/h
      heading: position.heading,
      accuracy: position.accuracy,
      timestamp: position.timestamp ?? DateTime.now(),
      isValid: position.accuracy < 100,  // Considera válido se precisão < 100m
    );
  }

  /// ==========================================================================
  /// UTILIDADES
  /// ==========================================================================

  /// Calcula distância entre duas posições (em metros)
  static double calculateDistance(GpsPosition pos1, GpsPosition pos2) {
    return Geolocator.distanceBetween(
      pos1.latitude,
      pos1.longitude,
      pos2.latitude,
      pos2.longitude,
    );
  }

  /// Verifica se a posição é válida
  static bool isValidPosition(GpsPosition position) {
    return position.isValid && 
           position.latitude != 0 && 
           position.longitude != 0 &&
           position.accuracy < 100;
  }

  /// Formata coordenadas para exibição
  static String formatCoordinates(double latitude, double longitude) {
    final latDir = latitude >= 0 ? 'N' : 'S';
    final lonDir = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(6)}° $latDir, ${longitude.abs().toStringAsFixed(6)}° $lonDir';
  }

  /// Libera recursos
  void dispose() {
    stopTracking();
    _positionController.close();
    _statusController.close();
  }
}
