import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/printer_config_service.dart';
import '../../services/print_service.dart';
import '../../utils/esc_pos_formatter.dart';

class PrinterConfigScreen extends StatefulWidget {
  const PrinterConfigScreen({super.key});

  @override
  State<PrinterConfigScreen> createState() => _PrinterConfigScreenState();
}

class _PrinterConfigScreenState extends State<PrinterConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  final _businessNameController = TextEditingController(text: 'TERRA CART');
  final _kotHeaderController = TextEditingController();
  final _billHeaderController = TextEditingController();

  final PrinterConfigService _printerConfig = PrinterConfigService();
  final PrintService _printService = PrintService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _centerAlign = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _businessNameController.dispose();
    _kotHeaderController.dispose();
    _billHeaderController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final config = await _printerConfig.getPrinterConfig();
      if (mounted) {
        setState(() {
          _ipController.text = config['printerIp']?.toString() ?? '';
          _portController.text = (config['printerPort'] ?? 9100).toString();
          _businessNameController.text =
              config['businessName']?.toString() ?? 'TERRA CART';
          _kotHeaderController.text = config['kotHeaderText']?.toString() ?? '';
          _billHeaderController.text =
              config['billHeaderText']?.toString() ?? '';
          _centerAlign = config['centerAlign'] != false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load config: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final ip = _ipController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 9100;

      await _printerConfig.savePrinterConfig(
        printerIp: ip,
        printerPort: port,
        businessName: _businessNameController.text.trim(),
        kotHeaderText: _kotHeaderController.text.trim(),
        billHeaderText: _billHeaderController.text.trim(),
        centerAlign: _centerAlign,
      );

      _printService.invalidatePrinterConfig();

      if (mounted) {
        setState(() {
          _isSaving = false;
          _successMessage = 'Printer config saved successfully';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save: $e';
        });
      }
    }
  }

  String _buildKotPreview() {
    final businessName = _businessNameController.text.trim().isEmpty
        ? 'TERRA CART'
        : _businessNameController.text.trim();
    final headerText = _kotHeaderController.text.trim();
    const noteText = 'Less sugar, no onion';
    const previewWidth = 32;
    final lines = <String>[
      businessName,
      if (headerText.isNotEmpty) headerText,
      'KOT #02 DINE-IN',
      '20 Feb, 03:40 PM',
      '----------------------------',
      'Table: 7',
      'Ref: 6022007',
      if (noteText.isNotEmpty) '----------------------------',
      if (noteText.isNotEmpty) 'Note:',
      if (noteText.isNotEmpty) noteText,
      '----------------------------',
      EscPosFormatter.formatRow('Special Tea', '2x', previewWidth),
      EscPosFormatter.formatRow('Veg Sandwich', '1x', previewWidth),
      '----------------------------',
      'Items: 2  Qty: 3',
    ];
    return lines.join('\n');
  }

  String _buildBillPreview() {
    final businessName = _businessNameController.text.trim().isEmpty
        ? 'TERRA CART'
        : _businessNameController.text.trim();
    final billHeader = _billHeaderController.text.trim();
    final alignment = _centerAlign ? 'CENTER' : 'LEFT';
    const previewWidth = 32;
    final lines = <String>[
      businessName,
      if (billHeader.isNotEmpty) billHeader,
      'Outlet Address from Profile',
      'Invoice No: INV-260220-2207',
      'Date: 2/20/2026',
      'Table 7',
      '----------------------------',
      EscPosFormatter.formatRow('Tea x2', 'Rs.24.00', previewWidth),
      EscPosFormatter.formatRow('Sandwich x1', 'Rs.35.00', previewWidth),
      '----------------------------',
      EscPosFormatter.formatRow('Subtotal', 'Rs.59.00', previewWidth),
      EscPosFormatter.formatRow('Total', 'Rs.59.00', previewWidth),
      'Payment CASH',
      'Align: $alignment',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Configuration'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Configure printer and compact print format. '
                      'Changes are applied to live KOT/Bill printing.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      _buildMessageCard(
                        icon: Icons.error_outline,
                        text: _errorMessage!,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_successMessage != null) ...[
                      _buildMessageCard(
                        icon: Icons.check_circle,
                        text: _successMessage!,
                        color: AppColors.success,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'Printer IP Address',
                        hintText: 'e.g. 192.168.1.151',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.print),
                      ),
                      keyboardType: TextInputType.text,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'IP address is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Printer Port',
                        hintText: '9100',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final port = int.tryParse(v);
                        if (port == null || port < 1 || port > 65535) {
                          return 'Port must be 1-65535';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _businessNameController,
                      decoration: const InputDecoration(
                        labelText: 'Business Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _kotHeaderController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'KOT Header Text (editable preview)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _billHeaderController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Bill Header Text (editable preview)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _centerAlign,
                      onChanged: (value) =>
                          setState(() => _centerAlign = value),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Center Align KOT & Bill'),
                      subtitle:
                          const Text('Use centered layout for compact print'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Live Preview (Editable Settings)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _buildPreviewCard(
                      title: 'KOT Preview',
                      previewText: _buildKotPreview(),
                      previewTextAlign:
                          _centerAlign ? TextAlign.center : TextAlign.left,
                    ),
                    const SizedBox(height: 12),
                    _buildPreviewCard(
                      title: 'Bill Preview',
                      previewText: _buildBillPreview(),
                      previewTextAlign:
                          _centerAlign ? TextAlign.center : TextAlign.left,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMessageCard({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard({
    required String title,
    required String previewText,
    TextAlign previewTextAlign = TextAlign.left,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.cardBorder.withValues(alpha: 0.5),
              ),
            ),
            child: SelectableText(
              previewText.trim(),
              textAlign: previewTextAlign,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
