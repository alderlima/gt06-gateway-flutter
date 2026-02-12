import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'services/gt06_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _requestLocationPermission();
  await _startForegroundService();

  runApp(const MyApp());
}

Future<void> _requestLocationPermission() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.whileInUse) {
    await Geolocator.requestPermission();
  }
}

Future<void> _startForegroundService() async {
  try {
    const platform = MethodChannel('com.example.gt06_gateway/service');
    await platform.invokeMethod('startForegroundService');
  } catch (e) {
    debugPrint("Erro ao iniciar foreground service: $e");
  }
}

Future<void> _stopForegroundService() async {
  try {
    const platform = MethodChannel('com.example.gt06_gateway/service');
    await platform.invokeMethod('stopForegroundService');
  } catch (e) {
    debugPrint("Erro ao parar foreground service: $e");
  }
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
        // Mantido CardThemeData conforme solicitado
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

class _ConfigPageState extends State<ConfigPage> with WidgetsBindingObserver {
  final traccarHost = TextEditingController();
  final traccarPort = TextEditingController();
  final imei = TextEditingController();

  GT06Service? service;
  bool traccarConnected = false;
  bool usbConnected = false;
  bool loading = true;
  bool appInBackground = false;
  List<String> logs = [];
  Position? currentPosition;

  static const platformNav = MethodChannel('com.example.gt06_gateway/navigation');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfig();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    service?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      appInBackground = state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive;
    });
    if (state == AppLifecycleState.paused) {
      _addLog("App em background - mantendo conexões ativas");
    } else if (state == AppLifecycleState.resumed) {
      _addLog("App em foreground");
    }
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      final now = DateTime.now();
      final timeStr =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      final bgIndicator = appInBackground ? "[BG] " : "";
      logs.insert(0, "[$timeStr] $bgIndicator$msg");
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
          const SnackBar(
              content:
                  Text("Falha ao conectar USB. Verifique o cabo OTG.")),
        );
      }
    }
  }

  // Botão para sair do aplicativo completamente (encerra processo)
  Future<void> _exitApp() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Encerrar aplicativo"),
        content: const Text(
            "Todas as conexões serão finalizadas. Deseja sair?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("SAIR", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _addLog("Encerrando aplicativo...");
      service?.dispose(); // sem await, método void
      await _stopForegroundService();
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return WillPopScope(
      onWillPop: () async {
        // Botão voltar: minimiza o app, não fecha
        _addLog("⬅️ Botão voltar pressionado – movendo para background");
        try {
          await platformNav.invokeMethod('moveToBackground');
        } catch (e) {
          _addLog("Erro ao mover para background: $e");
        }
        // Retorna false para impedir o fechamento padrão
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('GT06 TRACKER PRO',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              if (appInBackground)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: const Text(
                    'BACKGROUND',
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: 8,
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              onPressed: _exitApp,
              tooltip: "Encerrar aplicativo",
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Status Section
                  Row(
                    children: [
                      Expanded(
                          child: _statusTile(
                              "SERVIDOR", traccarConnected, Icons.cloud_sync)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statusTile(
                              "ARDUINO USB", usbConnected, Icons.usb)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statusTile("GPS", currentPosition != null,
                              Icons.gps_fixed)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // GPS Data Card
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
                                _gpsInfo("LATITUDE",
                                    currentPosition!.latitude.toStringAsFixed(6)),
                                _gpsInfo("LONGITUDE",
                                    currentPosition!.longitude.toStringAsFixed(6)),
                              ],
                            ),
                            const Divider(height: 24, color: Colors.cyan),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _gpsInfo(
                                    "VELOCIDADE",
                                    "${(currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h"),
                                _gpsInfo("SÉRIE",
                                    service?.serial.toString() ?? "0"),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Config Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("CONFIGURAÇÃO",
                              style: TextStyle(
                                  color: Colors.cyan,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          _inputField("Host Traccar", traccarHost),
                          _inputField("Porta", traccarPort, isNumber: true),
                          _inputField("IMEI Dispositivo", imei, isNumber: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Control Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          traccarConnected
                              ? "PARAR TRACKER"
                              : "INICIAR TRACKER",
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

                  if (usbConnected) ...[
                    const SizedBox(height: 24),
                    const Text("TESTES DE COMANDO (USB 9600)",
                        style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _testButton("BLOQUEAR", Colors.red,
                              () => service?.sendToArduino("ENGINE_STOP")),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _testButton("LIBERAR", Colors.green,
                              () => service?.sendToArduino("ENGINE_RESUME")),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Terminal Log
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: Border(
                    top: BorderSide(
                        color: Colors.cyan.withOpacity(0.3), width: 2)),
              ),
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Colors.black,
                    child: Row(
                      children: [
                        const Icon(Icons.terminal,
                            color: Colors.cyan, size: 16),
                        const SizedBox(width: 8),
                        const Text("CONSOLE LOGS",
                            style: TextStyle(
                                color: Colors.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(
                          appInBackground ? "[BACKGROUND]" : "[FOREGROUND]",
                          style: TextStyle(
                              color: appInBackground
                                  ? Colors.amber
                                  : Colors.green,
                              fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          logs[index],
                          style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontFamily: 'monospace'),
                        ),
                      ),
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

  Widget _gpsInfo(String label, String value) => Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
        ],
      );

  Widget _statusTile(String label, bool active, IconData icon) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? Colors.cyan.withOpacity(0.1) : Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? Colors.cyan : Colors.grey[800]!),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: active ? Colors.cyan : Colors.grey[600], size: 18),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: active ? Colors.cyan : Colors.grey[600])),
            Text(active ? "ON" : "OFF",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.greenAccent : Colors.redAccent)),
          ],
        ),
      );

  Widget _inputField(String label, TextEditingController controller,
          {bool isNumber = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType:
              isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
            isDense: true,
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey[800]!)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.cyan)),
          ),
        ),
      );

  Widget _actionButton(String label, Color color, VoidCallback onPressed,
          IconData icon) =>
      ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.15),
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

  Widget _testButton(String label, Color color, VoidCallback onPressed) =>
      OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );
}