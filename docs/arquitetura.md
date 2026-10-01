# Documento de Arquitetura e Decisões de Infraestrutura

**Projeto:** Dove Restaurante — Sistema de Gestão do Restaurante Dove  
**Disciplina:** Projeto Integrador | Uniamérica Descomplica  
**Professor:** Gildomiro Bairros  
**Provedor de Nuvem:** Amazon Web Services (AWS)  
**Região:** `sa-east-1` (São Paulo)  

---

## 5.1 Descrição da Aplicação

### 1. Problema que a aplicação resolve
O **Dove Restaurante** foi desenvolvido para atender às necessidades operacionais específicas do restaurante **Dove**, resolvendo gargalos no seu fluxo de atendimento diário:
- Desorganização e risco de perda de pedidos causados pelo uso de comandas físicas em papel;
- Falta de sincronização em tempo real entre o atendimento/salão e a equipe de cozinha;
- Dificuldade na gestão do cardápio diário, que varia conforme o dia e a disponibilidade de insumos;
- Ausência de rastreamento do tempo de preparo dos pratos e das marmitas montadas para os clientes.

A aplicação centraliza o fluxo de operação do restaurante Dove: o cliente ou atendente visualiza as opções do cardápio daquele dia específico, faz o pedido com os pratos e marmitas desejados, e a cozinha recebe e atualiza o status de início e conclusão do preparo em tempo real.

---

### 2. Perfis de Usuários
O sistema adota Controle de Acesso Baseado em Papéis (*Role-Based Access Control* - RBAC) através do atributo `TipoUsuario`:

1. **Cliente (`CLIENTE`):**
   - Visualiza o cardápio do dia;
   - Realiza novos pedidos de refeições e marmitas;
   - Consulta o histórico e o status atual do seu pedido ("Meus Pedidos");
   - Mantém seus dados de cadastro e senha.

2. **Funcionário (`FUNCIONARIO`):**
   - Acompanha os pedidos em andamento na cozinha por ordem de chegada;
   - Registra o início e o término do preparo de cada pedido (`hora_inicio` e `hora_fim`);
   - Configura o cardápio do dia vinculando os pratos e marmitas aos ingredientes disponíveis;
   - Gerencia a lista de ingredientes utilizados no restaurante.

3. **Administrador (`ADMIN`):**
   - Gerencia os usuários e funcionários do sistema (cadastro, perfis e permissões);
   - Acompanha o fluxo geral das operações e pedidos do restaurante.

---

### 3. Funcionalidades Principais
- **Autenticação Segura:** Login baseado em JSON Web Token (JWT) stateless com senhas criptografadas em BCrypt.
- **Cardápio Diário:** Cadastro e consulta do cardápio específico para cada data, associado aos ingredientes do dia (`tb_cardapio` e `tb_cardapio_ingrediente`).
- **Controle de Ingredientes:** Cadastro e manutenção dos insumos utilizados nas preparações (`tb_ingrediente`).
- **Gestão de Pedidos:** Registro completo de pedidos (`tb_pedido`), permitindo acompanhar a evolução do atendimento com marcação de horários de início e finalização do preparo pela equipe de cozinha.

---

### 4. Componentes Técnicos da Solução
A solução é dividida em três camadas estruturadas:

1. **Frontend Web (`dove-integrador-web`):**
   - Single Page Application (SPA) desenvolvida em **Angular 19** com componentes visuais do **MDB Angular UI Kit**;
   - Hospedada de forma estática no **Amazon S3** e distribuída globalmente com HTTPS pelo **Amazon CloudFront**;
   - O CloudFront atua como ponto único de entrada, roteando requisições estáticas (`/*`) para o S3 e chamadas de API (`/api/*`) para o API Gateway.

2. **Backend API (`dove-integrador-api`):**
   - API RESTful em **Java 17** com framework **Spring Boot 3.5.4** e Spring Data JPA;
   - Executada de forma serverless como função **AWS Lambda** acoplada às sub-redes privadas da VPC;
   - Ouvindo e respondendo às requisições REST encaminhadas pelo **Amazon API Gateway** (HTTP API).

3. **Banco de Dados Relacional:**
   - **Amazon Aurora Serverless v2 (compatível com MySQL 8.0)**, escutando na porta padrão `3306`;
   - Localizado em sub-rede privada, sem IP público e sem exposição direta para a internet;
   - Acesso estritamente restrito através do Security Group `sg-db`, permitindo tráfego apenas a partir do Security Group da Lambda (`sg-lambda`).

---

### 5. Requisitos Não Funcionais Assumidos
- **Carga e Concorrência Estimada:**
  - O restaurante Dove opera em horário de almoço, com **atendimento exclusivamente das 11h00 às 14h30**;
  - Estimativa de carga de pico: **10 a 30 usuários simultâneos** no intervalo de maior movimento (entre 12h00 e 13h30);
  - Volume de tráfego estimado: baixa vazão, em torno de 2 a 5 requisições por segundo (RPS) em média, totalizando cerca de 100.000 requisições mensais.
  - Fora desse horário operacional, a arquitetura usufrui do *scale-to-zero* dos componentes serverless (Lambda e Aurora com auto-pause), garantindo custo computacional quase nulo.

- **Disponibilidade Esperada:**
  - **Baseline (Entrega 1 e 2):** Instância writer única do Aurora na zona `sa-east-1a`. A arquitetura inicial **não oferece Alta Disponibilidade ativa no banco de dados**, decisão deliberada para conter custos e manter o ambiente dimensionado de forma realista para o escopo do projeto acadêmico.
  - **Alta Disponibilidade (Planejamento conceitual para Entrega 2):** Como requisito da Entrega 2, será documentada a proposta de expansão com réplica de leitura do Aurora e failover multi-AZ automático.

- **Isolação e Segurança:**
  - Ponto de entrada público blindado via CloudFront com HTTPS obrigatório (porta 443);
  - Camada de aplicação e banco de dados isoladas em sub-redes privadas sem IP público;
  - Tráfego interno restrito por regras de Security Group da AWS.

---

## 5.2 Diagrama de Arquitetura

*(Seção a ser preenchida pelo grupo com a referência e descrição dos fluxos do diagrama em `docs/diagramas/`)*

---

## 5.3 Plano de Endereçamento IP

*(Seção a ser preenchida pelo grupo com a tabela de sub-redes e justificativas de endereçamento)*

---

## 5.4 Tabelas de Rota

*(Seção a ser preenchida pelo grupo com os destinos e alvos das tabelas de rota pública e privada)*

---

## 5.5 Matriz de Regras de Segurança

A segurança e o isolamento de rede da arquitetura são implementados na camada de rede por meio de **Security Groups da AWS** (*stateful firewalls*). Seguindo o princípio do menor privilégio, apenas portas estritamente necessárias estão liberadas e todo tráfego não explicitamente autorizado é descartado por padrão (*default deny*).

Nesta arquitetura serverless, os Security Groups são aplicados exclusivamente aos recursos que possuem interfaces de rede dentro da VPC: as **ENIs da AWS Lambda** e o **cluster Amazon Aurora Serverless v2**. Os serviços de borda (CloudFront, S3 e API Gateway) operam fora da VPC com proteção gerenciada pela própria AWS.

---

### 1. Grupo de Segurança da API Lambda (`sg-lambda`)
Associado às interfaces de rede elásticas (ENIs) da função Lambda distribuídas entre as sub-redes privadas `priv-a` e `priv-b`:

| Direção | Tipo / Protocolo | Portas | Origem / Destino | Justificativa |
|---|---|---|---|---|
| **Inbound** (Entrada) | — | — | *Nenhuma regra* | A Lambda não aceita conexões de entrada de rede diretas. A invocação é realizada pelo Amazon API Gateway através da infraestrutura interna gerenciada do plano de controle da AWS (permissão IAM `lambda:InvokeFunction`). |
| **Outbound** (Saída) | TCP | 3306 | `sg-db` *(referência por ID)* | Permite que a API Spring Boot (via Hibernate / JPA) envie consultas e comandos SQL ao cluster Aurora Serverless v2. |
| **Outbound** (Saída) | TCP | 443 | `0.0.0.0/0` | Permite conexões de saída seguras (HTTPS) roteadas pelo NAT Gateway, necessárias para integrações externas e chamadas de APIs. |
| **Outbound** (Saída) | UDP/TCP | 53 | `10.20.0.2` | Resolução de nomes DNS internos da VPC (*AmazonProvidedDNS*), indispensável para resolver o endpoint DNS do Aurora (`*.rds.amazonaws.com`). |

---

### 2. Grupo de Segurança do Banco de Dados (`sg-db`)
Associado ao cluster Amazon Aurora Serverless v2 na sub-rede privada `priv-a` (e grupo de sub-redes em `priv-b`):

| Direção | Tipo / Protocolo | Portas | Origem / Destino | Justificativa |
|---|---|---|---|---|
| **Inbound** (Entrada) | TCP | 3306 | `sg-lambda` *(referência por ID)* | Permite conexões SQL originadas **exclusivamente** pelas execuções autenticadas da função Lambda. Bloqueia qualquer outra origem dentro ou fora da VPC. |
| **Outbound** (Saída) | — | — | *Nenhuma regra* | O banco de dados relacional opera de forma passiva, apenas respondendo às requisições recebidas da aplicação. Ele não inicia conexões de saída para a rede externa. |

---

### Conformidade com as Regras Obrigatórias do Edital

1. **SSH nunca liberado para `0.0.0.0/0` (Inexistência da porta 22):**
   - Em conformidade com o **ADR-001**, a arquitetura eliminou o Bastion Host e as máquinas virtuais convencionais. Consequentemente, **a porta 22 (SSH) não existe e não está aberta em nenhum Security Group** do projeto, eliminando qualquer superfície de ataque por força bruta ou vazamento de chaves privadas SSH.
2. **Isolamento por Referência a Security Group (Sem IPs Estáticos):**
   - O grupo `sg-db` não utiliza faixas de IP ou blocos CIDR para autorizar acesso; ele referencia diretamente o identificador do grupo `sg-lambda`. Isso garante que, mesmo que os endereços IP privados das ENIs da Lambda variem dinamicamente durante escalonamentos, apenas o tráfego legítimo da função terá acesso ao MySQL.
3. **Saída Restrita (*Egress Filtering*):**
   - Em vez de liberar saída irrestrita para qualquer porta (`0.0.0.0/0 ALL`), as regras de saída da Lambda estão restritas estritamente às portas de negócio (3306 para o banco, 443 para HTTPS e 53 para DNS), atendendo aos critérios de menor privilégio.

---

## 5.6 Tecnologias

*(Seção a ser preenchida pelo grupo com a tabela de tecnologias, versões e justificativas)*

---

## 5.7 Dimensionamento das Instâncias

*(Não aplicável / Cancelado com anuência do professor)*

Conforme autorizado pelo professor Gildomiro Bairros, o projeto adota uma arquitetura **100% Serverless**, dispensando o provisionamento e a manutenção de máquinas virtuais (sem instâncias Amazon EC2 para aplicação, banco de dados ou Bastion Host).

Dessa forma, o dimensionamento tradicional de hardware de instâncias (famílias de CPU, quantidade de vCPU, memória RAM de sistema operacional e tipos de discos EBS) **não se aplica** a esta infraestrutura. A computação do backend é executada sob demanda pela AWS Lambda e a capacidade relacional escala automaticamente em frações de ACUs no Amazon Aurora Serverless v2.

---

## 5.8 Registros de Decisão Arquitetural (ADRs)

As decisões arquiteturais obrigatórias da Entrega 1 foram registradas no formato Y-statement e encontram-se detalhadas individualmente na pasta [`docs/adr/`](adr/):

1. **[ADR-001: Estratégia de Acesso Administrativo](adr/001-acesso-administrativo.md)**
   - *Decisão:* Acesso baseado exclusivamente em **AWS IAM** operado via Terraform e AWS CLI, descartando soluções via SSH (Bastion Host e SSM).
   - *Consequência aceita:* A segurança do ambiente passa a depender inteiramente das credenciais IAM de cada integrante.

2. **[ADR-002: Saída para a Internet da Sub-rede Privada](adr/002-saida-internet-subrede-privada.md)**
   - *Decisão:* Adoção de **NAT Gateway gerenciado** em sub-rede pública criado e destruído sob demanda via Terraform, descartando NAT em EC2 (fck-nat) e VPC Endpoints.
   - *Consequência aceita:* Custo fixo alto cobrado por hora mesmo sem uso, exigindo criá-lo apenas durante testes do fluxo 3 e destruí-lo em seguida.

3. **[ADR-003: Localização do Banco de Dados](adr/003-localizacao-banco.md)**
   - *Decisão:* Utilização do **Amazon Aurora MySQL Serverless v2** (faixa de 0 a 2 ACUs com auto-pause após 5 min) na sub-rede privada `priv-a`, descartando RDS for MySQL e instâncias EC2.
   - *Consequência aceita:* Ausência de nível gratuito, latência de ~15 segundos na retomada após a pausa (exigindo aquecimento agendado) e writer único em `sa-east-1a` como ponto único de falha.

---

## 5.9 Estimativa de Custos

| Item | Informação |
|---|---|
| Ferramenta | AWS Pricing Calculator (calculadora oficial) |
| Estimativa compartilhável | https://calculator.aws/#/estimate?id=6d6c46b6adfb03688a5634809a8aa207dafcab5a |
| Exportação | [`docs/custos/estimativa.pdf`](custos/estimativa.pdf) |
| Região | `sa-east-1` (São Paulo) |
| Data da consulta de preços | 29/09/2026 |
| Moeda | USD (sem impostos) |

### 1. Premissas de uso

Os volumes abaixo derivam dos requisitos não funcionais da seção 5.1 (atendimento das 11h00 às 14h30, pico de 10 a 30 usuários simultâneos).

| Premissa | Valor adotado | Origem |
|---|---|---|
| Requisições à API | 100.000/mês | ~150 clientes/dia × ~20 chamadas por sessão (cardápio, pedido, status) + painel da cozinha, arredondado para cima |
| Duração média da Lambda | 300 ms | Consultas JPA simples ao Aurora com a função aquecida |
| Memória da Lambda | 1.536 MB | Mínimo confortável para JVM + Spring Boot (mais memória também significa mais CPU na Lambda) |
| Capacidade do Aurora | 1 ACU na calculadora (mínimo real: 0,5 ACU) | A calculadora não aceita ACU fracionado; o valor é conservador |
| Armazenamento do Aurora | 1 GB | Tabelas de usuários, cardápio, ingredientes e pedidos |
| Build do Angular no S3 | 1 GB | O build real tem poucos MB; valor com folga |
| Logs (CloudWatch) | 1 GB/mês | Logs da Lambda |
| Segredos | 2 | Senha do banco e `SECRET_KEY` do JWT |
| Aquecimento (EventBridge) | ~1.300 invocações/mês | Ping a cada 5 min, das 10h50 às 14h30, 30 dias |

### 2. Cenário A: operação contínua (730 h/mês)

Valores retirados da estimativa exportada ([`docs/custos/estimativa.pdf`](custos/estimativa.pdf)):

| # | Serviço | Configuração | US$/mês | % do total |
|---|---|---|---:|---:|
| 1 | Amazon Aurora MySQL Serverless v2 | 1 ACU × 730 h (US$ 0,25/ACU-h) + 1 GB | **183,43** | 71,4% |
| 2 | Amazon VPC: NAT Gateway | 1 NAT em 1 AZ × 730 h (US$ 0,093/h) + 1 GB processado | **67,98** | 26,5% |
| 3 | Amazon VPC: IPv4 público | 1 Elastic IP do NAT × 730 h (US$ 0,005/h) | 3,65 | 1,4% |
| 4 | Amazon CloudWatch | 1 GB de logs/mês | 0,91 | 0,4% |
| 5 | AWS Secrets Manager | 2 segredos | 0,80 | 0,3% |
| 6 | Amazon API Gateway | HTTP API, 100 mil requisições/mês | 0,16 | 0,1% |
| 7 | Amazon S3 | 1 GB + 21 mil requisições | 0,06 | < 0,1% |
| 8 | AWS Lambda | 100 mil req × 300 ms × 1.536 MB | 0,00 | nível gratuito |
| 9 | Amazon CloudFront | Plano gratuito (tarifa fixa) | 0,00 | nível gratuito |
| 10 | Amazon EventBridge Scheduler | Aquecimento agendado | 0,00 | nível gratuito |
| | **Total mensal** | | **256,99** | 100% |
| | **Total em 12 meses** | | **3.083,88** | |

**Item mais caro: Amazon Aurora Serverless v2 (US$ 183,43/mês, 71% do total)**, seguido pelo **NAT Gateway (US$ 71,63/mês com o IPv4, 28%)**. Os dois juntos representam 99% do custo; os serviços serverless de borda e computação (CloudFront, API Gateway, Lambda) custam praticamente zero no volume do restaurante.

Observações sobre a calculadora:
- O Aurora foi estimado com 1 ACU porque a calculadora não aceita 0,5 ACU. Com o mínimo real de 0,5 ACU ligado 24h, o custo de computação cai para US$ 91,25/mês.
- A calculadora exige o preenchimento do campo "NAT Gateway regional"; foi usado 1 gateway em 1 AZ, cujo preço (US$ 0,093/h) é idêntico ao do NAT Gateway zonal da arquitetura.
- O campo do EventBridge Scheduler só aceita milhões inteiros; foi usado 1 milhão (o uso real, ~1.300 invocações, fica dentro das 14 milhões gratuitas).

### 3. Cenário B: período de trabalho da Entrega 2 (05/10 a 23/11/2026)

Este é o valor que o grupo efetivamente pagará. A calculadora só estima meses cheios (730 h), por isso o cenário B usa os **preços por hora obtidos na própria calculadora** multiplicados pelas horas previstas.

**Estratégia de operação no período:**
- O ambiente é criado uma vez pelo Terraform e **permanece existindo** até a apresentação.
- O Aurora fica com **auto-pause** (mínimo 0 ACU): só cobra computação quando há conexões ativas.
- O NAT Gateway é **criado apenas nas sessões que precisam dele** (validação do fluxo 3, ensaio e apresentação), via variável `enable_nat`. A aplicação funciona sem o NAT, pois a Lambda só acessa o Aurora dentro da VPC.
- O aquecimento agendado fica **desligado** (só faz sentido na operação real do restaurante).

**Horas previstas:**

| Atividade | Sessões | Horas com Aurora ativo | Horas com NAT |
|---|---:|---:|---:|
| Desenvolvimento e testes da aplicação | 8 × 5 h | 40 | 0 |
| Testes de segurança e do fluxo 3 (NAT) | 2 × 4 h | 8 | 8 |
| Ensaio da apresentação | 1 × 3 h | 3 | 1 |
| Apresentação (23/11) | 1 × 2 h | 2 | 1 |
| Margem para imprevistos | | 7 | 0 |
| **Total** | | **60** | **10** |

**Custo do período:**

| Item | Preço unitário (calculadora) | Quantidade | Custo (US$) |
|---|---|---:|---:|
| Aurora: computação | US$ 0,25/ACU-h × 0,5 ACU = US$ 0,125/h | 60 h | 7,50 |
| Aurora: armazenamento e E/S | ≈ US$ 0,93/mês | ~1,7 mês | 1,58 |
| NAT Gateway | US$ 0,093/h (cobrado por hora iniciada) | 10 h | 0,93 |
| NAT Gateway: dados processados | US$ 0,093/GB | 1 GB | 0,09 |
| IPv4 público do NAT | US$ 0,005/h | 10 h | 0,05 |
| Secrets Manager | US$ 0,40/segredo/mês | 2 × ~1,7 mês | 1,36 |
| API Gateway, S3, CloudWatch | valores proporcionais ao uso de teste | — | ~0,50 |
| Lambda, CloudFront, EventBridge | nível gratuito | — | 0,00 |
| **Total estimado do período** | | | **≈ 12,01** |

O valor corresponde a cerca de **10% do crédito disponível** na conta (seção "Nível gratuito" abaixo).

### 4. Proposta de redução do item mais caro

**Item:** Amazon Aurora Serverless v2.

**Proposta:** configurar o Aurora com **auto-pause** (`min_capacity = 0`, `seconds_until_auto_pause = 300`) e operar o banco **apenas no horário do restaurante**, com um aquecimento agendado às 10h50 pelo EventBridge Scheduler. Fora do horário, o banco pausa e só o armazenamento é cobrado.

| Configuração do Aurora | Horas ativas/mês | US$/mês (computação) |
|---|---:|---:|
| Cenário A da calculadora (1 ACU × 730 h) | 730 | 182,50 |
| Mínimo real ligado 24h (0,5 ACU × 730 h) | 730 | 91,25 |
| **Proposta: auto-pause + operação 10h50–14h30** (~4 h/dia × 30 dias, média de ~0,7 ACU) | ~120 | **≈ 21,00** |

| Total da arquitetura | US$/mês |
|---|---:|
| Cenário A (calculadora) | 256,99 |
| Cenário A com a proposta aplicada ao Aurora | ≈ 95,50 |
| Cenário A com a proposta + NAT criado sob demanda | ≈ 24,00 |

**Redução: de US$ 183,43 para cerca de US$ 21/mês no Aurora (−88%).**

**O que se perde com a redução:**
- **Latência na retomada:** o Aurora leva ~15 s para acordar (mais se ficar pausado por mais de 24 h). Somado ao cold start da Lambda, a primeira requisição pode passar do limite de 30 s do API Gateway e falhar. Isso exige o aquecimento agendado antes do almoço.
- **Complexidade operacional:** a pausa só ocorre sem conexões abertas; é necessário configurar `wait_timeout` no parameter group e um pool pequeno no Spring (Hikari com `minimum-idle = 0`), senão a Lambda mantém conexões e o banco nunca pausa.
- **Uso fora do horário fica lento:** um pedido feito às 16h, por exemplo, encontra o banco pausado e espera a retomada.
- **Se o NAT for criado sob demanda:** a sub-rede privada fica sem saída para a internet fora das janelas de manutenção (o fluxo 3 deixa de estar disponível permanentemente).

### 5. Nível gratuito

**Na calculadora:**

| Serviço | Nível gratuito considerado? | Detalhe |
|---|---|---|
| AWS Lambda | Sim | Opção "Incluir nível gratuito" (1 milhão de requisições e 400.000 GB-s/mês, sempre gratuitos); o uso estimado (~45.000 GB-s) fica dentro do limite |
| Amazon CloudFront | Sim | Plano gratuito de tarifa fixa |
| Amazon EventBridge Scheduler | Sim, na prática | 14 milhões de invocações/mês gratuitas; o uso real é ~1.300 |
| Aurora, NAT, IPv4, S3, API Gateway, Secrets Manager, CloudWatch | Não | A calculadora exclui os descontos do nível gratuito nesses serviços |

**Na conta:** a conta usada pelo grupo está no **AWS Free plan**, com **US$ 120,00 de crédito, válido até 22/01/2027**. Os créditos cobrem integralmente o cenário B (≈ US$ 12) e o prazo inclui a apresentação de 23/11/2026. O Aurora Serverless v2 (MySQL) e o NAT Gateway não têm nível gratuito e consomem crédito desde a primeira hora.

**Risco associado:** no Free plan, quando o crédito acaba, a AWS suspende os serviços. Com NAT e Aurora ligados 24h (~US$ 0,22/h), o crédito se esgotaria em cerca de 22 dias, o que derrubaria o ambiente antes da apresentação. Esse risco é tratado pelo plano abaixo.

### 6. Plano de controle de custos

| Controle | Implementação | Momento |
|---|---|---|
| Alertas de orçamento | AWS Budgets com alertas por e-mail para o grupo em US$ 10, US$ 30 e US$ 60 (valor real e previsto) | Criado manualmente no console **antes do primeiro `terraform apply`** (exceção permitida pelo enunciado) |
| Tags em todos os recursos | `default_tags` no provider AWS do Terraform: `projeto = "dove"`, `grupo = "<grupo>"`, `ambiente = "entrega2"`, `gerenciado-por = "terraform"` | Desde o primeiro `apply` |
| Rastreio de custo por tag | Ativação das tags como *cost allocation tags* em Billing | Após o primeiro `apply` |
| NAT sob demanda | Variável `enable_nat` (padrão `false`); scripts `nat-on.sh` / `nat-off.sh` executam `terraform apply -var enable_nat=true/false` | Toda sessão que usar o NAT termina com `nat-off.sh` |
| Banco com pausa automática | Aurora com `min_capacity = 0` e `seconds_until_auto_pause = 300` | Permanente |
| Aquecimento desligado | Variável `enable_warmup = false` durante a Entrega 2 | Ligado apenas para demonstrar o cenário de operação |
| Nada criado no console | Toda mudança de infraestrutura via Terraform, para não haver recurso "esquecido" fora do state | Permanente |
| Destruição final | `terraform destroy` completo após a apresentação | 23/11/2026 |

### 7. Estratégia adotada: destruir e recriar × manter o ambiente

| Opção | Custo | Esforço | Decisão |
|---|---|---|---|
| Destruir tudo entre sessões | Menor custo de computação, mas o Aurora recriado leva 10–15 min e **perde os dados** (exigiria restaurar snapshot a cada sessão) | Alto | Descartada |
| **Manter o ambiente e destruir só o NAT entre sessões** | ~US$ 1–2/mês com o ambiente parado (armazenamento do Aurora e segredos) + horas de uso | Baixo | **Adotada** |
| Manter tudo ligado 24h | ~US$ 257/mês pela calculadora; esgotaria o crédito em semanas | Nenhum | Descartada |

**Justificativa:** como os componentes serverless (Lambda, API Gateway, CloudFront, S3) não cobram quando ociosos e o Aurora pausa sozinho, manter o ambiente criado custa quase nada. O único recurso que cobra por hora de existência é o NAT Gateway, e por isso ele é o único criado e destruído a cada sessão, por script Terraform.

**Trade-off aceito:** o grupo precisa manter a disciplina de executar `nat-off.sh` ao fim de cada sessão (um dia esquecido custa ~US$ 2,35), e a primeira requisição de cada sessão é lenta por causa da retomada do Aurora. Para que recriar partes do ambiente não exija reinstalação manual, o deploy da aplicação é automatizado: o pacote da Lambda é publicado pelo Terraform, e o front é publicado por script (`aws s3 sync` + invalidação do CloudFront).

---

## 5.10 Riscos e Limitações

A arquitetura baseline adotada para a Entrega 1 prioriza baixo custo operacional, simplicidade de manutenção e conformidade com o crédito disponível na AWS (US$ 120,00). Essa abordagem deliberada introduz limitações e pontos únicos de falha conhecidos, que servirão como base de comparação para a proposta de Alta Disponibilidade da Entrega 2:

### 1. Instância Writer Única do Aurora em Zona Única (`sa-east-1a`)
- **Descrição da limitação:** Para manter a infraestrutura de banco de dados econômica, o cluster Amazon Aurora Serverless v2 possui apenas uma única instância writer alocada na zona de disponibilidade `sa-east-1a` (sub-rede `priv-a`). Embora o *DB Subnet Group* englobe `priv-b` (em `sa-east-1b`), nenhuma réplica de leitura ou instância standby está ativa nesta segunda zona.
- **Impacto:** Caso ocorra uma falha física, energética ou de conectividade na AZ `sa-east-1a` da AWS em São Paulo, o banco de dados ficará completamente indisponível. A aplicação não conseguirá realizar leituras ou escritas.
- **Tempo e forma de recuperação:** Exige intervenção manual ou acionamento do Terraform para provisionar uma nova instância writer na zona `sa-east-1b` a partir do storage distribuído subjacente do Aurora (RTO estimado: ~10 a 15 minutos).
- **Tratamento na Entrega 2:** Este ponto único de falha será o ponto central da proposta de Alta Disponibilidade da Entrega 2, onde será avaliada a inclusão de réplicas de leitura multi-AZ com failover automático.

### 2. Latência de Retomada do Aurora Pausado (0 ACU) somada ao Cold Start da Lambda
- **Descrição da limitação:** Conforme definido no ADR-003 e na Seção 5.9, o cluster Aurora Serverless v2 opera com auto-pause (`min_capacity = 0`, pausa após 5 minutos sem conexões). Quando o banco está pausado, o restabelecimento da camada computacional leva cerca de 15 segundos. Se essa primeira chamada coincidir com uma execução a frio (*cold start*) da função AWS Lambda em Java/Spring Boot (~8 a 10 segundos para carregar JVM e beans JPA), o tempo total de resposta acumulado pode atingir de 23 a 28 segundos.
- **Impacto:** Risco de expirar o limite rígido de timeout de 30 segundos do Amazon API Gateway, retornando erro `HTTP 504 Gateway Timeout` para o primeiro cliente que acessar o sistema após um período de inatividade.
- **Mitigação aplicada:** Durante o horário operacional do restaurante (11h00 às 14h30), uma regra do Amazon EventBridge Scheduler dispara pings periódicos a partir das 10h50 para manter o banco acordado e a função aquecida. No entanto, chamadas esporádicas fora desse turno continuam sujeitas a essa latência perceptível.

### 3. Ausência Temporária de Rota de Saída (Egress) com o NAT Gateway Destruído
- **Descrição da limitação:** O AWS NAT Gateway cobra um valor fixo de ~US$ 0,093/hora (~US$ 71,63/mês com o IPv4 público) independentemente do volume de tráfego. Para não esgotar os créditos da conta durante o período de desenvolvimento da Entrega 2 (Cenário B da Seção 5.9), o NAT Gateway permanecerá destruído na maior parte do tempo, sendo provisionado via Terraform (`enable_nat = true`) exclusivamente nas janelas de teste de saída e apresentações.
- **Impacto:** Em todas as sessões em que o NAT Gateway estiver destruído, a função Lambda na sub-rede privada não terá nenhuma conectividade de saída com a internet pública (`0.0.0.0/0`). Qualquer funcionalidade que venha a depender de chamadas a serviços externos à VPC (como gateways de pagamento, APIs externas ou envio de e-mails) falhará por falta de rota.
- **Trade-off aceito:** A conectividade interna com o Aurora (`priv-a`) continua operando normalmente pela rota local da VPC (`10.20.0.0/16`), permitindo que testes da aplicação sejam realizados sem gerar o custo fixo do NAT.

### 4. Dependência Exclusiva da Gestão de Credenciais IAM (Sem Acesso Shell/SSH)
- **Descrição da limitação:** A escolha deliberada por não utilizar Bastion Host nem portas abertas (ADR-001) elimina o vetor de ataque via SSH, mas concentra 100% da governança de segurança na gestão de credenciais do AWS IAM.
- **Impacto:** A equipe não possui acesso interativo via terminal às máquinas subjacentes da Lambda ou do Aurora. Qualquer diagnóstico operacional ou investigação de falhas depende estritamente da ingestão correta de logs no Amazon CloudWatch e de métricas do console. Além disso, o comprometimento da chave de acesso IAM ou da sessão de console de qualquer integrante concede privilégios diretos sobre a infraestrutura na nuvem, demandando aplicação rigorosa de senhas fortes e MFA em todas as contas.

---

## 5.11 Declaração de Uso de Ferramentas de IA

O uso de inteligência artificial generativa no planejamento, modelagem e documentação da infraestrutura do projeto está formalizado em conformidade com as diretrizes da disciplina no arquivo [`IA.md`](../IA.md), localizado na raiz deste repositório. O documento declara detalhadamente as ferramentas consultadas, o escopo de atuação e as correções e validações críticas conduzidas pela equipe técnica.




