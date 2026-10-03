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

O diagrama completo da infraestrutura em nuvem na AWS está disponível em formato vetorial no documento:  
📁 **[Diagrama de arquitetura.pdf](diagramas/Diagrama%20de%20arquitetura.pdf)**

### Componentes e Distribuição de Rede

A infraestrutura foi projetada na região **`sa-east-1` (São Paulo)** dentro da VPC **`vpc-dove`** (`10.20.0.0/16`), distribuída entre duas Zonas de Disponibilidade (`sa-east-1a` e `sa-east-1b`):

- **Sub-rede pública (`pub-a` — 10.20.1.0/24):** Hospeda o Internet Gateway (IGW) e o AWS NAT Gateway provisionado com Elastic IP (criado sob demanda, conforme ADR-002);
- **Sub-redes privadas (`priv-a` — 10.20.10.0/24 e `priv-b` — 10.20.11.0/24):** Hospedam as interfaces de rede elásticas (ENIs) da função AWS Lambda em ambas as AZs e compõem o *DB Subnet Group* do cluster Amazon Aurora Serverless v2 (alocado como writer na sub-rede `priv-a`).

### Descrição dos Fluxos de Comunicação

1. **Fluxo 1 — Requisições de Usuários Finais (Frontend e API):**
   - O usuário final acessa a aplicação via navegador web através de conexão criptografada HTTPS na porta padrão 443;
   - O **Amazon CloudFront** atua como ponto único de entrada seguro (HTTPS) e direciona as requisições:
     - Rotas de conteúdo estático (`/*`): atendidas pelo bucket privado **Amazon S3**, onde está hospedada a SPA em Angular compilada;
     - Rotas da API REST (`/api/*`): encaminhadas diretamente para o **Amazon API Gateway** (HTTP API);
   - O API Gateway invoca a função **AWS Lambda** (`dove-integrador-api`), executada com runtime gerenciado Java 17 e Spring Boot 3 com SnapStart (1536 MB), associada ao Security Group `sg-lambda`;
   - A função Lambda comunica-se com a instância writer do cluster **Amazon Aurora Serverless v2 (MySQL)** através da porta TCP `3306`, protegida pelo Security Group `sg-db` (que autoriza exclusivamente conexões originadas pelo `sg-lambda`).

2. **Fluxo 2 — Gestão e Acesso Administrativo:**
   - O gerenciamento e a administração da infraestrutura são realizados pelo administrador autenticado via **AWS IAM**, operando exclusivamente através da **AWS CLI** e do console web da AWS;
   - Não há instâncias EC2, servidor Bastion Host ou abertura de portas administrativas (como SSH/22) expostas à internet (conforme deliberado no ADR-001).

3. **Fluxo 3 — Saída para a Internet Sob Demanda (Egress):**
   - Quando o NAT Gateway estiver ativado via Terraform (`enable_nat = true`), a função AWS Lambda nas sub-redes privadas consegue estabelecer conexões de saída com serviços externos na internet via porta TCP 443, passando pelo **NAT Gateway** (`pub-a`) e pelo **Internet Gateway (IGW)** (conforme deliberado no ADR-002).

4. **Fluxo 4 — Rotina Programada de Aquecimento (Warm-up):**
   - O **Amazon EventBridge Scheduler** dispara um evento agendado via cron às 10h50 para acionar a função Lambda e restaurar o cluster Aurora Serverless v2 do estado pausado (0 ACU) antes da abertura do restaurante às 11h00, mitigando *cold starts* e tempos de espera no primeiro acesso dos clientes.

---

## 5.3 Plano de Endereçamento IP

### Segmentação pública e privada na AWS

Na AWS, uma sub-rede é pública ou privada conforme o destino da rota padrão na sua tabela de rotas:

- **Pública:** `0.0.0.0/0` aponta para o Internet Gateway.
- **Privada:** `0.0.0.0/0` aponta para o NAT Gateway, que permite saída para a internet mas não aceita conexões de entrada.

A VPC é regional e cada sub-rede pertence a uma única zona de disponibilidade.

Nesta arquitetura, **nenhum recurso computacional possui IP público**. O único endereço público do projeto é o Elastic IP associado ao NAT Gateway, utilizado exclusivamente para tráfego de saída, já que o NAT não aceita conexões de entrada. O Aurora é criado com o acesso público desabilitado, e as funções Lambda não recebem endereço público.

CloudFront, S3, API Gateway, EventBridge, IAM e CloudWatch são serviços gerenciados que operam fora da VPC e, por isso, não constam na tabela de endereçamento.

### Tabela de endereçamento

| Recurso | Nome | CIDR | Zona | Tipo | Finalidade |
|---|---|---|---|---|---|
| VPC | `vpc-dove` | `10.20.0.0/16` | sa-east-1 | — | Rede do projeto |
| Sub-rede | `pub-a` | `10.20.1.0/24` | sa-east-1a | Pública | NAT Gateway (único recurso com IP público) |
| Sub-rede | `priv-a` | `10.20.10.0/24` | sa-east-1a | Privada | ENIs do Lambda (`sg-lambda`) e instância writer do Aurora (`sg-db`) |
| Sub-rede | `priv-b` | `10.20.11.0/24` | sa-east-1b | Privada | ENIs do Lambda (`sg-lambda`); integra o DB subnet group |

Todas as faixas pertencem a `10.0.0.0/8` (RFC 1918) e não se sobrepõem.

### Endereços reservados pela AWS

A AWS reserva **5 endereços em cada sub-rede**: o endereço de rede, o roteador da VPC, o servidor DNS, um endereço reservado para uso futuro e o endereço de broadcast.

| Sub-rede | Total | Reservados | Utilizáveis |
|---|---|---|---|
| `pub-a` (`/24`) | 256 | `.0`, `.1`, `.2`, `.3`, `.255` | 251 |
| `priv-a` (`/24`) | 256 | `.0`, `.1`, `.2`, `.3`, `.255` | 251 |
| `priv-b` (`/24`) | 256 | `.0`, `.1`, `.2`, `.3`, `.255` | 251 |

### Justificativa dos tamanhos

**VPC `/16`.** Define o espaço de endereçamento do projeto e comporta novas sub-redes sem renumeração. O terceiro octeto identifica a função: `1.x` para sub-rede pública, `10.x` e `11.x` para sub-redes privadas.

**`pub-a` (`/24`).** Contém apenas o NAT Gateway, que consome um endereço. O `/24` foi adotado por padronização e legibilidade, já que sub-redes não geram custo e um bloco menor não traria economia. Não há instância, bastion ou balanceador nesta sub-rede: ela existe porque o NAT Gateway precisa estar em uma sub-rede com rota para o Internet Gateway.

**`priv-a` e `priv-b` (`/24`).** Dimensionadas pelo consumo do Lambda. Quando associado a uma VPC, o Lambda cria interfaces de rede (ENIs) compartilhadas entre execuções, e o número de ENIs cresce conforme a concorrência. Com a carga prevista na seção 5.1 (10 a 30 usuários simultâneos), o consumo real é de poucas dezenas de endereços, e os 251 utilizáveis por sub-rede oferecem margem ampla. A instância writer do Aurora consome um endereço adicional em `priv-a`.

**Por que duas sub-redes privadas.** O Amazon Aurora exige um DB subnet group com sub-redes em pelo menos duas zonas de disponibilidade; a criação do cluster falha caso contrário. Essa é uma restrição da AWS, não uma decisão de alta disponibilidade: a instância writer roda apenas em `sa-east-1a`, e nenhuma instância é provisionada em `priv-b`. A arquitetura não oferece alta disponibilidade (ver seção 5.10). A AWS também recomenda manter endereços livres em cada sub-rede do grupo para ações de recuperação, o que os `/24` atendem com folga.

### Endereços por recurso

| Recurso | Sub-rede | Endereço | IP público | Observação |
|---|---|---|---|---|
| NAT Gateway | `pub-a` | IP privado dinâmico | **Sim** — Elastic IP | Único endereço público da arquitetura; usado apenas para saída |
| Aurora (writer) | `priv-a` | Dinâmico, atribuído pela AWS | Não | Acesso público desabilitado; a aplicação usa o endpoint DNS do cluster |
| Lambda (ENIs) | `priv-a` e `priv-b` | Dinâmicos | Não | Quantidade varia conforme a concorrência |

Nenhum endereço IP é fixado manualmente. A aplicação conecta ao banco pelo endpoint DNS do cluster Aurora, que permanece estável mesmo se o endereço da instância mudar após uma recriação do ambiente — situação prevista, já que o ambiente será destruído e recriado entre as sessões de teste da Entrega 2 (ver seção 5.9).

---

## 5.4 Tabelas de Rota

### Visão geral

A VPC `vpc-dove` usa duas tabelas de rota personalizadas, além da tabela principal (*main route table*) criada automaticamente pela AWS:

| Tabela | Nome | Sub-redes associadas | Função |
|---|---|---|---|
| Pública | `rt-public` | `pub-a` | Dá à sub-rede pública saída direta para a internet pelo Internet Gateway |
| Privada | `rt-private` | `priv-a`, `priv-b` | Mantém as sub-redes privadas sem rota de entrada da internet; a saída, quando habilitada, passa pelo NAT Gateway |
| Principal (padrão da VPC) | `rt-main` | nenhuma (associação explícita em todas as sub-redes) | Contém apenas a rota `local`. Se uma sub-rede nova for criada sem associação, ela fica isolada por padrão |

Toda tabela de rota da AWS contém automaticamente a rota `local` para o CIDR da VPC, que não pode ser removida. É ela que permite a comunicação entre sub-redes de zonas de disponibilidade diferentes (por exemplo, uma ENI do Lambda em `priv-b` acessando o Aurora em `priv-a`) sem nenhuma configuração adicional.

### `rt-public`: sub-rede pública

| Destino | Alvo | Observação |
|---|---|---|
| `10.20.0.0/16` | `local` | Tráfego interno da VPC (automática) |
| `0.0.0.0/0` | `igw-dove` (Internet Gateway) | Torna `pub-a` pública. Usada pelo NAT Gateway para alcançar a internet |

### `rt-private`: sub-redes privadas

| Destino | Alvo | Observação |
|---|---|---|
| `10.20.0.0/16` | `local` | Tráfego interno da VPC: Lambda → Aurora na porta 3306 (automática) |
| `0.0.0.0/0` | `nat-dove` (NAT Gateway em `pub-a`) | **Existe apenas quando `enable_nat = true`.** Criada e removida pelo Terraform junto com o NAT Gateway (ver ADR-002) |

As duas sub-redes privadas compartilham a mesma tabela porque existe um único NAT Gateway, em `sa-east-1a`. Com isso, o tráfego de saída das ENIs do Lambda em `priv-b` atravessa para a zona `a` antes de sair. Na proposta de alta disponibilidade (Entrega 2), cada sub-rede privada terá sua própria tabela apontando para um NAT na mesma zona.

### Caminho do fluxo 3: saída para a internet a partir da sub-rede privada

```
Lambda (ENI em priv-a ou priv-b, sem IP público)
   │  rt-private: 0.0.0.0/0 → nat-dove
   ▼
NAT Gateway (pub-a) ── troca o IP de origem pelo Elastic IP
   │  rt-public: 0.0.0.0/0 → igw-dove
   ▼
Internet Gateway ──► Internet
```

A resposta percorre o caminho inverso: o NAT Gateway mantém o estado da conexão e devolve o tráfego à ENI de origem. Conexões iniciadas pela internet não têm caminho de volta até as sub-redes privadas, pois não há rota de entrada nem IP público nelas.

### O que acontece se a rota `0.0.0.0/0 → NAT` não existir

Nesta arquitetura, esse é o **estado padrão**, já que o NAT Gateway é criado sob demanda.

| Componente | Comportamento sem a rota |
|---|---|
| Lambda → Aurora | **Continua funcionando.** O tráfego usa a rota `local` |
| Usuário → CloudFront → API Gateway → Lambda | **Continua funcionando.** A invocação da Lambda chega pelo serviço Lambda, fora da VPC, e não depende das rotas |
| Logs da Lambda no CloudWatch | **Continuam funcionando.** São enviados pelo serviço Lambda, não pela ENI |
| Lambda → qualquer endereço na internet ou API pública da AWS | **Falha por tempo esgotado.** O pacote não tem rota de saída e é descartado; a função espera até o timeout da conexão |
| Fluxo 3 (demonstração) | Não pode ser demonstrado até o NAT ser criado |

Por isso a aplicação foi projetada para **não depender de saída em tempo de execução**: os segredos são injetados como variáveis de ambiente no deploy pelo Terraform, e não lidos de serviços externos pela Lambda.

Dois casos relacionados:

- **NAT removido e rota mantida:** a rota ficaria no estado `blackhole` e o tráfego seria descartado da mesma forma. O Terraform evita esse estado removendo a rota junto com o NAT, pelo mesmo `count` controlado por `enable_nat`.
- **Rota `0.0.0.0/0 → IGW` na sub-rede privada:** também não daria acesso à internet, porque as ENIs do Lambda nunca recebem IP público. Sem NAT, o Internet Gateway não tem como traduzir o endereço privado, e a sub-rede ainda ficaria exposta conceitualmente como "pública".

### Implementação no Terraform (resumo)

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dove.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dove.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.dove.id
}

resource "aws_route" "private_nat" {
  count                  = var.enable_nat ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.dove[0].id
}
```

As associações (`aws_route_table_association`) ligam `pub-a` à `rt-public` e `priv-a`/`priv-b` à `rt-private`.

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

### Provedor e região

**AWS, região `sa-east-1` (São Paulo).**

A escolha do provedor considerou três fatores. O decisivo foi a disponibilidade de créditos gratuitos em uma conta AWS já criada pelo grupo, suficientes para cobrir o custo da Entrega 2, já que a instituição não oferece créditos de nuvem. Além disso, Lambda, API Gateway e Aurora Serverless v2 formam um conjunto integrado, com suporte completo no provider Terraform, atendendo às exigências do enunciado quanto a rede virtual, NAT gerenciado, IP público e regras de firewall. Por fim, integrantes do grupo já haviam utilizado a conta e os serviços em trabalhos anteriores, o que reduz o risco de atraso.

A região foi escolhida pelos três critérios exigidos:

**Latência.** Os usuários do restaurante estão no Brasil e São Paulo é a única região da AWS no país. Uma região norte-americana acrescentaria latência perceptível a cada requisição, agravando o efeito da inicialização a frio do Lambda.

**Custo.** `sa-east-1` é uma das regiões mais caras da AWS. A estimativa na calculadora oficial confirma a diferença: o NAT Gateway custa cerca do dobro do preço de `us-east-1`, o Aurora fica em torno de US$ 0,25 por ACU-hora contra aproximadamente US$ 0,12, e o API Gateway é cerca de 59% mais caro por milhão de requisições. O grupo aceitou esse custo em favor da latência, já que o valor absoluto permanece baixo no cenário previsto e é coberto pelos créditos.

**Disponibilidade dos serviços.** Todos os serviços da arquitetura existem em `sa-east-1`, incluindo o Aurora Serverless v2 compatível com MySQL. A região possui mais de uma zona de disponibilidade, requisito obrigatório para a criação do DB subnet group do Aurora e base para a proposta de alta disponibilidade da Entrega 2.

---

### Sistema operacional

**Não aplicável.** A arquitetura não possui instâncias EC2. O Lambda executa sobre sistema operacional gerenciado pela AWS, sem acesso administrativo, e o Aurora não expõe o sistema subjacente. Não há pacotes a instalar nem atualizações de segurança sob responsabilidade do grupo.

Pela mesma razão não existe acesso por SSH: sem instâncias, não há host ao qual se conectar. A administração ocorre pela AWS CLI, autenticada por IAM. A dispensa da demonstração de SSH prevista para a Entrega 2 foi autorizada pelo professor e está registrada no ADR-001.

---

### Runtime e linguagem

**AWS Lambda com runtime Java gerenciado — Java 17.**

A aplicação já é escrita em Java 17 com Spring Boot 3.5.4, o que dispensa reescrita. Optou-se pelo runtime gerenciado, empacotado em `.zip`, em vez de imagem de container, por ser compatível com o Lambda SnapStart — recurso que reduz o tempo de inicialização a frio, limitação crítica do Spring Boot em ambiente serverless.

A adaptação ao Lambda é feita pela biblioteca **AWS Serverless Java Container**, oficial da AWS, que traduz eventos do API Gateway em requisições HTTP para o Spring. Controllers, serviços e a camada JPA permanecem inalterados.

---

### Servidor web e proxy

**Amazon API Gateway (HTTP API), com Amazon CloudFront e Amazon S3.**

Não há Nginx ou Apache: a função é cumprida por serviços gerenciados. O API Gateway recebe as requisições HTTPS, aplica limitação de taxa e invoca a função Lambda. O tipo HTTP API foi escolhido em vez do REST API por custo por requisição significativamente menor, sem necessidade dos recursos exclusivos do REST API (chaves de API, planos de uso e cache).

O frontend Angular é compilado em arquivos estáticos, servido a partir de um bucket S3 privado e distribuído pelo CloudFront, que fornece HTTPS e unifica frontend e API sob o mesmo domínio, eliminando a configuração de CORS.

---

### Banco de dados

**Amazon Aurora Serverless v2 compatível com MySQL — Aurora MySQL 3.08.0 ou superior.**

A versão 3.x é compatível com MySQL 8.0, mantendo o esquema e as consultas já desenvolvidos. A partir da 3.08.0 o cluster suporta *auto-pause*, podendo escalar a zero ACUs quando ocioso — determinante para o perfil do restaurante, que opera apenas das 11h00 às 14h30. A capacidade foi definida entre 0 e 2 ACUs, sendo cada ACU equivalente a aproximadamente 2 GB de memória com CPU proporcional.

As credenciais do banco são injetadas como variáveis de ambiente na função Lambda pelo Terraform, no momento do deploy, e não são lidas de nenhum serviço externo em tempo de execução. Essa decisão mantém a aplicação funcional mesmo com o NAT Gateway destruído, condição necessária para a estratégia de controle de custos descrita na seção 5.9 e no ADR-002. A limitação aceita está registrada na seção 5.10.

---

### Infraestrutura como código

**Terraform** 

O Terraform é a ferramenta padrão de mercado, com ampla documentação e suporte completo aos serviços utilizados. O provider oficial cobre todos os recursos do projeto e sua versão deve ser fixada no bloco `required_providers` para garantir reprodutibilidade entre os integrantes. Atenção: a configuração de capacidade mínima igual a 0 ACU no Aurora Serverless v2 exige uma versão recente do provider.

---

### Instalação da aplicação

**Script de implantação via AWS CLI, orquestrado pelo Terraform.**

Não há instalação de software em servidor, o que torna inaplicáveis cloud-init e Ansible. O artefato `.jar` da aplicação é publicado em um bucket S3 e referenciado pela função Lambda; o frontend compilado é sincronizado para o bucket do S3. Ambos os passos são executados por script versionado no repositório, sem intervenção manual — o que também viabiliza a estratégia de destruir e recriar o ambiente entre as sessões de teste (seção 5.9).

---

### Serviços complementares

**Amazon EventBridge Scheduler.** Executa uma invocação programada da função Lambda antes do horário de funcionamento, aquecendo o ambiente e retirando o cluster Aurora do estado pausado, o que mitiga a lentidão do primeiro acesso do dia.

**AWS IAM.** Autentica o acesso administrativo pela AWS CLI e define a *execution role* da função Lambda, com permissão restrita à gravação de logs no CloudWatch e à criação das interfaces de rede na VPC.

**Amazon CloudWatch Logs.** Recebe automaticamente os logs de execução da função Lambda.

---

## 5.7 Dimensionamento das Instâncias

*(Arquitetura 100% Serverless / Dispensa de EC2 autorizada pelo professor)*

Conforme autorizado pelo professor Gildomiro Bairros e formalizado no **ADR-001**, o projeto adota uma arquitetura **100% Serverless**, dispensando o provisionamento e a manutenção de máquinas virtuais tradicionais (sem instâncias Amazon EC2 para aplicação, banco de dados ou Bastion Host).

Dessa forma, o dimensionamento tradicional de hardware de instâncias (famílias de instâncias EC2, tipos como `t3.micro`, quantidade fixa de vCPUs de SO e tipos de volumes em bloco EBS como `gp3`) não se aplica diretamente no modelo IaaS convencional. No entanto, para fins de especificação formal, controle de capacidade computacional e atendimento rigoroso aos requisitos do projeto, a equivalência de dimensionamento dos recursos serverless adotados é detalhada a seguir:

### Tabela de Dimensionamento dos Recursos Computacionais

| Componente | Família / Modelo do Serviço | Tipo / Alocação | vCPU Equivalente | Memória RAM | Disco / Armazenamento | Sub-rede | Justificativa de Dimensionamento |
|---|---|---|---|---|---|---|---|
| **Aplicação (Backend)** | AWS Lambda | Runtime gerenciado Java 17 | ~0,88 vCPU eq. (alocada proporcionalmente à memória) | 1.536 MB | 512 MB `/tmp` (efêmero) | `priv-a` e `priv-b` | Dimensionado para suportar com folga o consumo de memória da JVM com Spring Boot 3 e SnapStart. Na AWS Lambda, a alocação de 1.536 MB garante fração de vCPU dedicada suficiente para processar a carga de pico estimada de 10 a 30 usuários simultâneos (2 a 5 RPS) com tempo médio de resposta de 300 ms, sem incorrer em saturação ou trocas de contexto. |
| **Banco de Dados** | Amazon Aurora Serverless v2 | `db.serverless` (Aurora MySQL 3.08+) | Proporcional (escala de 0,5 a 2 vCPUs) | 0 a 2 ACUs (~0 a 4 GB RAM) | Storage distribuído elástico e auto-escalável (0 a 128 TiB) | `priv-a` (writer) | Configurado com auto-pause (`min_capacity = 0`) para escalar a zero fora do expediente do restaurante, contendo custos. Durante o atendimento (11h00 às 14h30), escala dinamicamente entre 0,5 e 2 ACUs (sendo 1 ACU ≈ 2 GB RAM), absorvendo picos sem intervenção manual e com isolamento transacional completo para o InnoDB. |
| **Bastion Host** | *Não aplicável* | — | — | — | — | — | Provisionamento dispensado com anuência do professor e registrado no ADR-001. A administração é 100% realizada via AWS CLI, Terraform e Console AWS autenticada por IAM com MFA, eliminando custos de VM e riscos associados à exposição da porta 22 (SSH). |

### Comportamento em Limite de Carga e Escalonamento
- **AWS Lambda:** Ao atingir o limite de concorrência ou em caso de elevação súbita de tráfego, a AWS cria novas instâncias de execução da função distribuídas pelas ENIs nas sub-redes `priv-a` e `priv-b`. Caso a concorrência atinja limites não provisionados, novas requisições sofrem *throttling* temporário (`HTTP 429 Too Many Requests`), preservando a estabilidade da aplicação.
- **Aurora Serverless v2:** O escalonamento de ACUs ocorre de forma transparente e em tempo real (em frações de até 0,5 ACU) sem queda de conexões ativas. Se a carga ultrapassar 2 ACUs, o banco mantém as conexões existentes mas pode aumentar o tempo de resposta das consultas (*disk queue/wait state*), sem corrupção de dados ou interrupção do serviço.

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
- **Mitigação aplicada:** Durante o horário operacional do restaurante (11h00 às 14h30), uma regra do Amazon EventBridge Scheduler dispara pings periódicos a partir das 10h50 para manter o banco acordado e a função aquecida antes do início do atendimento. Como o restaurante não funciona fora desse horário, a pausa automática durante o período ocioso não prejudica o fluxo normal de atendimento.

### 3. Ausência Temporária de Rota de Saída (Egress) com o NAT Gateway Destruído
- **Descrição da limitação:** O AWS NAT Gateway cobra um valor fixo de ~US$ 0,093/hora (~US$ 71,63/mês com o IPv4 público) independentemente do volume de tráfego. Para não esgotar os créditos da conta durante o período de desenvolvimento da Entrega 2 (Cenário B da Seção 5.9), o NAT Gateway permanecerá destruído na maior parte do tempo, sendo provisionado via Terraform (`enable_nat = true`) exclusivamente nas janelas de teste de saída e apresentações.
- **Impacto:** Em todas as sessões em que o NAT Gateway estiver destruído, a função Lambda na sub-rede privada não terá nenhuma conectividade de saída com a internet pública (`0.0.0.0/0`). Qualquer funcionalidade que venha a depender de chamadas a serviços externos à VPC (como gateways de pagamento, APIs externas ou envio de e-mails) falhará por falta de rota.
- **Trade-off aceito:** A conectividade interna com o Aurora (`priv-a`) continua operando normalmente pela rota local da VPC (`10.20.0.0/16`), permitindo que testes da aplicação sejam realizados sem gerar o custo fixo do NAT.

### 4. Dependência Exclusiva da Gestão de Credenciais IAM (Sem Acesso Shell/SSH)
- **Descrição da limitação:** A escolha deliberada por não utilizar Bastion Host nem portas abertas (ADR-001) elimina o vetor de ataque via SSH, mas concentra 100% da governança de segurança na gestão de credenciais do AWS IAM.
- **Impacto:** A equipe não possui acesso interativo via terminal às máquinas subjacentes da Lambda ou do Aurora. Qualquer diagnóstico operacional ou investigação de falhas depende estritamente da ingestão correta de logs no Amazon CloudWatch e de métricas do console. Além disso, o comprometimento da chave de acesso IAM ou da sessão de console de qualquer integrante concede privilégios diretos sobre a infraestrutura na nuvem, demandando aplicação rigorosa de senhas fortes e MFA em todas as contas.

### 5. Risco de Esgotamento Precoce dos Créditos AWS e Suspensão dos Serviços (Free Plan)
- **Descrição do risco:** Conforme identificado na Seção 5.9 (item 5), a conta utilizada opera sob o AWS Free plan com limite de crédito promocional (US$ 120,00 válido até 22/01/2027). Serviços como Aurora Serverless v2 e NAT Gateway não possuem nível gratuito permanente e geram custo contínuo (~US$ 0,22/h combinados) caso fossem mantidos ativos 24 horas por dia. Nesse cenário ininterrupto, o crédito total se esgotaria em cerca de 22 dias, o que provocaria a suspensão preventiva da conta e a queda de todo o ambiente antes da apresentação final do projeto.
- **Impacto:** Suspensão imediata dos serviços em nuvem pela AWS por falta de créditos/saldo, impedindo testes, ensaios e a demonstração ao vivo para a banca avaliadora.
- **Tratamento e controle:** Esse risco é controlado pelo plano de gestão de custos detalhado na Seção 5.9:
  1. O cluster Aurora opera com *auto-pause* (`min_capacity = 0`), consumindo horas de computação apenas nas janelas de teste;
  2. O NAT Gateway é gerenciado sob demanda via variável Terraform (`enable_nat = false`), sendo mantido destruído fora das sessões de validação;
  3. Configuração de alertas antecipados no **AWS Budgets** (US$ 10, US$ 30 e US$ 60) e ativação de *Cost Allocation Tags* para detecção e contenção imediata de qualquer desvio no consumo.

---

## 5.11 Declaração de Uso de Ferramentas de IA

O uso de inteligência artificial generativa no planejamento, modelagem e documentação da infraestrutura do projeto está formalizado em conformidade com as diretrizes da disciplina no arquivo [`IA.md`](../IA.md), localizado na raiz deste repositório. O documento declara detalhadamente as ferramentas consultadas, o escopo de atuação e as correções e validações críticas conduzidas pela equipe técnica.
