# Errata: Entrega 1 × infraestrutura implantada

Este documento lista o que mudou entre o projeto entregue na Entrega 1 (`docs/arquitetura.md`, ADRs 001 a 003 e diagrama, tag `entrega-1`) e o que foi de fato implantado no código Terraform em `infra/` (tag `entrega-2`). O texto da Entrega 1 foi mantido como registro histórico; quando houver conflito, **vale o que está nesta errata e no código**.

Cada item indica o que foi projetado, o que foi implantado, o motivo e as seções da Entrega 1 afetadas.

---

## 1. Motor do banco: Aurora MySQL → Aurora PostgreSQL

| | Entrega 1 | Implantado |
|---|---|---|
| Motor | Aurora MySQL-Compatible Serverless v2, versão 3.08 ou superior | Aurora PostgreSQL Serverless v2, versão 17.9 (`aurora_engine_version`) |
| Porta | TCP 3306 | TCP 5432 |
| Parâmetros | `wait_timeout` (MySQL) | `idle_session_timeout` e `idle_in_transaction_session_timeout` no parameter group `aurora-postgresql17` |
| Aplicação | Driver MySQL, dialeto MySQL | Driver `org.postgresql.Driver` e `PostgreSQLDialect` no perfil `prod` da API |

**Motivo.** O Free plan da conta AWS do grupo bloqueou a criação do Aurora MySQL, e o grupo migrou para o PostgreSQL. Em seguida, o Free plan também bloqueou o Aurora PostgreSQL na configuração padrão: só permitia a *express configuration*, fora da VPC, com autenticação apenas por IAM e sem suporte no provider Terraform. A conta passou então para o plano pago, o que liberou os dois motores. O grupo manteve o PostgreSQL porque a aplicação e a infraestrutura já estavam migradas e testadas, e voltar ao MySQL exigiria recriar o banco e repetir os testes sem ganho para o projeto. A troca preserva o que motivou o ADR-003 (Aurora Serverless v2 com pausa em 0 ACU, banco gerenciado em sub-rede privada) e exigiu apenas troca de driver e dialeto na API, já que o acesso é feito por Spring Data JPA.

**Afeta:** ADR-003 (substituído pelo [ADR-004](adr/004-motor-banco-postgresql.md)), seções 5.1 (componentes), 5.2 (fluxo 1), 5.4 (`rt-private`), 5.5 (matriz), 5.6 (banco de dados), 5.9 (custos) e o diagrama.

**Custo.** A estimativa da Entrega 1 foi feita com Aurora MySQL. Em `sa-east-1`, o Aurora Serverless v2 é cobrado por ACU-hora com o mesmo preço para os dois motores compatíveis, e o armazenamento e as E/S também seguem a mesma tabela, então os valores dos cenários A e B continuam válidos.

**Conta.** Com a saída do Free plan, o risco 5 da Entrega 1 (seção 5.9, item 5: suspensão dos serviços quando o crédito acabar) muda de natureza. Os créditos de US$ 120,00 continuam valendo até 22/01/2027, mas o que passar deles é cobrado no cartão em vez de suspender a conta. A mitigação passa a ser os alertas do AWS Budgets ([`evidencias/budgets-alertas.txt`](evidencias/budgets-alertas.txt)), o NAT sob demanda e a pausa automática do Aurora.

---

## 2. Matriz de security groups

### `sg-lambda`

| Regra | Entrega 1 | Implantado |
|---|---|---|
| Saída TCP para o banco | 3306 → `sg-db` | **5432** → `sg-db` |
| Saída TCP 443 → `0.0.0.0/0` | Prevista | **Removida** |
| Saída UDP/TCP 53 → `10.20.0.2` | Prevista | **Removida** |
| Entrada | Nenhuma | Nenhuma |

### `sg-db`

| Regra | Entrega 1 | Implantado |
|---|---|---|
| Entrada | TCP 3306 ← `sg-lambda` | TCP **5432** ← `sg-lambda` |
| Saída | Nenhuma | Nenhuma |

### Novo: `sg-egress-check`

| Direção | Protocolo | Porta | Destino | Justificativa |
|---|---|---|---|---|
| Saída | TCP | 443 | `0.0.0.0/0` | Usado apenas pela função de teste do fluxo 3 (item 3) |

**Motivo.**
- A Lambda da API não precisa de saída para a internet: os segredos são injetados no deploy (seção 5.6 da Entrega 1). Manter a regra 443 só ampliaria o que um código comprometido poderia fazer (ameaça T6 em [`seguranca.md`](seguranca.md)). Por menor privilégio, a saída 443 foi isolada em um security group próprio da função de teste.
- O tráfego para o resolvedor DNS da Amazon (`10.20.0.2`) não é filtrado por security groups, e a resolução do endpoint do Aurora funciona sem a regra 53.
- O security group padrão da VPC foi esvaziado (`aws_default_security_group` sem regras), o que não constava na Entrega 1.

**Afeta:** seção 5.5 e o rótulo "TCP 443 saída sob demanda" da Lambda no diagrama.

---

## 3. Nova função Lambda `dove-egress-check` (fluxo 3)

**Entrega 1:** o fluxo 3 seria demonstrado pela própria Lambda da API acessando a internet pelo NAT.

**Implantado:** como a API ficou sem saída para a internet (item 2), foi criada uma função Python 3.12 de 128 MB, `dove-egress-check`, nas mesmas sub-redes privadas (`priv-a` e `priv-b`), com o `sg-egress-check`. Ela consulta `https://ifconfig.me/ip` e devolve o IP de origem visto pela internet:

- com `enable_nat = true`, o IP retornado é o Elastic IP do NAT (`terraform output nat_public_ip`);
- com `enable_nat = false`, a chamada esgota o tempo, mostrando que a sub-rede privada não tem saída.

**Motivo:** demonstrar o fluxo 3 (requisito R4 e demonstração D4) sem dar saída à internet para a função que guarda as credenciais do banco.

**Afeta:** seção 5.2 (fluxo 3) e o diagrama.

---

## 4. Acesso administrativo ao banco pela RDS Data API

**Entrega 1:** o acesso administrativo seria só por IAM, via Terraform, AWS CLI e console (ADR-001), sem prever como executar SQL no banco privado.

**Implantado:** o cluster tem a RDS Data API habilitada (`enable_http_endpoint = true`). Um integrante autenticado no IAM executa SQL com `aws rds-data execute-statement`, usando o ARN do cluster (`terraform output aurora_cluster_arn`) e do segredo (`terraform output db_secret_arn`). Nenhuma porta do banco é aberta e não há bastion.

**Motivo:** permitir consultas e correções de dados (por exemplo, promover o primeiro usuário a ADMIN, ver o README) sem contrariar o ADR-001.

**Risco aceito:** quem tiver permissão IAM sobre o cluster e o segredo executa SQL pela internet, o que reduz o risco do banco ao risco das credenciais IAM (ameaças T3 e T7 em [`seguranca.md`](seguranca.md)).

**Afeta:** ADR-001 (complemento, sem mudar a decisão), seção 5.2 (fluxo 2) e seção 5.6 (serviços complementares).

---

## 5. Configuração da Lambda da API

| Parâmetro | Entrega 1 | Implantado | Motivo |
|---|---|---|---|
| Memória | 1536 MB | **2048 MB** (`lambda_memory_mb`) | Na Lambda, a CPU é proporcional à memória. Com 1536 MB, a inicialização do Spring mais a retomada do Aurora chegava perto do limite de 30 s do API Gateway |
| Timeout | Não definido | **29 s** (`lambda_timeout_s`) | Fica abaixo do limite de 30 s do API Gateway |
| Artefato | `.jar` | **`.zip`** com classes e `lib/` (`target/dove-lambda.zip`), gerado pelo `maven-assembly-plugin` | Formato esperado pelo runtime gerenciado Java com SnapStart |
| SnapStart | Previsto | Mantido, controlado pela variável `enable_snapstart`, com `publish = true` e alias `live` | O SnapStart só vale para versões publicadas, por isso o API Gateway e o aquecimento chamam o alias |
| Ajustes da JVM | Não previstos | `JAVA_TOOL_OPTIONS = -XX:+TieredCompilation -XX:TieredStopAtLevel=1` | Reduz o tempo de inicialização em funções curtas |
| Conexão ao banco | Não detalhada | Timeouts JDBC longos e pool Hikari de no máximo 2 conexões, sem conexões ociosas | Tolerar a retomada do Aurora pausado e não impedir a pausa automática |

**Afeta:** seções 5.2, 5.6 e 5.7 e o rótulo da Lambda no diagrama.

---

## 6. Aquecimento agendado

| | Entrega 1 | Implantado |
|---|---|---|
| Horário | Um disparo às 10h50 | A cada 5 minutos, das 11h00 às 14h55 (`cron(0/5 11-14 * * ? *)`, fuso `America/Sao_Paulo`) |
| Alvo | Função Lambda | Alias `live` da Lambda, simulando um `GET /api/usuario/findByUsername` (rota pública que lê o banco sem alterar dados) |
| Situação na Entrega 2 | Desligado (`enable_warmup = false`) | Desligado por padrão, como previsto |

**Motivo:** um único disparo às 10h50 acorda o Aurora, mas ele volta a pausar após 5 minutos sem conexões (`seconds_until_auto_pause = 300`), antes do almoço. Disparos a cada 5 minutos durante o expediente mantêm a Lambda e o banco prontos enquanto há clientes. O custo extra é pequeno, porque o Aurora já ficaria acordado nesse horário pelo uso real.

**Afeta:** seções 5.2 (fluxo 4) e 5.6 e o rótulo do EventBridge no diagrama.

---

## 7. Implantação da aplicação e scripts

| Item | Entrega 1 | Implantado |
|---|---|---|
| Pacote da API | Publicado no S3 por script versionado | Publicado pelo próprio Terraform (`aws_s3_object.api_zip`) em um **bucket de artefatos** criptografado e sem acesso público, que não constava na Entrega 1 |
| Frontend | Sincronizado para o S3 por script versionado | `aws s3 sync` do build do Angular e invalidação do CloudFront, executados manualmente conforme o passo a passo do [README](../README.md#implantação) |
| `nat-on.sh` / `nat-off.sh` | Previstos na seção 5.9 | **Não criados.** O NAT é ligado e desligado pela variável `enable_nat` no `terraform.tfvars`, seguida de `terraform apply`, conforme o README |

**Motivo:** o deploy da API pelo Terraform garante que todo `apply` publique a versão do pacote presente em `infra/artifacts/`, sem um passo separado. Para o front e o NAT, os comandos são curtos e foram documentados no README em vez de virar scripts. Manter `enable_nat` no `terraform.tfvars`, em vez de `-var` na linha de comando, garante que o `terraform plan` sem argumentos não mostre alterações (demonstração D1).

**Afeta:** seções 5.6 (instalação da aplicação) e 5.9 (plano de controle de custos e estratégia adotada).

---

## 8. CloudFront e API Gateway

Itens implantados que a Entrega 1 citava apenas de forma geral:

- **CloudFront Function `spa_rewrite`** (evento `viewer-request`): reescreve as rotas do Angular para `index.html`, permitindo recarregar páginas internas da SPA.
- **Política de cache da API** (`dove-api-sem-cache`): sem cache, repassando o cabeçalho `Authorization` e as query strings. Junto com a origin request policy gerenciada `Managed-AllViewerExceptHostHeader`.
- **Política de cabeçalhos de segurança** (`Managed-SecurityHeadersPolicy`) nos dois comportamentos, para corrigir o achado CKV2_AWS_32 do Checkov ([`seguranca.md`](seguranca.md)).
- **Origem da API** com `origin_protocol_policy = "https-only"` e TLS 1.2.
- **API Gateway:** limite de 20 requisições/s com pico de 50 (`api_throttle_rate` e `api_throttle_burst`) e logs de acesso em `/aws/apigateway/dove-api`, com retenção de 7 dias.

**Afeta:** seção 5.6 (servidor web e proxy).

---

## 9. Aplicação (repositórios `dove-integrador-api` e `dove-integrador-web`)

A revisão de segurança da Entrega 2 encontrou falhas de controle de acesso na API, corrigidas no `dove-integrador-api` (PR `fix/seguranca-usuario`, commit `2a39829`):

- o cadastro público aceitava o perfil `ADMIN` (A1);
- as buscas públicas de usuário expunham o hash da senha, o CPF e o e-mail (A2);
- qualquer usuário logado lia, alterava ou apagava cadastros de outros (A3);
- pedidos, cardápio e ingredientes não verificavam o perfil de quem chamava (A4).

Detalhes, decisão e testes em [`seguranca.md`](seguranca.md), seção 2.1. O frontend não precisou de alteração.

**Consequência operacional:** como o cadastro público passou a criar sempre `CLIENTE`, o primeiro administrador é criado promovendo um usuário pela Data API (item 4), conforme o README.

---

## 10. Adaptações dos requisitos da Entrega 2 ao modelo serverless

Não são divergências da Entrega 1, mas registram como requisitos pensados para máquinas virtuais foram atendidos, com base no ADR-001 (dispensa de instâncias e SSH autorizada pelo professor):

| Requisito | Como foi atendido |
|---|---|
| R5: recurso computacional na sub-rede privada, sem IP público | ENIs da Lambda da API e da `dove-egress-check` em `priv-a` e `priv-b`, sem IP público |
| R6: IP público no recurso de acesso | Não há bastion. A entrada da aplicação é o CloudFront, endereçado por DNS (`app_url`), e o único IP público estático é o Elastic IP do NAT (`nat_public_ip`) |
| R7: SSH só a partir de um CIDR em variável | Não há porta 22 em nenhum security group. O acesso administrativo é por IAM (ADR-001) |
| R8: chave SSH | Não se aplica (sem instâncias) |
| R9: família e tipo da instância em variável | Capacidade parametrizada por variável: `lambda_memory_mb`, `aurora_min_capacity` e `aurora_max_capacity` |
| R11: IPs públicos e privados nos outputs | `nat_public_ip`, `app_url`, `api_gateway_endpoint`, `aurora_endpoint`, sub-redes e security groups. As ENIs da Lambda recebem IPs privados dinâmicos, criados e reciclados pela AWS, por isso não há output de IP privado fixo |
| S1: endurecimento do SSH | Não se aplica (sem SSH). Ver [`seguranca.md`](seguranca.md) |

---

## 11. Alertas de orçamento

**Entrega 1:** três orçamentos no AWS Budgets, com alertas em US$ 10, 30 e 60 (seção 5.9, plano de controle de custos).

**Implantado:** dois orçamentos mensais criados no console, de **US$ 10** e **US$ 60**, cada um com alerta em 85% e 100% do gasto real e em 100% da previsão ([`evidencias/budgets-alertas.txt`](evidencias/budgets-alertas.txt)). O alerta de US$ 30 não foi criado.

**Motivo:** os alertas de 85% e de previsão de cada orçamento já avisam antes de o limite ser atingido (por exemplo, em US$ 8,50 e US$ 51), o que cobre a faixa intermediária que o alerta de US$ 30 cobriria. O gasto real no mês da implantação ficou abaixo de US$ 1.

**Afeta:** seção 5.9 (plano de controle de custos).

---

## 12. Documentação

- **Diagrama.** O diagrama da Entrega 1 (`docs/diagramas/Diagrama de arquitetura.*`) ainda mostra Aurora MySQL na porta 3306, Lambda com 1536 MB e saída TCP 443, aquecimento às 10h50 e não mostra a função `dove-egress-check` nem a Data API. Os itens 1 a 6 desta errata descrevem as diferenças.
- **Nomes de arquivo.** O README da Entrega 1 citava `docs/diagramas/arquitetura.drawio` e `arquitetura.png`, mas os arquivos foram entregues como `Diagrama de arquitetura.drawio`, `Diagrama de arquitetura PNG.png` e `Diagrama de arquitetura.pdf`.
- **`docs/arquitetura.md`** não foi reescrito, para preservar o registro da Entrega 1. As seções afetadas estão indicadas em cada item.
