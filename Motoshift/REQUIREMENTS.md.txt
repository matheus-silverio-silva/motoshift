# Documento de Requisitos - Projeto MotoShift

## 1. Visão Geral
O **MotoShift** é um marketplace voltado para o setor de logística urbana, conectando estabelecimentos comerciais (clientes) a entregadores autônomos (motoboys) para a realização de fretes agendados e imediatos.

## 2. Requisitos Funcionais (RF)

### [RF01] Autenticação e Gestão de Perfis
- **Descrição:** O sistema deve permitir o cadastro e login de dois tipos de usuários: Clientes (Empresas) e Entregadores (Motoboys).
- **Integração:** Conectar com o backend Java/Spring para validação de JWT e persistência no MySQL.

### [RF02] Solicitação de Serviços (Marketplace)
- **Descrição:** O cliente deve ser capaz de solicitar uma entrega informando:
    - Endereço de origem e destino.
    - Descrição da carga.
    - Tipo de agendamento (Imediato ou Programado).
- **Regra:** O sistema deve calcular uma estimativa de valor baseada na distância/tempo.

### [RF03] Gerenciamento de Entregas (Lado do Motoboy)
- **Descrição:** O entregador deve visualizar uma lista de pedidos disponíveis próximos à sua localização.
- **Ações:** Aceitar pedido, iniciar rota e confirmar entrega.

### [RF04] Histórico e Status
- **Descrição:** Ambos os usuários devem ter acesso ao histórico de serviços realizados e o status atual de pedidos em andamento (Pendente, Em Trânsito, Concluído).

### [RF05] Painel Administrativo (Dashboard)
- **Descrição:** Visualização resumida de métricas: entregas totais, ganhos do dia e avaliações.

## 3. Requisitos Não Funcionais (RNF)

### [RNF01] Tecnologia de Desenvolvimento
- **Frontend:** Flutter (Compatível com Android/iOS).
- **Backend:** Java com Spring Boot.
- **Banco de Dados:** MySQL.

### [RNF02] Performance e Escalabilidade
- O sistema deve suportar múltiplas requisições simultâneas de localização.
- Respostas da API devem ser processadas em menos de 2 segundos.

### [RNF03] Interface (UI/UX)
- Seguir os protótipos definidos no Stitch.
- Utilizar Material Design 3.

## 4. Estrutura de Integração Sugerida
- **Base URL:** `http://10.0.2.2:8080` (Emulador Android) ou `http://localhost:8080`.
- **Endpoints Previstos:**
    - `POST /api/auth/login`
    - `GET /api/entregas/disponiveis`
    - `POST /api/entregas/solicitar`