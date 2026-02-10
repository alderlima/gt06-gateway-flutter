import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:move_to_background/move_to_background.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'services/gt06_service.dart';
import 'package:minimize_app/minimize_app.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Garante permissões críticas para o app não ser morto pelo Android
  await [
    Permission.location,
    Permission.notification,
    Permission.ignoreBatteryOptimizations,
  ].request();

  // Inicializa o serviço que mantém o app vivo em background
  await _configureBackgroundService();

  runApp(const MyApp());
}

Future<void> _configureBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'gt06_service',
      initialNotificationTitle: 'GT06 SERVICE ATIVO',
      initialNotificationContent: 'Monitorando Socket e GPS...',
      foregroundServiceType: AndroidForegroundType.dataSync,
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  // Mantém o processo isolado rodando mesmo com tela apagada
  Timer.periodic(const Duration(seconds: 30), (timer) {
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GT06 Gateway PRO',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[900],
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const ConfigPage(),
    );
  }
}

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final traccarHost = TextEditingController();
  final traccarPort = TextEditingController();
  final imei = TextEditingController();

  GT06Service? service;
  bool traccarConnected = false;
  bool usbConnected = false;
  bool loading = true;
  List<String> logs = [];
  Position? currentPosition;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      final now = DateTime.now();
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      logs.insert(0, "[$timeStr] $msg");
      if (logs.length > 100) logs.removeLast();
    });
  }

  Future<void> _loadConfig() async {
    final p = await SharedPreferences.getInstance();
    traccarHost.text = p.getString('traccarHost') ?? '66.70.144.235';
    traccarPort.text = (p.getInt('traccarPort') ?? 5023).toString();
    imei.text = p.getString('imei') ?? '357152040915004';
    
    _initService();
    setState(() => loading = false);
  }

  void _initService() {
    service?.dispose();
    service = GT06Service(
      traccarHost: traccarHost.text.trim(),
      traccarPort: int.tryParse(traccarPort.text) ?? 5023,
      imei: imei.text.trim(),
      onTraccarStatusChanged: (status) => setState(() => traccarConnected = status),
      onUsbStatusChanged: (status) => setState(() => usbConnected = status),
      onLog: (msg) => _addLog(msg),
      onLocationChanged: (pos) => setState(() => currentPosition = pos),
    );
  }

  Future<void> _toggleTraccar() async {
    if (traccarConnected) {
      service?.dispose();
      _initService();
    } else {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('traccarHost', traccarHost.text.trim());
        await p.setInt('traccarPort', int.tryParse(traccarPort.text) ?? 5023);
        await p.setString('imei', imei.text.trim());
        
        _initService();
        await service!.connectTraccar();
      } catch (e) {
        _addLog("Erro Traccar: $e");
      }
    }
  }

  Future<void> _toggleUsb() async {
    if (usbConnected) {
      service?.disconnectUsb();
    } else {
      bool success = await service!.connectUsb();
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Falha ao conectar USB. Verifique o cabo OTG.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // PopScope impede o fechamento do app pelo botão voltar, apenas minimiza
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        MinimizeApp.minimizeApp(); // Faz a mesma função de forma compatível
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('GT06 TRACKER PRO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(child: _statusTile("SERVIDOR", traccarConnected, Icons.cloud_sync)),
                      const SizedBox(width: 12),
                      Expanded(child: _statusTile("ARDUINO USB", usbConnected, Icons.usb)),
                      const SizedBox(width: 12),
                      Expanded(child: _statusTile("GPS", currentPosition != null, Icons.gps_fixed)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (currentPosition != null)
                    Card(
                      color: Colors.cyan.withOpacity(0.05),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _gpsInfo("LATITUDE", currentPosition!.latitude.toStringAsFixed(6)),
                                _gpsInfo("LONGITUDE", currentPosition!.longitude.toStringAsFixed(6)),
                              ],
                            ),
                            const Divider(height: 24, color: Colors.cyan),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _gpsInfo("VELOCIDADE", "${(currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h"),
                                _gpsInfo("SÉRIE", service?.serial.toString() ?? "0"),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("CONFIGURAÇÃO", style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          _inputField("Host Traccar", traccarHost),
                          _inputField("Porta", traccarPort, isNumber: true),
                          _inputField("IMEI Dispositivo", imei, isNumber: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          traccarConnected ? "PARAR TRACKER" : "INICIAR TRACKER",
                          traccarConnected ? Colors.redAccent : Colors.cyan,
                          _toggleTraccar,
                          traccarConnected ? Icons.stop : Icons.play_arrow,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionButton(
                          usbConnected ? "DESCONECTAR USB" : "CONECTAR USB",
                          usbConnected ? Colors.orangeAccent : Colors.greenAccent,
                          _toggleUsb,
                          Icons.usb,
                        ),
                      ),
                    ],
                  ),
                  
                  // Bloco de logs
                  const SizedBox(height: 20),
                  const Text("LOGS DO SISTEMA", style: TextStyle(color: Colors.grey, fontSize: 10)),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
                    child: ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (c, i) => Text(logs[i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.green)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widgets auxiliares mantendo seu estilo
  Widget _statusTile(String title, bool active, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: active ? Colors.cyan.withOpacity(0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? Colors.cyan : Colors.white24),
      ),
      child: Column(
        children: [
          Icon(icon, color: active ? Colors.cyan : Colors.white38),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _gpsInfo(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _inputField(String label, TextEditingController controller, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed, IconData icon) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
