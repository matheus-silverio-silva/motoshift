import 'package:flutter/material.dart';

import '../../models/danfse.dart';
import '../../models/nota_fiscal.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato_fiscal.dart';
import 'marca_simulacao.dart';
import 'qr_code.dart';

/// Uma NFS-e na tela, no leiaute do DANFSe v2.0 — o Documento Auxiliar da
/// NFS-e do padrão nacional (Nota Técnica SE/CGNFS-e nº 008/2026).
///
/// A ordem é a do documento oficial: identificação da nota (chave de acesso,
/// número, competência, emissão, DPS e QR Code), depois os quadros —
/// prestador, tomador, destinatário, intermediário, serviço, tributação
/// municipal, federal, IBS/CBS, valor total e informações complementares.
/// Os quadros vêm prontos do backend ([Danfse]); aqui só se desenha. O PDF
/// (`DocumentoPdf`) desenha os mesmos quadros.
///
/// O visual segue o do DANFSe: fundo branco, cabeçalho e valor final
/// sombreados em cinza, rótulo pequeno em cima do valor. A marca de simulação
/// vem sempre — no topo e em diagonal —, e não é parâmetro: não existe jeito
/// de mostrar esta nota sem ela.
class NfseView extends StatelessWidget {
  const NfseView({required this.nota, this.rodape, super.key});

  final NotaFiscal nota;

  /// Ações de quem hospeda (cancelar, baixar), abaixo do documento.
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    final danfse = nota.danfse;
    return MarcaDagua(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MarcaSimulacao(),
          const SizedBox(height: 12),
          if (danfse == null)
            _semLeiaute()
          else ...[
            _cabecalho(danfse),
            const SizedBox(height: 10),
            _identificacao(danfse),
            for (final q in danfse.quadros) ...[
              const SizedBox(height: 10),
              _QuadroView(
                quadro: q,
                souEu: (q.id == 'prestador' && nota.souPrestador) ||
                    (q.id == 'tomador' && !nota.souPrestador),
              ),
            ],
          ],
          if (nota.cancelada) ...[
            const SizedBox(height: 12),
            _cancelada(),
          ],
          if (rodape != null) ...[
            const SizedBox(height: 14),
            rodape!,
          ],
        ],
      ),
    );
  }

  /// O cabeçalho do DANFSe: o que é o documento e de onde é. Sem brasão nem
  /// nome de prefeitura — o documento é simulado e não fala em nome de órgão
  /// nenhum; o município aparece como dado.
  Widget _cabecalho(Danfse d) {
    return Container(
      key: const Key('danfse-cabecalho'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('NFS-e',
                style: tsBricolage(14, FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.versao,
                    style: tsJakarta(13, FontWeight.w800, color: AppColors.ink)),
                Text('Documento Auxiliar da NFS-e',
                    style: tsJakarta(11, FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 4),
                Text('Município emissor: ${d.municipioEmissor}',
                    style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted)),
                Text('Leiaute: ${d.norma}',
                    style: tsJakarta(10, FontWeight.w400, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Chave de acesso, número, competência, emissão, DPS e o QR Code.
  Widget _identificacao(Danfse d) {
    final campos = [
      CampoDanfse('Número da NFS-e', nota.numero.toString()),
      CampoDanfse('Competência da NFS-e',
          nota.competencia == null ? '-' : FormatoFiscal.data(nota.competencia!)),
      CampoDanfse('Data e Hora da emissão da NFS-e',
          FormatoFiscal.dataHoraDocumento(nota.emitidaEm)),
      CampoDanfse('Número da DPS', d.numeroDps?.toString() ?? '-'),
      CampoDanfse('Série da DPS', d.serieDps ?? '-'),
      CampoDanfse('Data e Hora da emissão da DPS',
          FormatoFiscal.dataHoraDocumento(nota.emitidaEm)),
    ];
    return _Moldura(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('CHAVE DE ACESSO DA NFS-e', style: _rotulo),
          const SizedBox(height: 4),
          SelectableText(
            d.chaveFormatada,
            key: const Key('danfse-chave'),
            style: tsJakarta(12.5, FontWeight.w800, color: AppColors.ink)
                .copyWith(letterSpacing: 0.6, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 10),
          _Grade(campos: campos),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QrCode(key: const Key('danfse-qrcode'), conteudo: d.conteudoQrCode),
              const SizedBox(width: 12),
              Expanded(
                child: Text(d.avisoQrCode,
                    style: tsJakarta(10.5, FontWeight.w400,
                        color: AppColors.muted, height: 1.45)),
              ),
            ],
          ),
          if (nota.cancelada) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.error, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('NFS-e CANCELADA',
                  textAlign: TextAlign.center,
                  style: tsJakarta(13, FontWeight.w800, color: AppColors.error)
                      .copyWith(letterSpacing: 1.2)),
            ),
          ],
        ],
      ),
    );
  }

  /// Nota vinda de um backend anterior ao leiaute: diz o essencial e o porquê.
  Widget _semLeiaute() {
    return _Moldura(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NFS-e Nº ${nota.numeroFormatado}',
              style: tsJakarta(13, FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text('Valor líquido: ${FormatoFiscal.moeda(nota.valorLiquido)}',
              style: tsJakarta(12, FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 6),
          Text('O servidor não enviou o leiaute do DANFSe desta nota.',
              style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _cancelada() {
    final quando = nota.canceladaEm;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withOpacity(0.35), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.block_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nota cancelada',
                    style: tsJakarta(12.5, FontWeight.w800, color: AppColors.error)),
                if (quando != null)
                  Text(FormatoFiscal.dataHora(quando),
                      style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted)),
                if (nota.motivoCancelamento != null)
                  Text(nota.motivoCancelamento!,
                      style: tsJakarta(11, FontWeight.w400, color: AppColors.text)),
                const SizedBox(height: 4),
                // Cancelar o documento não desfaz o pagamento.
                Text('O pagamento continua no extrato: cancelar a nota não '
                    'estorna dinheiro.',
                    style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final TextStyle _rotulo = tsJakarta(8.5, FontWeight.w700, color: AppColors.muted)
    .copyWith(letterSpacing: 0.6);

/// Um quadro do DANFSe: título em caixa alta, a grade de campos e a
/// observação, se houver.
class _QuadroView extends StatelessWidget {
  const _QuadroView({required this.quadro, required this.souEu});

  final QuadroDanfse quadro;

  /// O quadro é do lado de quem está olhando — prestador ou tomador.
  final bool souEu;

  @override
  Widget build(BuildContext context) {
    return _Moldura(
      key: Key('danfse-quadro-${quadro.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                // "INTERMEDIÁRIO DO SERVIÇO NÃO IDENTIFICADO NA NFS-e" já é o
                // título e o conteúdo: vai uma vez só.
                child: Text(
                    quadro.observacaoRepeteTitulo ? quadro.observacao! : quadro.titulo,
                    style: tsJakarta(9.5, FontWeight.w800, color: AppColors.ink)
                        .copyWith(letterSpacing: 0.7)),
              ),
              if (souEu)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.tealSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('você',
                      style: tsJakarta(9.5, FontWeight.w700, color: AppColors.tealDeep)),
                ),
            ],
          ),
          if (quadro.campos.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Grade(campos: quadro.campos),
          ],
          if (quadro.observacao != null && !quadro.observacaoRepeteTitulo) ...[
            SizedBox(height: quadro.campos.isEmpty ? 6 : 8),
            Text(quadro.observacao!,
                style: tsJakarta(10.5, FontWeight.w400,
                    color: quadro.campos.isEmpty ? AppColors.text : AppColors.muted,
                    height: 1.45)),
          ],
        ],
      ),
    );
  }
}

/// A grade de campos: duas colunas no celular, três em telas largas; campo
/// largo ocupa a linha inteira.
class _Grade extends StatelessWidget {
  const _Grade({required this.campos});

  final List<CampoDanfse> campos;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const espaco = 8.0;
      final colunas = c.maxWidth >= 520 ? 3 : 2;
      final larguraCelula = (c.maxWidth - espaco * (colunas - 1)) / colunas;
      return Wrap(
        spacing: espaco,
        runSpacing: espaco,
        children: [
          for (final campo in campos)
            SizedBox(
              width: campo.largo ? c.maxWidth : larguraCelula,
              child: _CampoView(campo: campo),
            ),
        ],
      );
    });
  }
}

class _CampoView extends StatelessWidget {
  const _CampoView({required this.campo});

  final CampoDanfse campo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: campo.destaque
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
          : EdgeInsets.zero,
      decoration: campo.destaque
          ? BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(campo.rotulo, style: _rotulo),
          const SizedBox(height: 2),
          Text(campo.valor,
              style: tsJakarta(campo.destaque ? 13 : 11.5,
                  campo.destaque ? FontWeight.w800 : FontWeight.w600,
                  color: campo.destaque ? AppColors.tealDeep : AppColors.text,
                  height: 1.35)),
        ],
      ),
    );
  }
}

/// A borda fina dos blocos do DANFSe.
class _Moldura extends StatelessWidget {
  const _Moldura({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: child,
    );
  }
}
