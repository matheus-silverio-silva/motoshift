import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/app_scaffold.dart';

Widget _stubBody(String title) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.construction_rounded,
                color: AppColors.teal, size: 28),
          ),
          const SizedBox(height: 16),
          Text(title,
              style:
                  tsBricolage(17, FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(
            'Em breve',
            style: tsJakarta(12, FontWeight.w400, color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class DadosPessoaisScreen extends StatelessWidget {
  const DadosPessoaisScreen({super.key});
  @override
  Widget build(BuildContext context) => AppScaffold(
        header: AppHeader.back(title: 'Dados pessoais'),
        body: _stubBody('Dados pessoais'),
      );
}

class CnhVeiculoScreen extends StatelessWidget {
  const CnhVeiculoScreen({super.key});
  @override
  Widget build(BuildContext context) => AppScaffold(
        header: AppHeader.back(title: 'CNH e Veículo'),
        body: _stubBody('CNH e Veículo'),
      );
}

class NotificacoesScreen extends StatelessWidget {
  const NotificacoesScreen({super.key});
  @override
  Widget build(BuildContext context) => AppScaffold(
        header: AppHeader.back(title: 'Notificações'),
        body: _stubBody('Notificações'),
      );
}

class MinhasAvaliacoesScreen extends StatelessWidget {
  const MinhasAvaliacoesScreen({super.key});
  @override
  Widget build(BuildContext context) => AppScaffold(
        header: AppHeader.back(title: 'Minhas avaliações'),
        body: _stubBody('Minhas avaliações'),
      );
}

class HistoricoTurnosScreen extends StatelessWidget {
  const HistoricoTurnosScreen({super.key});
  @override
  Widget build(BuildContext context) => AppScaffold(
        header: AppHeader.back(title: 'Histórico de turnos'),
        body: _stubBody('Histórico de turnos'),
      );
}

class SacarPixScreen extends StatelessWidget {
  const SacarPixScreen({super.key});
  @override
  Widget build(BuildContext context) => AppScaffold(
        header: AppHeader.back(title: 'Transferir via PIX'),
        body: _stubBody('Transferir via PIX'),
      );
}

class EsqueceuSenhaScreen extends StatelessWidget {
  const EsqueceuSenhaScreen({super.key});
  @override
  Widget build(BuildContext context) => AppScaffold(
        header: AppHeader.back(title: 'Recuperar senha'),
        body: _stubBody('Recuperar senha'),
      );
}
