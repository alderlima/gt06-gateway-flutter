import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/tracker_provider.dart';
import '../models/tracker_state.dart';

/// ============================================================================
/// TELA DE LOGS
/// ============================================================================

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  LogType? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Color _getLogColor(LogType type) {
    switch (type) {
      case LogType.success:
      case LogType.sent:
        return Colors.green;
      case LogType.error:
        return Colors.red;
      case LogType.warning:
        return Colors.orange;
      case LogType.command:
        return Colors.purple;
      case LogType.gps:
        return Colors.cyan;
      case LogType.arduino:
        return Colors.amber;
      case LogType.received:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getLogIcon(LogType type) {
    switch (type) {
      case LogType.success:
        return Icons.check_circle;
      case LogType.error:
        return Icons.error;
      case LogType.warning:
        return Icons.warning;
      case LogType.sent:
        return Icons.arrow_upward;
      case LogType.received:
        return Icons.arrow_downward;
      case LogType.command:
        return Icons.gamepad;
      case LogType.gps:
        return Icons.gps_fixed;
      case LogType.arduino:
        return Icons.usb;
      default:
        return Icons.info;
    }
  }

  String _getLogTypeName(LogType type) {
    switch (type) {
      case LogType.info: return 'INFO';
      case LogType.success: return 'SUCCESS';
      case LogType.error: return 'ERROR';
      case LogType.warning: return 'WARN';
      case LogType.sent: return 'SENT';
      case LogType.received: return 'RECV';
      case LogType.command: return 'CMD';
      case LogType.gps: return 'GPS';
      case LogType.arduino: return 'ARDUINO';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Logs'),
        elevation: 0,
        actions: [
          // Filtro
          PopupMenuButton<LogType?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar',
            onSelected: (filter) {
              setState(() {
                _filter = filter;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('Todos'),
              ),
              ...LogType.values.map((type) => PopupMenuItem(
                value: type,
                child: Row(
                  children: [
                    Icon(_getLogIcon(type), color: _getLogColor(type), size: 18),
                    const SizedBox(width: 8),
                    Text(_getLogTypeName(type)),
                  ],
                ),
              )),
            ],
          ),
          // Limpar
          IconButton(
            onPressed: () {
              context.read<TrackerProvider>().clearLogs();
            },
            icon: const Icon(Icons.delete),
            tooltip: 'Limpar logs',
          ),
          // Auto-scroll
          IconButton(
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.unfold_less),
            tooltip: _autoScroll ? 'Auto-scroll ligado' : 'Auto-scroll desligado',
            color: _autoScroll ? Colors.cyan : Colors.grey,
          ),
        ],
      ),
      body: Consumer<TrackerProvider>(
        builder: (context, provider, child) {
          final logs = _filter != null
              ? provider.logs.where((log) => log.type == _filter).toList()
              : provider.logs;
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
          
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.terminal,
                    size: 64,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhum log disponível',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conecte ao servidor para ver os logs',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }
          
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildLogItem(log);
            },
          );
        },
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    final color = _getLogColor(log.type);
    final icon = _getLogIcon(log.type);
    final typeName = _getLogTypeName(log.type);
    
    return Card(
      color: const Color(0xFF161B22),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: log.details != null
            ? () => _showLogDetails(log)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícone
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              
              // Conteúdo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            typeName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '[${_formatTime(log.timestamp)}]',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (log.details != null) ...[
                          const Spacer(),
                          Icon(
                            Icons.expand_more,
                            size: 16,
                            color: Colors.grey[500],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    
                    // Mensagem
                    Text(
                      log.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.9),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:''${time.minute.toString().padLeft(2, '0')}:''${time.second.toString().padLeft(2, '0')}';
  }

  void _showLogDetails(LogEntry log) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Título
                Row(
                  children: [
                    Icon(_getLogIcon(log.type), color: _getLogColor(log.type)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Detalhes do Log',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                          text: '${log.message}\n${log.details}',
                        ));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copiado!')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Timestamp
                _buildDetailRow('Horário:', _formatFullTime(log.timestamp)),
                _buildDetailRow('Tipo:', _getLogTypeName(log.type)),
                const SizedBox(height: 16),
                
                // Mensagem
                const Text(
                  'Mensagem:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    log.message,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                  ),
                ),
                
                if (log.details != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Detalhes:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      log.details!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFullTime(DateTime time) {
    return '${time.day.toString().padLeft(2, '0')}/''${time.month.toString().padLeft(2, '0')}/''${time.year} ''${time.hour.toString().padLeft(2, '0')}:''${time.minute.toString().padLeft(2, '0')}:''${time.second.toString().padLeft(2, '0')}';
  }
}
