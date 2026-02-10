import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/tracker_provider.dart';

/// ============================================================================
/// TELA DE CONFIGURAÇÃO
/// ============================================================================

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late TextEditingController _serverController;
  late TextEditingController _portController;
  late TextEditingController _imeiController;
  late TextEditingController _heartbeatController;
  late TextEditingController _locationController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<TrackerProvider>();
    _serverController = TextEditingController(text: provider.config.serverAddress);
    _portController = TextEditingController(text: provider.config.serverPort.toString());
    _imeiController = TextEditingController(text: provider.config.imei);
    _heartbeatController = TextEditingController(text: provider.config.heartbeatInterval.toString());
    _locationController = TextEditingController(text: provider.config.locationInterval.toString());
  }

  @override
  void dispose() {
    _serverController.dispose();
    _portController.dispose();
    _imeiController.dispose();
    _heartbeatController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _saveConfig() {
    final provider = context.read<TrackerProvider>();
    provider.updateConfig(
      serverAddress: _serverController.text.trim(),
      serverPort: int.tryParse(_portController.text) ?? 5023,
      imei: _imeiController.text.trim(),
      heartbeatInterval: int.tryParse(_heartbeatController.text) ?? 30,
      locationInterval: int.tryParse(_locationController.text) ?? 10,
    );
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configurações salvas!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Configuração'),
        elevation: 0,
      ),
      body: Consumer<TrackerProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Seção Servidor
                _buildSectionTitle('Servidor Traccar'),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _serverController,
                  label: 'Endereço do Servidor',
                  hint: 'ex: traccar.seudominio.com',
                  icon: Icons.dns,
                  enabled: !provider.isConnected,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _portController,
                  label: 'Porta TCP',
                  hint: '5023',
                  icon: Icons.settings_ethernet,
                  keyboardType: TextInputType.number,
                  enabled: !provider.isConnected,
                ),
                
                const SizedBox(height: 32),
                
                // Seção Dispositivo
                _buildSectionTitle('Dispositivo'),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _imeiController,
                  label: 'IMEI',
                  hint: '15 dígitos',
                  icon: Icons.perm_device_info,
                  keyboardType: TextInputType.number,
                  maxLength: 15,
                  enabled: !provider.isConnected,
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _imeiController.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('IMEI copiado!')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 20),
                      ),
                      IconButton(
                        onPressed: provider.isConnected 
                            ? null 
                            : () {
                                provider.generateNewIMEI();
                                setState(() {
                                  _imeiController.text = provider.config.imei;
                                });
                              },
                        icon: const Icon(Icons.refresh, size: 20),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Seção Intervalos
                _buildSectionTitle('Intervalos'),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _heartbeatController,
                  label: 'Heartbeat (segundos)',
                  hint: '30',
                  icon: Icons.favorite,
                  keyboardType: TextInputType.number,
                  helperText: 'Intervalo para manter conexão ativa',
                  enabled: !provider.isConnected,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _locationController,
                  label: 'Envio de Posição (segundos)',
                  hint: '10',
                  icon: Icons.location_on,
                  keyboardType: TextInputType.number,
                  helperText: 'Intervalo para enviar coordenadas GPS',
                  enabled: !provider.isConnected,
                ),
                
                const SizedBox(height: 32),
                
                // Informações
                _buildInfoCard(),
                
                const SizedBox(height: 32),
                
                // Botão Salvar
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: provider.isConnected ? null : _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyan,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      disabledBackgroundColor: Colors.grey[800],
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text(
                      'SALVAR CONFIGURAÇÕES',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.cyan,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool enabled = true,
    String? helperText,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: TextStyle(
        color: enabled ? Colors.white : Colors.grey,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        labelStyle: TextStyle(color: Colors.grey[400]),
        hintStyle: TextStyle(color: Colors.grey[600]),
        helperStyle: TextStyle(color: Colors.grey[500]),
        counterStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: Colors.cyan),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF161B22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[800]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[800]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.cyan),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[900]!),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Colors.cyan),
                const SizedBox(width: 8),
                const Text(
                  'Como Configurar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoItem('1.', 'Informe o endereço IP ou domínio do seu servidor Traccar'),
            _buildInfoItem('2.', 'Use a porta 5023 para protocolo GT06'),
            _buildInfoItem('3.', 'O IMEI deve ter exatamente 15 dígitos'),
            _buildInfoItem('4.', 'No Traccar, cadastre o dispositivo com o mesmo IMEI'),
            _buildInfoItem('5.', 'Selecione o modelo "GT06" ou "Concox" no Traccar'),
            _buildInfoItem('6.', 'Clique em CONECTAR na tela principal'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: const TextStyle(
              color: Colors.cyan,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
