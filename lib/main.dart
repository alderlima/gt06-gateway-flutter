import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Teste OK')),
        body: const Center(
          child: Text(
            'App abriu com sucesso ✅',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}
