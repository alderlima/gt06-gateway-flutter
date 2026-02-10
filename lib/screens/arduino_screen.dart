import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:usb_serial/usb_serial.dart';
import '../services/tracker_provider.dart';
import '../services/arduino_service.dart';
import '../models/tracker_state.dart';

/// ============================================================================
/// TELA DO ARDUINO
/// ============================================================================

class ArduinoScreen extends StatefulWidget {
  const ArduinoScreen({super.key});

  @override
  State<ArduinoScreen> createState() => _ArduinoScreenState();
}

class _ArduinoScreenState extends State<ArduinoScreen> {
  final TextEditingController _commandController = TextEditingController();
  List<UsbDevice> _devices = [];
  int _selectedBaudRate = 9600;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _refreshDevices() async {
    setState(() => _isLoading = true);
    final provider = context.read<TrackerProvider>();
    _devices = await provider.arduinoService.listDevices();
    setState(() => _isLoading = false);
  }

  Future<void> _connectArduino(UsbDevice device) async {
    final provider = context.read<TrackerProvider>();
    await provider.arduinoService.connect(device, baudRate: _selectedBaudRate);
  }

  Future<void> _sendCommand() async {
    if (_commandController.text.isEmpty) return;
    
    final provider = context.read<TrackerProvider>();
    await provider.sendToArduino(_commandController.text);
    _commandController.clear();
  }

  Color _getStatusColor(ArduinoStatus status) {
    switch (status) {
      case ArduinoStatus.connected:
        return Colors.green;
      case ArduinoStatus.connecting:
        return Colors.orange;
      case ArduinoStatus.error:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Arduino'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshDevices,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar dispositivos',
          ),
        ],
      ),
      body: Consumer<TrackerProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              // Status Card
              _buildStatusCard(provider),
              
              // Lista de dispositivos ou mensagens
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.isArduinoConnected
                        ? _buildConnectedView(provider)
                        : _buildDeviceList(provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(TrackerProvider provider) {
    final status = provider.arduinoState.status;
    final color = _getStatusColor(status);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withOpacity(0.3), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status == ArduinoStatus.connected
                          ? 'Arduino Conectado'
                          : status == ArduinoStatus.connecting
                              ? 'Conectando...'
                              : 'Desconectado',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (provider.arduinoState.deviceName != null)
                      Text(
                        provider.arduinoState.deviceName!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                        ),
                      ),
                  ],
                ),
              ),
              if (provider.isArduinoConnected)
                ElevatedButton.icon(
                  onPressed: provider.disconnectArduino,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Desconectar'),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => provider.connectArduino(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.usb, size: 18),
                  label: const Text('Auto Conectar'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceList(TrackerProvider provider) {
    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.usb_off,
              size: 64,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum dispositivo USB encontrado',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Conecte o Arduino via cabo OTG',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshDevices,
              icon: const Icon(Icons.refresh),
              label: const Text('Atualizar'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          color: const Color(0xFF161B22),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.usb, color: Colors.orange),
            ),
            title: Text(
              device.productName ?? 'Dispositivo USB',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.manufacturerName ?? 'Fabricante desconhecido',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                Text(
                  'VID: ${device.vid} | PID: ${device.pid}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () => _connectArduino(device),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Conectar'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectedView(TrackerProvider provider) {
    return Column(
      children: [
        // Configuração
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configuração',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _selectedBaudRate,
                    decoration: InputDecoration(
                      labelText: 'Baud Rate',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[800]!),
                      ),
                    ),
                    dropdownColor: const Color(0xFF161B22),
                    style: const TextStyle(color: Colors.white),
                    items: ArduinoService.availableBaudRates.map((rate) {
                      return DropdownMenuItem(
                        value: rate,
                        child: Text('$rate bps'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedBaudRate = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Comandos rápidos
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comandos Rápidos',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildQuickCommandButton('BLOQUEAR', Colors.red),
                      _buildQuickCommandButton('DESBLOQUEAR', Colors.green),
                      _buildQuickCommandButton('STATUS', Colors.blue),
                      _buildQuickCommandButton('POSICAO', Colors.cyan),
                      _buildQuickCommandButton('REINICIAR', Colors.orange),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Envio manual
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            color: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comando Manual',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commandController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Digite o comando...',
                            hintStyle: TextStyle(color: Colors.grey[600]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[800]!),
                            ),
                          ),
                          onSubmitted: (_) => _sendCommand(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _sendCommand,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Mensagens recentes
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: const Color(0xFF161B22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.message, color: Colors.amber),
                        const SizedBox(width: 8),
                        const Text(
                          'Mensagens',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        if (provider.arduinoState.lastMessage.isNotEmpty)
                          Text(
                            'Última: ${_formatTime(provider.arduinoState.lastMessageTime)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: provider.arduinoState.lastMessage.isEmpty
                            ? Text(
                                'Nenhuma mensagem ainda',
                                style: TextStyle(color: Colors.grey[600]),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  provider.arduinoState.lastMessage,
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildQuickCommandButton(String command, Color color) {
    return ActionChip(
      label: Text(
        command,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color.withOpacity(0.3)),
      onPressed: () {
        context.read<TrackerProvider>().sendToArduino('CMD:$command');
      },
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--:--';
    return '${time.hour.toString().padLeft(2, '0')}:''${time.minute.toString().padLeft(2, '0')}:''${time.second.toString().padLeft(2, '0')}';
  }
}
