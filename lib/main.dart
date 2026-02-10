import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gt06_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Capturar erros do Flutter
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
      theme: ThemeData(useMaterial3: true),
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
  bool connected = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
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
      debugPrint("Erro loadConfig: $e");
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
      debugPrint("Erro ao salvar config: $e");
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

    try {
      await _saveConfig();

      service = GT06Service(
        traccarHost: traccarHost.text.trim(),
        traccarPort: tPort,
        arduinoHost: arduinoHost.text.trim(),
        arduinoPort: aPort,
        imei: imei.text.trim(),
      );

      await service!.connect();

      setState(() {
        connected = true;
        loading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Conectado com sucesso!")),
        );
      }
    } catch (e) {
      setState(() => loading = false);
      debugPrint("ERRO AO CONECTAR: $e");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e")),
        );
      }
    }
  }

  void _disconnect() {
    service?.dispose();
    setState(() => connected = false);
  }

  Widget field(String label, TextEditingController c,
      {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('GT06 Gateway'),
        actions: [
          Icon(
            connected ? Icons.link : Icons.link_off,
            color: connected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text("Configurações Traccar", 
                      style: TextStyle(fontWeight: FontWeight.bold)),
                    field('IP Servidor', traccarHost),
                    field('Porta', traccarPort, type: TextInputType.number),
                    field('IMEI do Dispositivo', imei, type: TextInputType.number),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Text("Configurações Arduino", 
                      style: TextStyle(fontWeight: FontWeight.bold)),
                    field('IP Arduino', arduinoHost),
                    field('Porta Arduino', arduinoPort, type: TextInputType.number),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: connected ? Colors.red.shade100 : Colors.blue.shade100,
                ),
                onPressed: connected ? _disconnect : _connect,
                child: Text(connected ? 'DESCONECTAR' : 'CONECTAR AGORA'),
              ),
            ),
            if (connected) ...[
              const SizedBox(height: 20),
              const Divider(),
              const Text("Comandos Rápidos (Arduino)", 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => service?.sendToArduino("ENGINE_STOP"),
                    child: const Text("Bloquear"),
                  ),
                  ElevatedButton(
                    onPressed: () => service?.sendToArduino("ENGINE_RESUME"),
                    child: const Text("Desbloquear"),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}
