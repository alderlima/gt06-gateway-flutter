import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/tracker_provider.dart';
import '../models/tracker_state.dart';
import 'config_screen.dart';
import 'logs_screen.dart';
import 'arduino_screen.dart';

/// ============================================================================
/// TELA PRINCIPAL - Dashboard do Rastreador
/// ============================================================================

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Consumer<TrackerProvider>(
          builder: (context, provider, child) {
            return CustomScrollView(
              slivers: [
                // App Bar
                SliverToBoxAdapter(
                  child: _buildHeader(context, provider),
                ),
                
                // Status Card
                SliverToBoxAdapter(
                  child: _buildStatusCard(context, provider),
                ),
                
                // Estatísticas
                SliverToBoxAdapter(
                  child: _buildStatsCard(context, provider),
                ),
                
                // GPS Info
                SliverToBoxAdapter(
                  child: _buildGpsCard(context, provider),
                ),
                
                // Botões de Ação
                SliverToBoxAdapter(
                  child: _buildActionButtons(context, provider),
                ),
                
                // Logs Preview
                SliverToBoxAdapter(
                  child: _buildLogsPreview(context, provider),
                ),
                
                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  /// ==========================================================================
  /// HEADER
  /// ==========================================================================

  Widget _buildHeader(BuildContext context, TrackerProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.cyan, Colors.blue],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.gps_fixed,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rastreador GT06',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'IMEI: ${provider.config.imei}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showImeiOptions(context, provider),
            icon: const Icon(Icons.edit, color: Colors.cyan),
          ),
        ],
      ),
    );
  }

  void _showImeiOptions(BuildContext context, TrackerProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Opções do IMEI',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.cyan),
              title: const Text('Gerar Novo IMEI', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                'Gera um IMEI aleatório válido',
                style: TextStyle(color: Colors.grey[400]),
              ),
              onTap: () {
                provider.generateNewIMEI();
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.orange),
              title: const Text('Editar IMEI Manualmente', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                'Digite um IMEI específico',
                style: TextStyle(color: Colors.grey[400]),
              ),
              onTap: () {
                Navigator.pop(context);
                _showEditImeiDialog(context, provider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.green),
              title: const Text('Copiar IMEI', style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: provider.config.imei));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('IMEI copiado!')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditImeiDialog(BuildContext context, TrackerProvider provider) {
    final controller = TextEditingController(text: provider.config.imei);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Editar IMEI', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.number,
          maxLength: 15,
          decoration: InputDecoration(
            hintText: 'Digite 15 dígitos',
            hintStyle: TextStyle(color: Colors.grey[500]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            counterStyle: TextStyle(color: Colors.grey[400]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final imei = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
              if (imei.length == 15) {
                provider.updateConfig(imei: imei);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('IMEI deve ter 15 dígitos')),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  /// ==========================================================================
  /// STATUS CARD
  /// ==========================================================================

  Widget _buildStatusCard(BuildContext context, TrackerProvider provider) {
    // Usa os getters do provider para cor e ícone
    final statusColor = provider.statusColor;
    final statusIcon = provider.statusIcon;
    
    // Determina se deve mostrar botão de conectar ou desconectar
    final bool showDisconnect = provider.isConnecting || provider.isOnline;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        color: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: statusColor.withOpacity(0.3), width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Status Indicator
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 3),
                ),
                child: Icon(
                  statusIcon,
                  size: 40,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                provider.statusText,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                provider.isOnline 
                    ? 'Conectado a ${provider.config.serverAddress}:${provider.config.serverPort}'
                    : provider.isConnecting
                        ? 'Estabelecendo conexão...'
                        : 'Aguardando conexão',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              
              // Botão Conectar/Desconectar
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: showDisconnect
                      ? provider.disconnect
                      : provider.connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: showDisconnect ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                  ),
                  icon: Icon(
                    showDisconnect ? Icons.stop : Icons.play_arrow,
                    size: 28,
                  ),
                  label: Text(
                    showDisconnect ? 'DESCONECTAR' : 'CONECTAR',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ==========================================================================
  /// ESTATÍSTICAS
  /// ==========================================================================

  Widget _buildStatsCard(BuildContext context, TrackerProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        color: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics, color: Colors.cyan),
                  const SizedBox(width: 8),
                  const Text(
                    'Estatísticas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  // Indicador de conexão Arduino
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: provider.isArduinoConnected ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    provider.isArduinoConnected ? 'Arduino OK' : 'Arduino Off',
                    style: TextStyle(
                      fontSize: 12,
                      color: provider.isArduinoConnected ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.favorite,
                      label: 'Heartbeats',
                      value: provider.stats.heartbeatsSent.toString(),
                      color: Colors.pink,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.location_on,
                      label: 'Posições',
                      value: provider.stats.locationsSent.toString(),
                      color: Colors.green,
                    ),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      icon: Icons.gamepad,
                      label: 'Comandos',
                      value: provider.stats.commandsReceived.toString(),
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
        ),
      ],
    );
  }

  /// ==========================================================================
  /// GPS CARD
  /// ==========================================================================

  Widget _buildGpsCard(BuildContext context, TrackerProvider provider) {
    final position = provider.currentPosition;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        color: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.gps_fixed, color: Colors.green),
                  const SizedBox(width: 8),
                  const Text(
                    'Localização GPS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: position?.isValid == true ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (position != null && position.isValid) ...[
                _buildGpsRow('Latitude:', position.latitude.toStringAsFixed(6)),
                _buildGpsRow('Longitude:', position.longitude.toStringAsFixed(6)),
                _buildGpsRow('Velocidade:', '${position.speed.toStringAsFixed(1)} km/h'),
                _buildGpsRow('Precisão:', '${position.accuracy.toStringAsFixed(0)} m'),
              ] else ...[
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.location_off, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 8),
                      Text(
                        'Aguardando sinal GPS...',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGpsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// ==========================================================================
  /// BOTÕES DE AÇÃO
  /// ==========================================================================

  Widget _buildActionButtons(BuildContext context, TrackerProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.settings,
                  label: 'Configuração',
                  color: Colors.blue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ConfigScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.terminal,
                  label: 'Logs',
                  color: Colors.purple,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LogsScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.usb,
                  label: 'Arduino',
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ArduinoScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.warning,
                  label: 'SOS',
                  color: Colors.red,
                  onTap: provider.isOnline 
                      ? () => _showSosConfirmation(context, provider)
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSosConfirmation(BuildContext context, TrackerProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Confirmar SOS', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Deseja enviar um alarme SOS para o servidor?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.sendSosAlarm();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ENVIAR SOS'),
          ),
        ],
      ),
    );
  }

  /// ==========================================================================
  /// LOGS PREVIEW
  /// ==========================================================================

  Widget _buildLogsPreview(BuildContext context, TrackerProvider provider) {
    final recentLogs = provider.logs.take(5).toList().reversed.toList();
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        color: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.purple),
                  const SizedBox(width: 8),
                  const Text(
                    'Logs Recentes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LogsScreen()),
                    ),
                    child: const Text('Ver Todos'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (recentLogs.isEmpty)
                Center(
                  child: Text(
                    'Nenhum log ainda',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              else
                ...recentLogs.map((log) => _buildLogItem(log)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    Color color;
    switch (log.type) {
      case LogType.success:
      case LogType.sent:
        color = Colors.green;
        break;
      case LogType.error:
        color = Colors.red;
        break;
      case LogType.warning:
        color = Colors.orange;
        break;
      case LogType.command:
        color = Colors.purple;
        break;
      case LogType.gps:
        color = Colors.cyan;
        break;
      case LogType.arduino:
        color = Colors.amber;
        break;
      default:
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[${log.timestamp.hour.toString().padLeft(2, '0')}:''${log.timestamp.minute.toString().padLeft(2, '0')}:''${log.timestamp.second.toString().padLeft(2, '0')}]',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              log.message,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// ==========================================================================
  /// BOTTOM NAV
  /// ==========================================================================

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          top: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(Icons.dashboard, 'Início', true, () {}),
              _buildNavItem(Icons.settings, 'Config', false, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfigScreen()),
                );
              }),
              _buildNavItem(Icons.terminal, 'Logs', false, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LogsScreen()),
                );
              }),
              _buildNavItem(Icons.usb, 'Arduino', false, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ArduinoScreen()),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? Colors.cyan : Colors.grey,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.cyan : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
