import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gt06_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
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
    
    // Inicializar serviço sem conectar
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
    );
  }

  Future<void> _toggleTraccar() async {
    if (traccarConnected) {
      service?.dispose();
      _initService(); // Reiniciar para próxima conexão
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('GT06 USB GATEWAY', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
                // Status Section
                Row(
                  children: [
                    Expanded(child: _statusTile("TRACCAR", traccarConnected, Icons.cloud_sync)),
                    const SizedBox(width: 12),
                    Expanded(child: _statusTile("ARDUINO USB", usbConnected, Icons.usb)),
                  ],
                ),
                const SizedBox(height: 20),

                // Config Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("CONFIGURAÇÃO SERVIDOR", style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
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
                        traccarConnected ? "PARAR TRACCAR" : "INICIAR TRACCAR",
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
                  const Text("TESTES DE COMANDO (USB 9600)", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _testButton("BLOQUEAR", Colors.red, () => service?.sendToArduino("ENGINE_STOP")),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _testButton("LIBERAR", Colors.green, () => service?.sendToArduino("ENGINE_RESUME")),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Terminal Log
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              border: Border(top: BorderSide(color: Colors.cyan.withOpacity(0.3), width: 2)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Colors.black,
                  child: const Row(
                    children: [
                      Icon(Icons.terminal, color: Colors.cyan, size: 16),
                      SizedBox(width: 8),
                      Text("CONSOLE LOGS", style: TextStyle(color: Colors.cyan, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: logs.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        logs[index],
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTile(String label, bool active, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? Colors.cyan.withOpacity(0.1) : Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? Colors.cyan : Colors.grey[800]!),
      ),
      child: Column(
        children: [
          Icon(icon, color: active ? Colors.cyan : Colors.grey[600]),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: active ? Colors.cyan : Colors.grey[600])),
          Text(active ? "ONLINE" : "OFFLINE", style: TextStyle(fontWeight: FontWeight.bold, color: active ? Colors.greenAccent : Colors.redAccent)),
        ],
      ),
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
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
          isDense: true,
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[800]!)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyan)),
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
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _testButton(String label, Color color, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
