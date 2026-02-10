import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'services/gt06_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GT06Service.initializeService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GT06 Tracker PRO',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
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

  final GT06Service service = GT06Service();
  bool isServiceRunning = false;
  bool usbConnected = false;
  List<String> logs = [];
  double? lat, lon;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _listenToService();
  }

  void _listenToService() {
    FlutterBackgroundService().on('update').listen((event) {
      if (mounted) {
        setState(() {
          lat = event?['latitude'];
          lon = event?['longitude'];
          isServiceRunning = true;
        });
      }
    });

    FlutterBackgroundService().on('log').listen((event) {
      if (mounted) _addLog(event?['message'] ?? "");
    });

    Timer.periodic(const Duration(seconds: 2), (timer) async {
      final running = await FlutterBackgroundService().isRunning();
      if (mounted && isServiceRunning != running) {
        setState(() => isServiceRunning = running);
      }
    });
  }

  void _addLog(String msg) {
    if (msg.isEmpty) return;
    setState(() {
      final time = DateTime.now().toString().split(' ')[1].split('.')[0];
      logs.insert(0, "[$time] $msg");
      if (logs.length > 50) logs.removeLast();
    });
  }

  Future<void> _loadConfig() async {
    final p = await SharedPreferences.getInstance();
    traccarHost.text = p.getString('traccarHost') ?? '66.70.144.235';
    traccarPort.text = (p.getInt('traccarPort') ?? 5023).toString();
    imei.text = p.getString('imei') ?? '357152040915004';
    
    service.onUsbStatusChanged = (status) => setState(() => usbConnected = status);
    service.onLog = (msg) => _addLog(msg);
  }

  Future<void> _saveConfig() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('traccarHost', traccarHost.text.trim());
    await p.setInt('traccarPort', int.tryParse(traccarPort.text) ?? 5023);
    await p.setString('imei', imei.text.trim());
  }

  Future<void> _toggleService() async {
    if (isServiceRunning) {
      await service.stopTracking();
    } else {
      // Verificar permissões antes de iniciar
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        await _saveConfig();
        await service.startTracking();
      } else {
        _addLog("Permissão de localização necessária");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('GT06 TRACKER PRO V2'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    _statusBox("TRACKER", isServiceRunning, Icons.location_on),
                    const SizedBox(width: 10),
                    _statusBox("USB", usbConnected, Icons.usb),
                  ],
                ),
                const SizedBox(height: 20),
                if (lat != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text("Lat: $lat | Lon: $lon", style: const TextStyle(fontFamily: 'monospace')),
                    ),
                  ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _textField("Host", traccarHost),
                        _textField("Porta", traccarPort, isNum: true),
                        _textField("IMEI", imei, isNum: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _toggleService,
                        icon: Icon(isServiceRunning ? Icons.stop : Icons.play_arrow),
                        label: Text(isServiceRunning ? "PARAR" : "INICIAR"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isServiceRunning ? Colors.red.withOpacity(0.2) : Colors.cyan.withOpacity(0.2),
                          foregroundColor: isServiceRunning ? Colors.red : Colors.cyan,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => usbConnected ? service.disconnectUsb() : service.connectUsb(),
                        icon: const Icon(Icons.usb),
                        label: Text(usbConnected ? "DESCONECTAR" : "CONECTAR"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: usbConnected ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                          foregroundColor: usbConnected ? Colors.orange : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                if (usbConnected) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: _testBtn("BLOQUEAR", Colors.red, "ENGINE_STOP")),
                      const SizedBox(width: 10),
                      Expanded(child: _testBtn("LIBERAR", Colors.green, "ENGINE_RESUME")),
                    ],
                  ),
                ]
              ],
            ),
          ),
          Container(
            height: 150,
            color: Colors.grey[900],
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              itemBuilder: (c, i) => Text(logs[i], style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace')),
            ),
          )
        ],
      ),
    );
  }

  Widget _statusBox(String title, bool on, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: on ? Colors.cyan : Colors.grey),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: on ? Colors.cyan : Colors.grey),
            Text(title, style: const TextStyle(fontSize: 10)),
            Text(on ? "ON" : "OFF", style: TextStyle(fontWeight: FontWeight.bold, color: on ? Colors.green : Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController controller, {bool isNum = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  Widget _testBtn(String label, Color color, String cmd) {
    return OutlinedButton(
      onPressed: () => service.sendToArduino(cmd),
      style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
      child: Text(label),
    );
  }
}
