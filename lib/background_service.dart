import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'gt06_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'gt06_channel',
      initialNotificationTitle: 'GT06 Tracker',
      initialNotificationContent: 'Rastreamento em andamento',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Carregar configurações
  final prefs = await SharedPreferences.getInstance();
  final traccarHost = prefs.getString('traccarHost') ?? '66.70.144.235';
  final traccarPort = prefs.getInt('traccarPort') ?? 5023;
  final imei = prefs.getString('imei') ?? '357152040915004';

  // Inicializar o serviço GT06
  final gt06Service = GT06Service(
    traccarHost: traccarHost,
    traccarPort: traccarPort,
    imei: imei,
    onLog: (msg) {
      // Enviar logs para a UI via event stream
      service.invoke('log', {'message': msg});
    },
    onLocationChanged: (position) {
      // Enviar localização para a UI
      service.invoke('location', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'speed': position.speed,
        'heading': position.heading,
      });
    },
  );

  // Conectar ao Traccar
  try {
    await gt06Service.connectTraccar();
  } catch (e) {
    service.invoke('log', {'message': 'Erro ao conectar Traccar: $e'});
  }

  // Manter o serviço ativo
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Atualizar notificação para manter o serviço em primeiro plano
        service.setForegroundNotificationInfo(
          title: "GT06 Tracker",
          content: "Rastreamento ativo",
        );
      }
    }

    // Verificar se o serviço deve parar
    if (!(await service.isRunning())) {
      timer.cancel();
      gt06Service.dispose();
    }
  });
}