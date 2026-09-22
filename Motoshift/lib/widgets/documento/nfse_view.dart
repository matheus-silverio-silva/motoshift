import 'package:flutter/material.dart';

import '../../models/nota_fiscal.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato_fiscal.dart';
import 'marca_simulacao.dart';

/// Uma NFS-e na tela, na ordem do documento: cabeçalho, prestador, tomador,
/// discriminação, valores, tributos e autenticação.
///
/// Saiu do bottom sheet da tela de notas quando o extrato também passou a
/// abrir notas: um layout só, para a nota não ter duas caras. O PDF
/// (`DocumentoPdf`) segue a mesma ordem e os mesmos textos.
///
/// A marca de simulação vem sempre — no topo e em diagonal —, e não é
/// parâmetro: não existe jeito de mostrar esta nota sem ela.
class NfseView extends StatelessWidget {
  const NfseView({required this.nota, this.rodape, super.key});

  final NotaFiscal nota;

  /// Ações de quem hospeda (cancelar, baixar), abaixo do documento.
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    return MarcaDagua(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MarcaSimulacao(),
          const SizedBox(height: 12),
          _cabecalho(),
          const SizedBox(height: 12),
          _parte('Prestador do serviço', nota.prestadorNome,
              nota.prestadorDocumentoTipo, nota.prestadorDocumento,
              nota.prestadorCidade, Icons.two_wheeler_outlined, nota.souPrestador),
          const SizedBox(height: 10),
          _parte('Tomador do serviço', nota.tomadorNome,
              nota.tomadorDocumentoTipo, nota.tomadorDocumento,
              nota.tomadorCidade, Icons.storefront_outlined, !nota.souPrestador),
          const SizedBox(height: 12),
          _discriminacao(),
          const SizedBox(height: 12),
          _valores(),
          const SizedBox(height: 12),
          _autenticacao(),
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

  Widget _cabecalho() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOTA FISCAL DE SERVIÇO ELETRÔNICA',
              style: tsJakarta(9, FontWeight.w700, color: Colors.white70)
                  .copyWith(letterSpacing: 0.9)),
          const SizedBox(height: 6),
          Text('Nº ${nota.numeroFormatado}',
              style: tsBricolage(24, FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Emitida em ${FormatoFiscal.dataHora(nota.emitidaEm)}',
              style: tsJakarta(11, FontWeight.w400, color: Colors.white70)),
          if (nota.competencia != null) ...[
            const SizedBox(height: 2),
            Text('Competência: ${FormatoFiscal.data(nota.competencia!)}',
                style: tsJakarta(11, FontWeight.w400, color: Colors.white70)),
          ],
        ],
      ),
    );
  }

  Widget _parte(String rotulo, String nome, String docTipo, String? doc,
      String? cidade, IconData icone, bool souEu) {
    return _Cartao(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: souEu ? AppColors.tealSoft : AppColors.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone,
                size: 17, color: souEu ? AppColors.tealDeep : AppColors.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(souEu ? '$rotulo · você' : rotulo,
                    style: tsJakarta(10, FontWeight.w600,
                        color: souEu ? AppColors.teal : AppColors.muted)),
                const SizedBox(height: 2),
                Text(nome,
                    style: tsJakarta(12.5, FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(FormatoFiscal.documento(docTipo, doc),
                    style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted)),
                if (cidade != null)
                  Text(cidade,
                      style: tsJakarta(10.5, FontWeight.w400, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _discriminacao() {
    return _Cartao(
      titulo: 'Discriminação do serviço',
      child: Text(nota.descricaoServico,
          style: tsJakarta(12, FontWeight.w400, color: AppColors.text, height: 1.5)),
    );
  }

  /// As duas políticas de tributo, cada uma dita pelo nome.
  ///
  /// Retidos: ISS e IRRF saíram do pagamento e o líquido é o que sobrou. Não
  /// retidos: são o valor aproximado dos tributos, informação no espírito da
  /// Lei 12.741/2012, e o líquido é o valor do serviço — o mesmo que o extrato
  /// creditou.
  Widget _valores() {
    final retidos = nota.tributosRetidos;
    final sinal = retidos ? '− ' : '';
    return _Cartao(
      titulo: retidos ? 'Valores e tributos retidos' : 'Valores e tributos',
      child: Column(
        children: [
          _Linha('Valor do serviço (base de cálculo)',
              FormatoFiscal.moeda(nota.valorServico), forte: true),
          const SizedBox(height: 8),
          if (!retidos) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Valor aproximado dos tributos (Lei 12.741/2012)',
                  style: tsJakarta(10.5, FontWeight.w700, color: AppColors.muted)),
            ),
            const SizedBox(height: 6),
          ],
          _Linha('ISS (${FormatoFiscal.percentual(nota.issAliquota)})',
              '$sinal${FormatoFiscal.moeda(nota.issValor)}'),
          const SizedBox(height: 6),
          _Linha('IRRF (${FormatoFiscal.percentual(nota.irrfAliquota)})',
              '$sinal${FormatoFiscal.moeda(nota.irrfValor)}'),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 10),
          _Linha(retidos ? 'Total de tributos retidos' : 'Total aproximado de tributos',
              FormatoFiscal.moeda(nota.totalTributos)),
          const SizedBox(height: 8),
          _Linha('Valor líquido', FormatoFiscal.moeda(nota.valorLiquido),
              forte: true, destaque: true),
          const SizedBox(height: 10),
          Text(
            retidos
                ? 'Os tributos foram retidos na fonte e aparecem no extrato, '
                    'na mesma operação do pagamento.'
                : 'Nada foi retido: o valor líquido é o valor do serviço, o '
                    'mesmo creditado no extrato. Alíquotas de exemplo.',
            style: tsJakarta(10, FontWeight.w400, color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _autenticacao() {
    return _Cartao(
      titulo: 'Autenticação',
      child: Column(
        children: [
          _Linha('Código de verificação', nota.codigoVerificacao, forte: true),
          if (nota.operacaoId != null) ...[
            const SizedBox(height: 6),
            _Linha('Operação no extrato', nota.operacaoId!),
          ],
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

class _Cartao extends StatelessWidget {
  const _Cartao({required this.child, this.titulo});

  final String? titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null) ...[
            Text(titulo!.toUpperCase(),
                style: tsJakarta(9, FontWeight.w700, color: AppColors.muted)
                    .copyWith(letterSpacing: 0.9)),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor, {this.forte = false, this.destaque = false});

  final String rotulo;
  final String valor;
  final bool forte;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(rotulo,
              style: tsJakarta(11.5, forte ? FontWeight.w700 : FontWeight.w400,
                  color: forte ? AppColors.text : AppColors.muted)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(valor,
              textAlign: TextAlign.right,
              style: tsJakarta(destaque ? 14 : 12,
                  forte ? FontWeight.w800 : FontWeight.w600,
                  color: destaque ? AppColors.tealDeep : AppColors.text)),
        ),
      ],
    );
  }
}
