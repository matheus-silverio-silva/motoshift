import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/pedido_entity.dart';
import '../../presentation/providers/pedido_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kinetic_button.dart';

// ============================================================
// PRESENTATION — Solicitar Serviço de Entrega (RF02)
// Lojista preenche origem, destino e tipo de carga.
// ============================================================

class SolicitarServicoScreen extends StatefulWidget {
  const SolicitarServicoScreen({super.key});

  @override
  State<SolicitarServicoScreen> createState() => _SolicitarServicoScreenState();
}

class _SolicitarServicoScreenState extends State<SolicitarServicoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _origemCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  final _refOrigemCtrl = TextEditingController();
  final _refDestinoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();

  TipoCarga _tipoCarga = TipoCarga.pequeno;
  bool _enviando = false;

  @override
  void dispose() {
    _origemCtrl.dispose();
    _destinoCtrl.dispose();
    _refOrigemCtrl.dispose();
    _refDestinoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _solicitar() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    final provider = context.read<PedidoProvider>();
    final usuarioId = auth.usuario?.id;
    if (usuarioId == null) return;

    setState(() => _enviando = true);

    final pedido = PedidoEntity(
      clienteId: usuarioId,
      enderecoOrigem: _origemCtrl.text.trim(),
      enderecoDestino: _destinoCtrl.text.trim(),
      referenciaOrigem: _refOrigemCtrl.text.trim().isEmpty
          ? null
          : _refOrigemCtrl.text.trim(),
      referenciaDestino: _refDestinoCtrl.text.trim().isEmpty
          ? null
          : _refDestinoCtrl.text.trim(),
      tipoCarga: _tipoCarga,
      observacoes: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
      criadoEm: DateTime.now(),
    );

    final criado = await provider.criarPedido(pedido);
    if (!mounted) return;
    setState(() => _enviando = false);

    if (criado != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido criado! Aguardando motoboy aceitar.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else if (provider.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.erro!), backgroundColor: Colors.red),
      );
      provider.limparErro();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: AppColors.onSurface,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Solicitar Entrega',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('Origem'),
              const SizedBox(height: 10),
              _field(
                controller: _origemCtrl,
                label: 'Endereço de Origem',
                hint: 'Rua, número, bairro...',
                icon: Icons.location_on_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o endereço de origem' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _refOrigemCtrl,
                label: 'Referência (opcional)',
                hint: 'Próximo ao...',
                icon: Icons.info_outline_rounded,
              ),
              const SizedBox(height: 24),
              _sectionLabel('Destino'),
              const SizedBox(height: 10),
              _field(
                controller: _destinoCtrl,
                label: 'Endereço de Destino',
                hint: 'Rua, número, bairro...',
                icon: Icons.flag_outlined,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe o endereço de destino' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _refDestinoCtrl,
                label: 'Referência (opcional)',
                hint: 'Próximo ao...',
                icon: Icons.info_outline_rounded,
              ),
              const SizedBox(height: 24),
              _sectionLabel('Tipo de Carga'),
              const SizedBox(height: 10),
              _cargaChips(),
              const SizedBox(height: 24),
              _sectionLabel('Observações'),
              const SizedBox(height: 10),
              _field(
                controller: _obsCtrl,
                label: 'Observações (opcional)',
                hint: 'Instruções especiais...',
                icon: Icons.notes_rounded,
                maxLines: 3,
              ),
              const SizedBox(height: 32),
              KineticButton(
                label: 'Solicitar Entrega',
                loading: _enviando,
                onPressed: _enviando ? null : _solicitar,
                icon: const Icon(Icons.delivery_dining_rounded,
                    color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: AppColors.onSurfaceVariant,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: const TextStyle(fontFamily: 'Manrope', fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      ),
    );
  }

  Widget _cargaChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: TipoCarga.values.map((tipo) {
        final sel = _tipoCarga == tipo;
        return GestureDetector(
          onTap: () => setState(() => _tipoCarga = tipo),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tipo.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  tipo.label,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
