// Nota: apesar do tipo react para preview, este arquivo é Flutter/Dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gt06_service.dart';

void main() {
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    traccarHost.text = p.getString('traccarHost') ?? '66.70.144.235';
    traccarPort.text = p.getInt('traccarPort')?.toString() ?? '5023';
    arduinoHost.text = p.getString('arduinoHost') ?? '192.168.1.4';
    arduinoPort.text = p.getInt('arduinoPort')?.toString() ?? '8080';
    imei.text = p.getString('imei') ?? '357152040915004';
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('traccarHost', traccarHost.text);
    await p.setInt('traccarPort', int.parse(traccarPort.text));
    await p.setString('arduinoHost', arduinoHost.text);
    await p.setInt('arduinoPort', int.parse(arduinoPort.text));
    await p.setString('imei', imei.text);
  }

  Future<void> _connect() async {
    await _save();

    service = GT06Service(
      traccarHost: traccarHost.text,
      traccarPort: int.parse(traccarPort.text),
      arduinoHost: arduinoHost.text,
      arduinoPort: int.parse(arduinoPort.text),
      imei: imei.text,
    );

    await service!.connect();

    setState(() => connected = true);
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
