import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gt06_service.dart';

Future<void> main() async {
  // OBRIGATÓRIO EM RELEASE
  WidgetsFlutterBinding.ensureInitialized();
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
    final p = await SharedPreferences.getInstance();
    await p.setString('traccarHost', traccarHost.text.trim());
    await p.setInt('traccarPort', int.parse(traccarPort.text));
    await p.setString('arduinoHost', arduinoHost.text.trim());
    await p.setInt('arduinoPort', int.parse(arduinoPort.text));
    await p.setString('imei', imei.text.trim());
  }

  Future<void> _connect() async {
    try {
      await _saveConfig();

      service = GT06Service(
        traccarHost: traccarHost.text.trim(),
        traccarPort: int.parse(traccarPort.text),
        arduinoHost: arduinoHost.text.trim(),
        arduinoPort: int.parse(arduinoPort.text),
        imei: imei.text.trim(),
      );

      await service!.connect();

      setState(() => connected = true);
    } catch (e) {
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
      appBar: AppBar(title: const Text('GT06 Gateway')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            field('Traccar IP', traccarHost),
            field('Traccar Porta', traccarPort,
                type: TextInputType.number),
            field('Arduino IP', arduinoHost),
            field('Arduino Porta', arduinoPort,
                type: TextInputType.number),
            field('IMEI', imei, type: TextInputType.number),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: connected ? _disconnect : _connect,
              child: Text(connected ? 'Desconectar' : 'Conectar'),
            ),
          ],
        ),
      ),
    );
  }
}
