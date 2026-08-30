#!/usr/bin/env bash
# ============================================================
#  Commita as melhorias do Moto Shift e envia para o GitHub.
#  Rode na RAIZ do projeto (onde está a pasta .git):
#     bash commitar_melhorias.sh
#  No Windows, use o "Git Bash" ou o terminal do VS Code.
# ============================================================
set -e

# 1) Remove lock preso de algum processo git anterior (se existir).
rm -f .git/index.lock 2>/dev/null || true

# 2) Adiciona APENAS os arquivos destas melhorias (não os de ruído de fim-de-linha).
git add \
  backend/src/main/resources/application.properties \
  backend/src/main/resources/application-prod.properties \
  backend/src/main/java/com/motoshift/entity/Turno.java \
  backend/src/main/java/com/motoshift/entity/TurnoInscricao.java \
  backend/src/main/java/com/motoshift/repository/TurnoInscricaoRepository.java \
  backend/src/main/java/com/motoshift/dto/TurnoRequest.java \
  backend/src/main/java/com/motoshift/dto/TurnoResponse.java \
  backend/src/main/java/com/motoshift/service/TurnoService.java \
  backend/src/main/java/com/motoshift/controller/TurnoController.java \
  Motoshift/lib/app.dart \
  Motoshift/lib/models/turno.dart \
  Motoshift/lib/services/auth_service.dart \
  Motoshift/lib/services/api_service.dart \
  Motoshift/lib/services/preco_recomendado.dart \
  Motoshift/lib/utils/validators.dart \
  Motoshift/lib/theme/app_theme.dart \
  Motoshift/lib/widgets/auth_guard.dart \
  Motoshift/lib/widgets/app_scaffold.dart \
  Motoshift/lib/widgets/stat_card.dart \
  Motoshift/lib/widgets/shift_card.dart \
  Motoshift/lib/widgets/empty_state.dart \
  Motoshift/lib/views/login/login_screen.dart \
  Motoshift/lib/views/cadastro/cadastro_screen.dart \
  Motoshift/lib/views/avaliacao/avaliacao_screen.dart \
  Motoshift/lib/views/agendar_turno/agendar_turno_screen.dart \
  Motoshift/lib/views/dados_pessoais/dados_pessoais_screen.dart \
  Motoshift/lib/views/cnh_veiculo/cnh_veiculo_screen.dart \
  Motoshift/lib/views/meus_turnos/meus_turnos_screen.dart \
  Motoshift/lib/views/detalhe_turno/detalhe_turno_screen.dart \
  Motoshift/lib/views/historico_turnos/historico_turnos_screen.dart \
  Motoshift/lib/views/dashboard_lojista/dashboard_lojista_screen.dart \
  Motoshift/lib/views/dashboard_motoboy/dashboard_motoboy_screen.dart

# 3) Commit.
git commit -m "feat: vagas multiplas, pagamento por entregador, preco recomendado, validacoes e polimento visual

- Protecao de rotas (AuthGuard) por autenticacao e papel
- Layout responsivo (largura maxima) para desktop
- Preco recomendado na publicacao de turno
- Validacoes de email/telefone/CNPJ/CNH/placa (com digito verificador)
- Backend: campo vagas + entidade TurnoInscricao (varios motoboys por turno)
- Pagamento e carteira por entregador (confirmacao dupla por inscricao)
- server.error.include-message=always (mensagens de erro claras)
- Polimento visual: sombra nos cards + componente EmptyState"

# 4) Envia para o GitHub (dispara o deploy no Railway).
git push origin main

echo ""
echo "Concluido! Acompanhe o build no painel do Railway."
