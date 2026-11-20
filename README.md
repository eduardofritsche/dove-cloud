# dove-cloud

Projeto de infraestrutura em nuvem do **Dove Restaurante**, sistema de gestão de pedidos, cardápio diário e cozinha do restaurante Dove, implantado na **AWS** com arquitetura serverless.

| Item | Informação |
|---|---|
| Instituição | Uniamérica Descomplica |
| Disciplina | Projeto Integrador: Trabalho Prático de Infraestrutura em Nuvem |
| Professor | Gildomiro Bairros |
| Provedor / Região | AWS · `sa-east-1` (São Paulo) |
| Infraestrutura como código | Terraform |
| Entrega atual | **Entrega 2:** Implantação, segurança, alta disponibilidade e backup (tag `entrega-2`) |

## Integrantes

| Nome | GitHub |
|---|---|
| Eduardo Henrique Fritsche | [@eduardofritsche](https://github.com/eduardofritsche) |
| Lethicia Marques dos Santos Martins | [@lethicia13](https://github.com/lethicia13) |
| Lucas Vieira | [@Lucas-Vieira2006](https://github.com/Lucas-Vieira2006) |

## Visão geral da arquitetura

```
Usuário ──(1) HTTPS──► CloudFront
                         ├─ /*      → S3 (frontend Angular)
                         └─ /api/*  → API Gateway (HTTP API) → Lambda dove-api (Spring Boot)
                                                                  │ 5432
VPC vpc-dove 10.20.0.0/16 · sa-east-1                             ▼
├─ pub-a   10.20.1.0/24   (sa-east-1a)  NAT Gateway + Elastic IP (enable_nat)
├─ priv-a  10.20.10.0/24  (sa-east-1a)  ENIs das Lambdas · Aurora PostgreSQL Serverless v2 (writer)
└─ priv-b  10.20.11.0/24  (sa-east-1b)  ENIs das Lambdas · DB subnet group

Administrador ──(2) IAM (MFA)──► Terraform / AWS CLI / Console / RDS Data API
Lambda dove-egress-check ──(3) rt-private──► NAT Gateway ──► Internet Gateway ──► Internet
```

| Camada | Serviço AWS | Exposição |
|---|---|---|
| Entrada e CDN | Amazon CloudFront (HTTPS, cabeçalhos de segurança) | Pública |
| Frontend | Amazon S3 | Privado, acessado apenas pelo CloudFront (OAC) |
| Entrada da API | Amazon API Gateway (HTTP API, 20 req/s, pico de 50) | Acessado pelo CloudFront |
| Backend | AWS Lambda `dove-api` (Java 17 + Spring Boot, SnapStart) | Sem IP público; ENIs nas sub-redes privadas; saída só para o banco |
| Teste do fluxo 3 | AWS Lambda `dove-egress-check` (Python) | Sem IP público; saída HTTPS pelo NAT |
| Banco de dados | Amazon Aurora PostgreSQL Serverless v2 (0 a 2 ACU) | Sub-rede privada, porta 5432 aceita só do `sg-lambda` |
| Segredos | AWS Secrets Manager (senha do banco e chave do JWT) | Privado |
| Saída da sub-rede privada | NAT Gateway | Criado sob demanda (`enable_nat`) |
| Aquecimento | Amazon EventBridge Scheduler | Desligado na Entrega 2 (`enable_warmup`) |

Os três fluxos numerados correspondem aos exigidos pelo enunciado: **(1)** usuário final acessando a aplicação, **(2)** acesso administrativo (adaptado para IAM, sem SSH; ver [ADR-001](docs/adr/001-acesso-administrativo.md)) e **(3)** recurso privado acessando a internet pelo NAT.

O que mudou em relação ao projeto da Entrega 1 (principalmente a troca do Aurora MySQL pelo Aurora PostgreSQL) está em [`docs/errata.md`](docs/errata.md).

## Aplicação

O código da aplicação fica em repositórios separados:

| Componente | Tecnologia | Repositório |
|---|---|---|
| Frontend | Angular 19 | `dove-integrador-web` |
| Backend | Java 17, Spring Boot 3.5.4, Spring Data JPA, PostgreSQL | `dove-integrador-api` |

## Estrutura do repositório

```
/
├── README.md              # Este arquivo: visão geral e procedimentos de implantação
├── IA.md                  # Declaração de uso de IA
├── docs/
│   ├── arquitetura.md     # Projeto da Entrega 1 (seções 5.1 a 5.11)
│   ├── errata.md          # Diferenças entre a Entrega 1 e o implantado
│   ├── seguranca.md       # Controles S1 a S8, achados e ameaças (Entrega 2)
│   ├── alta-disponibilidade.md  # Requisitos H1 a H7 e custo da redundância (Entrega 2)
│   ├── backup.md          # Inventário, RPO/RTO, política GFS e política mínima (Entrega 2)
│   ├── adr/               # Registros de decisão arquitetural (001 a 006)
│   ├── diagramas/         # Diagrama de arquitetura (.drawio, .png, .pdf)
│   ├── custos/            # Exports da AWS Pricing Calculator
│   └── evidencias/        # Relatórios das ferramentas e capturas das demonstrações
└── infra/                 # Código Terraform
    ├── versions.tf        # Versões fixadas do Terraform e dos providers
    ├── providers.tf       # Provider AWS e tags padrão
    ├── variables.tf       # Variáveis (com tipo e descrição)
    ├── network.tf         # VPC, sub-redes, IGW, NAT e rotas
    ├── security.tf        # Security groups do Lambda e do banco
    ├── database.tf        # Aurora PostgreSQL, parameter group e segredo do banco
    ├── secrets.tf         # Segredo do JWT
    ├── iam.tf             # Roles da Lambda e do EventBridge
    ├── lambda.tf          # Lambdas (API e teste do NAT) e bucket de artefatos
    ├── apigateway.tf      # HTTP API, limites e logs de acesso
    ├── frontend.tf        # Bucket do front e distribuição do CloudFront
    ├── warmup.tf          # Aquecimento agendado
    └── outputs*.tf        # Saídas (URL, IPs, endpoints)
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [Arquitetura](docs/arquitetura.md) | Projeto da Entrega 1: descrição da aplicação, endereçamento IP, rotas, regras de segurança, tecnologias, custos, riscos |
| [Errata](docs/errata.md) | O que mudou entre o projeto da Entrega 1 e o implantado |
| [Segurança](docs/seguranca.md) | Controles S1 a S8, tratamento dos achados do Checkov e da revisão da API, análise de ameaças |
| [Alta disponibilidade](docs/alta-disponibilidade.md) | Requisitos H1 a H7, pontos únicos de falha e custo da redundância |
| [Backup](docs/backup.md) | Inventário, RPO e RTO, política conservadora GFS, política mínima configurada e custos |
| [ADR-001](docs/adr/001-acesso-administrativo.md) | Estratégia de acesso administrativo |
| [ADR-002](docs/adr/002-saida-internet-subrede-privada.md) | Saída para a internet da sub-rede privada |
| [ADR-003](docs/adr/003-localizacao-banco.md) | Localização do banco de dados (motor substituído pelo ADR-004) |
| [ADR-004](docs/adr/004-motor-banco-postgresql.md) | Motor do banco: Aurora PostgreSQL |
| [ADR-005](docs/adr/005-estrategia-alta-disponibilidade.md) | Estratégia de alta disponibilidade (NAT e banco) |
| [ADR-006](docs/adr/006-estrategia-backup.md) | Estratégia de backup (metas, política GFS, mecanismo e local) |
| [Diagrama](docs/diagramas/Diagrama%20de%20arquitetura%20PNG.png) | Diagrama de arquitetura ([fonte editável](docs/diagramas/Diagrama%20de%20arquitetura.drawio)) |
| [Estimativa de custos](docs/custos/estimativa.pdf) | Export da calculadora oficial da AWS |
| [Declaração de uso de IA](IA.md) | Ferramentas de IA usadas e o que foi revisado |

## Implantação

> **Aviso de custo.** O NAT Gateway (≈ US$ 2,35 por dia ligado em `sa-east-1`, mais tráfego) e o Aurora Serverless v2 (cobrado por ACU-hora quando não está pausado, mais armazenamento) geram custo enquanto existem. Mantenha `enable_nat = false` fora das sessões de teste e da apresentação e execute o `terraform destroy` ao final (ver [Destruição do ambiente](#destruição-do-ambiente)). Antes do primeiro `apply`, crie no console os alertas do AWS Budgets. A conta do grupo tem orçamentos mensais de US$ 10 e US$ 60, com alerta em 85% e 100% do gasto real e em 100% da previsão ([evidência](docs/evidencias/budgets-alertas.txt)).

### Pré-requisitos

| Ferramenta | Versão | Uso |
|---|---|---|
| Terraform | 1.16.x (fixada em `infra/versions.tf`) | Criar e destruir a infraestrutura |
| AWS CLI | v2 | Credenciais, deploy do front e testes |
| Java + Maven | Java 17 e Maven 3.9 | Gerar o pacote da API |
| Node.js + Angular CLI | Node 20 ou superior, Angular CLI 19 | Gerar o build do front |
| Repositórios da aplicação | `dove-integrador-api` e `dove-integrador-web`, clonados ao lado deste | Código da aplicação |

Credenciais: configure um perfil da AWS CLI de um usuário IAM com MFA (`aws configure --profile dove`) e exporte `AWS_PROFILE=dove` antes de rodar o Terraform. Nenhuma credencial fica no código.

O state do Terraform (`infra/terraform.tfstate`) fica **local, na máquina de quem executa o `apply`**, e não vai para o Git porque contém a senha do banco e a chave do JWT. Todos os `apply` e o `destroy` são feitos pelo mesmo integrante (ver [Divisão das demonstrações](#divisão-das-demonstrações)).

### 1. Gerar o pacote da API

```bash
cd dove-integrador-api
mvn clean package            # roda os testes e gera target/dove-lambda.zip
mkdir -p ../dove-cloud/infra/artifacts
cp target/dove-lambda.zip ../dove-cloud/infra/artifacts/dove-lambda.zip
```

O Terraform publica esse arquivo no bucket de artefatos e cria uma nova versão da Lambda sempre que o conteúdo do zip muda. Um zip gerado em outra máquina tem hash diferente mesmo com o mesmo código, por isso o `plan` da apresentação deve usar o mesmo arquivo do último `apply`.

### 2. Configurar as variáveis

```bash
cd dove-cloud/infra
cp terraform.tfvars.example terraform.tfvars
```

Principais variáveis do `terraform.tfvars` (que não é versionado):

| Variável | Uso | Dia a dia | Apresentação |
|---|---|---|---|
| `grupo` | Valor da tag `grupo` em todos os recursos | nome do grupo | nome do grupo |
| `enable_nat` | Cria o NAT, o Elastic IP e a rota `0.0.0.0/0` da sub-rede privada | `false` | `true` |
| `aurora_min_capacity` | Capacidade mínima do Aurora (0 permite pausar) | `0` | `0.5` (evita a retomada de ~15 s) |
| `enable_warmup` | Aquecimento agendado | `false` | `false` |

As demais variáveis (região, CIDRs, memória da Lambda, limites da API, retenção de backup e de logs) têm padrão em `variables.tf`, com tipo e descrição.

### 3. Criar a infraestrutura

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
terraform output
```

A criação completa leva de 10 a 15 minutos, a maior parte no Aurora e no CloudFront. Saídas principais: `app_url` (endereço da aplicação), `nat_public_ip`, `aurora_endpoint`, `aurora_cluster_arn`, `db_secret_arn`, `frontend_bucket` e `cloudfront_distribution_id`.

### 4. Publicar o frontend

```bash
cd dove-integrador-web
npm ci
npx ng build                 # perfil production: a API é chamada pela URL relativa /api
aws s3 sync dist/dove-restaurante/browser "s3://$(terraform -chdir=../dove-cloud/infra output -raw frontend_bucket)" --delete
aws cloudfront create-invalidation \
  --distribution-id "$(terraform -chdir=../dove-cloud/infra output -raw cloudfront_distribution_id)" \
  --paths "/*"
```

A invalidação leva de 1 a 2 minutos. Depois disso, a aplicação abre em `terraform output -raw app_url`.

### 5. Criar o primeiro administrador

O esquema do banco é criado pela própria API (Hibernate, `ddl-auto=update`) quando ela inicializa. Por segurança, o cadastro público sempre cria usuários com o perfil `CLIENTE` (ver [`seguranca.md`](docs/seguranca.md), achado A1). Para ter um administrador:

1. Cadastre-se pela tela "Cadastro" da aplicação (e-mail `@gmail.com` ou `@hotmail.com`).
2. Promova o usuário a `ADMIN` pela RDS Data API, autenticado por IAM, sem abrir porta no banco:

```bash
cd dove-cloud/infra
aws rds-data execute-statement \
  --resource-arn "$(terraform output -raw aurora_cluster_arn)" \
  --secret-arn "$(terraform output -raw db_secret_arn)" \
  --database dove \
  --sql "UPDATE tb_usuario SET tipo = 'ADMIN' WHERE username = 'seu-usuario'"
```

3. Faça login de novo. O administrador cadastra funcionários pela área "Funcionários"; funcionários cadastram ingredientes e o cardápio do dia; clientes fazem pedidos.

### 6. Verificar

| O que | Comando | Esperado |
|---|---|---|
| HTTPS e cabeçalhos | `curl -sI "$(terraform output -raw app_url)"` | `HTTP/2 200` com `strict-transport-security` e `x-frame-options` |
| Redirecionamento HTTP | `curl -sI "http://$(terraform output -raw app_url \| sed 's#https://##')"` | `301` para `https://` |
| Saída pelo NAT (fluxo 3) | `aws lambda invoke --function-name dove-egress-check saida.json && cat saida.json` | `ip_de_origem` igual a `terraform output -raw nat_public_ip` (com `enable_nat = true`) |
| Backup e criptografia | `aws rds describe-db-clusters --db-cluster-identifier "$(terraform output -raw aurora_cluster_arn)" --query "DBClusters[0].[BackupRetentionPeriod,StorageEncrypted]"` | `[1, true]` |
| Autorização da API | Logado como cliente, `POST /api/cardapios` | `403` |

### Ligar e desligar o NAT

O NAT é o único recurso cobrado por hora de existência. Para ligar ou desligar, altere `enable_nat` no `terraform.tfvars` e rode `terraform apply`. A aplicação não depende do NAT para funcionar: a Lambda da API não tem saída para a internet e recebe os segredos no deploy (ADR-002).

### Destruição do ambiente

```bash
cd dove-cloud/infra
terraform destroy
```

Os buckets são esvaziados automaticamente (`force_destroy`) e o Aurora é removido sem snapshot final (`skip_final_snapshot`), o que também apaga os backups automáticos. Depois do `destroy`, confira no console que não sobraram NAT Gateway, Elastic IP, snapshots manuais do RDS nem buckets com o prefixo `dove-`.

## Divisão das demonstrações

Roteiro da apresentação de 23/11/2026 (10 minutos). Cada integrante conduz pelo menos uma demonstração.

| Demo | O que mostrar | Responsável |
|---|---|---|
| D1 | `terraform plan` sem alterações e `terraform output` | Eduardo Henrique Fritsche |
| D2 | Aplicação em `app_url`: login, cardápio e pedido; `curl -sI` mostrando HTTPS e os cabeçalhos | Eduardo Henrique Fritsche |
| D3 | Acesso administrativo sem SSH (ADR-001): identidade IAM com MFA (`aws sts get-caller-identity`), consulta pela Data API e ausência de porta 22 nos security groups | Lethicia Marques dos Santos Martins |
| D4 | `dove-egress-check` devolvendo o IP do NAT; ENIs da Lambda sem IP público; matriz de security groups | Lethicia Marques dos Santos Martins |
| D5 | Segredos no Secrets Manager e fora do Git; relatório do Checkov com um achado corrigido (CKV2_AWS_32) e um aceito; cliente recebendo 403 em rota de funcionário | Lethicia Marques dos Santos Martins |
| D6 | Backup: retenção de 1 dia, criptografia ativa e um backup automático existente; política GFS de 12 meses | Lucas Vieira |
| D7 | Proposta de alta disponibilidade e custo | Lucas Vieira |

## Custos

| Cenário | Estimativa |
|---|---|
| A: operação contínua (730 h/mês) | US$ 256,99/mês |
| B: período de trabalho da Entrega 2 | ≈ US$ 12 |

O controle de custos (alertas no AWS Budgets, tags, NAT sob demanda e pausa automática do Aurora) está descrito na seção 5.9 de [`docs/arquitetura.md`](docs/arquitetura.md).

## Entregas

| Entrega | Conteúdo | Prazo | Tag |
|---|---|---|---|
| 1 | Projeto de arquitetura e decisões de infraestrutura | 04/10/2026 | `entrega-1` |
| 2 | Implantação, segurança, alta disponibilidade e backup | 22/11/2026 | `entrega-2` |
