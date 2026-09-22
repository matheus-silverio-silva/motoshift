import 'package:flutter/material.dart';

import '../../models/documento_fiscal.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato_fiscal.dart';
import 'marca_simulacao.dart';
import 'nfse_view.dart';

/// Recibo ou comprovante na tela: título, número, titular, valor, detalhes e
/// código de autenticação.
class ComprovanteView extends StatelessWidget {
  const ComprovanteView({required this.comprovante, this.rodape, super.key});

  final Comprovante comprovante;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    final c = comprovante;
    final sinal = c.credito == null ? '' : (c.credito! ? '+ ' : '− ');
    return MarcaDagua(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MarcaSimulacao(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.titulo.toUpperCase(),
                    style: tsJakarta(9, FontWeight.w700, color: Colors.white70)
                        .copyWith(letterSpacing: 0.9)),
                const SizedBox(height: 6),
                Text('$sinal${FormatoFiscal.moeda(c.valor)}',
                    style: tsBricolage(26, FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text('Nº ${c.numero} · ${FormatoFiscal.dataHora(c.dataHora)}',
                    style: tsJakarta(11, FontWeight.w400, color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _cartao('Titular', [
            _linha('Nome', c.titularNome, forte: true),
            _linha('Documento', FormatoFiscal.documento(c.titularDocumentoTipo, c.titularDocumento)),
            if (c.titularCidade != null) _linha('Cidade', c.titularCidade!),
          ]),
          const SizedBox(height: 12),
          _cartao('Movimento', [
            if (c.descricao.isNotEmpty) _linha('Descrição', c.descricao),
            for (final l in c.detalhes) _linha(l.rotulo, l.valor),
            if (c.saldoDisponivelApos != null)
              _linha('Saldo disponível depois', FormatoFiscal.moeda(c.saldoDisponivelApos!)),
            if (c.saldoBloqueadoApos != null && c.saldoBloqueadoApos! > 0)
              _linha('Saldo bloqueado depois', FormatoFiscal.moeda(c.saldoBloqueadoApos!)),
          ]),
          const SizedBox(height: 12),
          _cartao('Autenticação', [
            _linha('Código de autenticação', c.codigoAutenticacao, forte: true),
            if (c.operacaoId != null) _linha('Operação no extrato', c.operacaoId!),
          ]),
          if (rodape != null) ...[
            const SizedBox(height: 14),
            rodape!,
          ],
        ],
      ),
    );
  }

  Widget _cartao(String titulo, List<Widget> linhas) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo.toUpperCase(),
              style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                  .copyWith(letterSpacing: 0.9)),
          const SizedBox(height: 8),
          for (var i = 0; i < linhas.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            linhas[i],
          ],
        ],
      ),
    );
  }

  Widget _linha(String rotulo, String valor, {bool forte = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(rotulo,
              style: tsJakarta(11.5, FontWeight.w400, color: AppColors.muted)),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 6,
          child: Text(valor,
              textAlign: TextAlign.right,
              style: tsJakarta(11.5, forte ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.text)),
        ),
      ],
    );
  }
}

/// Um documento qualquer — NFS-e ou comprovante — na tela.
class DocumentoView extends StatelessWidget {
  const DocumentoView({required this.documento, this.rodape, super.key});

  final DocumentoFiscal documento;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    final nota = documento.nota;
    if (nota != null) return NfseView(nota: nota, rodape: rodape);
    return ComprovanteView(comprovante: documento.comprovante!, rodape: rodape);
  }
}
