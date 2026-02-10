import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gt06_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint("Flutter Error: ${details.exception}");
  };
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GT06 Gateway',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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
  final arduinoHost = TextEditingController();
  final arduinoPort = TextEditingController();
  final imei = TextEditingController();

  GT06Service? service;
  bool traccarConnected = false;
  bool arduinoConnected = false;
  bool loading = true;
  List<String> logs = [];
  final ScrollController _scrollController = ScrollController();

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
      if (logs.length > 50) logs.removeLast();
    });
  }

  Future<void> _loadConfig() async {
    try {
      final p = await SharedPreferences.getInstance();
      traccarHost.text = p.getString('traccarHost') ?? '66.70.144.235';
      traccarPort.text = (p.getInt('traccarPort') ?? 5023).toString();
      arduinoHost.text = p.getString('arduinoHost') ?? '192.168.1.4';
      arduinoPort.text = (p.getInt('arduinoPort') ?? 8080).toString();
      imei.text = p.getString('imei') ?? '357152040915004';
    } catch (e) {
      _addLog("Erro ao carregar configurações: $e");
    }
    setState(() => loading = false);
  }

  Future<void> _saveConfig() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('traccarHost', traccarHost.text.trim());
      int? tPort = int.tryParse(traccarPort.text);
      if (tPort != null) await p.setInt('traccarPort', tPort);
      await p.setString('arduinoHost', arduinoHost.text.trim());
      int? aPort = int.tryParse(arduinoPort.text);
      if (aPort != null) await p.setInt('arduinoPort', aPort);
      await p.setString('imei', imei.text.trim());
    } catch (e) {
      _addLog("Erro ao salvar config: $e");
    }
  }

  Future<void> _connect() async {
    final tPort = int.tryParse(traccarPort.text);
    final aPort = int.tryParse(arduinoPort.text);

    if (tPort == null || aPort == null || imei.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha todos os campos corretamente")),
      );
      return;
    }

    setState(() => loading = true);
    await _saveConfig();

    try {
      service?.dispose();
      service = GT06Service(
        traccarHost: traccarHost.text.trim(),
        traccarPort: tPort,
        arduinoHost: arduinoHost.text.trim(),
        arduinoPort: aPort,
        imei: imei.text.trim(),
        onTraccarStatusChanged: (status) => setState(() => traccarConnected = status),
        onArduinoStatusChanged: (status) => setState(() => arduinoConnected = status),
        onLog: (msg) => _addLog(msg),
      );

      await service!.connect();
      setState(() => loading = false);
    } catch (e) {
      setState(() => loading = false);
      _addLog("ERRO AO CONECTAR: $e");
    }
  }

  void _disconnect() {
    service?.dispose();
    setState(() {
      traccarConnected = false;
      arduinoConnected = false;
    });
    _addLog("Serviços parados pelo usuário");
  }

  Widget field(String label, TextEditingController c, {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: c,
        keyboardType: type,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool anyConnected = traccarConnected || arduinoConnected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GT06 Gateway PRO'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Status das Conexões
                Row(
                  children: [
                    Expanded(
                      child: _statusCard("Traccar", traccarConnected),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _statusCard("Arduino", arduinoConnected),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Configurações
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Configurações", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        field('IP Servidor Traccar', traccarHost),
                        field('Porta Traccar', traccarPort, type: TextInputType.number),
                        field('IMEI do Dispositivo', imei, type: TextInputType.number),
                        const SizedBox(height: 8),
                        field('IP do Arduino', arduinoHost),
                        field('Porta do Arduino', arduinoPort, type: TextInputType.number),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Ações
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: anyConnected ? _disconnect : _connect,
                    icon: Icon(anyConnected ? Icons.stop : Icons.play_arrow),
                    label: Text(anyConnected ? 'DESCONECTAR TUDO' : 'INICIAR GATEWAY'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: anyConnected ? Colors.red.shade100 : Colors.green.shade100,
                      foregroundColor: anyConnected ? Colors.red.shade900 : Colors.green.shade900,
                    ),
                  ),
                ),
                
                if (arduinoConnected) ...[
                  const SizedBox(height: 16),
                  const Text("Comandos Diretos", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => service?.sendToArduino("ENGINE_STOP"),
                          icon: const Icon(Icons.block, color: Colors.red),
                          label: const Text("BLOQUEAR"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => service?.sendToArduino("ENGINE_RESUME"),
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          label: const Text("LIBERAR"),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // Terminal de Logs
          Container(
            height: 180,
            width: double.infinity,
            color: Colors.black87,
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("LOGS DO SISTEMA", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                    Icon(Icons.terminal, color: Colors.green, size: 14),
                  ],
                ),
                const Divider(color: Colors.green, height: 8),
                Expanded(
                  child: ListView.builder(
                    reverse: false,
                    itemCount: logs.length,
                    itemBuilder: (context, index) => Text(
                      logs[index],
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
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

  Widget _statusCard(String title, bool isConnected) {
    return Card(
      color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            Icon(
              isConnected ? Icons.check_circle : Icons.error,
              color: isConnected ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isConnected ? Colors.green.shade900 : Colors.red.shade900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
