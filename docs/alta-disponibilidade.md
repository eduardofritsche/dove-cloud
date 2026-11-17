# Alta disponibilidade (Entrega 2, Parte C)

Este documento analisa a disponibilidade da arquitetura implantada segundo os requisitos H1 a H7 e estima o custo de eliminar os pontos únicos de falha que restam. A decisão do grupo está registrada no [ADR-005](adr/005-estrategia-alta-disponibilidade.md).

## Resumo da decisão

O grupo **não criou um diagrama separado de alta disponibilidade** e mantém o [diagrama da Entrega 1](diagramas/Diagrama%20de%20arquitetura%20PNG.png) como referência, pelos seguintes motivos:

1. **A maior parte da arquitetura já é multi-AZ por construção.** CloudFront, S3, API Gateway, Lambda, Secrets Manager e EventBridge são serviços regionais ou globais que a AWS opera em várias zonas de disponibilidade. As ENIs da Lambda já estão em duas zonas (`priv-a` em `sa-east-1a` e `priv-b` em `sa-east-1b`), e o armazenamento do Aurora já guarda seis cópias em três zonas. Não existe instância de aplicação a duplicar nem balanceador a acrescentar.
2. **Os dois pontos únicos de falha que restam são aceitos, não eliminados.** São a instância writer única do Aurora e o NAT Gateway único, os dois em `sa-east-1a`. Eliminá-los praticamente dobraria o custo mensal (seção [Custo](#custo-da-alta-disponibilidade)), e o perfil de uso do restaurante não justifica esse aumento.
3. **Com essas decisões, a "proposta de alta disponibilidade" coincide com a arquitetura já desenhada.** Um segundo diagrama repetiria o primeiro, mudando apenas os rótulos. As únicas diferenças de uma versão totalmente redundante, que são um segundo NAT e uma réplica do Aurora em `sa-east-1b`, estão descritas nos itens H3 e H4 e custeadas abaixo.

O diagrama da Entrega 1 está desatualizado em alguns rótulos (motor do banco, porta, memória da Lambda e horário do aquecimento). As diferenças estão na [errata](errata.md) e não alteram a análise de disponibilidade.

---

## H1: distribuição em duas zonas e plano de endereçamento

A arquitetura usa duas zonas de disponibilidade de `sa-east-1`. Nenhuma sub-rede nova é necessária, porque a proposta não acrescenta recursos de rede (H3).

| Sub-rede | CIDR | Zona | O que fica nela | Papel na disponibilidade |
|---|---|---|---|---|
| `pub-a` | `10.20.1.0/24` | `sa-east-1a` | NAT Gateway e Elastic IP (quando `enable_nat = true`) | Saída para a internet; não participa do atendimento ao usuário |
| `priv-a` | `10.20.10.0/24` | `sa-east-1a` | ENIs da Lambda; writer do Aurora | Atende requisições; banco ativo |
| `priv-b` | `10.20.11.0/24` | `sa-east-1b` | ENIs da Lambda; parte do DB subnet group | Atende requisições se `sa-east-1a` falhar; local de recriação do writer |

Fora da VPC, distribuídos pela própria AWS:

| Serviço | Abrangência | Consequência para a aplicação |
|---|---|---|
| CloudFront | Global (pontos de presença) | A entrada não depende de nenhuma zona da região |
| S3 (frontend e artefatos) | Regional, objetos replicados em pelo menos três zonas | O frontend continua disponível com uma zona fora |
| API Gateway (HTTP API) | Regional, multi-AZ | A API continua recebendo requisições com uma zona fora |
| Lambda | Regional; executa nas sub-redes configuradas | Com `sa-east-1a` fora, as execuções passam a usar só as ENIs de `priv-b` |
| Secrets Manager, EventBridge, CloudWatch | Regionais, multi-AZ | Sem ponto único de falha por zona |

## H2: balanceamento de carga e health check

Não existe balanceador de carga (ALB) nem grupo de autoescalonamento, porque não há instâncias. O papel que o requisito descreve é cumprido por serviços gerenciados:

| Função do balanceador | Equivalente na arquitetura |
|---|---|
| Ponto de entrada único | CloudFront (`/*` para o S3 e `/api/*` para o API Gateway) |
| Distribuir requisições entre várias instâncias | O serviço Lambda cria um ambiente de execução por requisição simultânea e distribui os ambientes entre as ENIs das duas zonas. Não há número fixo de "instâncias": com 10 a 30 usuários simultâneos, a Lambda escala sozinha |
| Autoescalonamento | Lambda (concorrência) e Aurora Serverless v2 (de 0 a 2 ACU) escalam conforme a carga, sem configuração de grupo |
| Health check | Feito pela própria AWS: um ambiente de execução da Lambda que falha é descartado e substituído, e a próxima requisição vai para um ambiente saudável. Requisições que falham voltam como erro 5xx no API Gateway e ficam registradas nos logs de acesso (`/aws/apigateway/dove-api`) |
| Proteção contra sobrecarga | Limite do API Gateway de 20 requisições/s, com pico de 50 |

**Limitação aceita:** não há health check configurado pelo grupo que retire uma zona de serviço. Se a falha for do banco (H4), a Lambda continua sendo invocada e devolve erro até o banco voltar.

## H3: estratégia de NAT

**Decisão: NAT compartilhado, um único NAT Gateway em `pub-a`, criado sob demanda (`enable_nat`), sem NAT por zona.**

| Opção | Custo adicional (operação contínua) | Consequência |
|---|---|---|
| Um NAT por zona (`nat-a` em `pub-a` e `nat-b` em uma nova `pub-b`, `10.20.2.0/24`, cada sub-rede privada com sua tabela de rotas) | ≈ US$ 71,63/mês (NAT mais IPv4 público) | A saída para a internet de `priv-b` sobrevive à falha de `sa-east-1a` |
| **NAT compartilhado (adotado)** | — | Se `sa-east-1a` falhar, `priv-b` também perde a saída para a internet |

**Por que a consequência é aceitável:** a Lambda da API **não usa o NAT**. O `sg-lambda` só permite saída para o banco na porta 5432, e os segredos são injetados no deploy (ADR-002). O NAT só é usado pela função de teste `dove-egress-check`, que existe para demonstrar o fluxo 3. Um segundo NAT custaria quase o mesmo que o primeiro para proteger um caminho que o atendimento ao cliente não usa.

## H4: estratégia para o banco de dados

**Decisão: manter a instância writer única do Aurora em `sa-east-1a`, sem réplica, apoiada na durabilidade do armazenamento do Aurora e em um procedimento de recuperação documentado.**

O que já existe:

- **Armazenamento multi-AZ:** o volume do Aurora é mantido pela AWS com seis cópias em três zonas. A falha de uma zona não perde dados confirmados; perde apenas a instância de computação.
- **DB subnet group nas duas zonas** (`priv-a` e `priv-b`): uma nova instância pode ser criada em `sa-east-1b` sem mudar a rede.
- **Backup automático diário com retenção de 1 dia** (política mínima da Parte D), para falhas lógicas como dados apagados por engano.

Recuperação se `sa-east-1a` cair: alterar só o `availability_zone` da instância writer (`aws_rds_cluster_instance.writer`, em `infra/database.tf`) para `sa-east-1b` e executar `terraform apply`. A variável `az_a` não deve ser trocada, porque ela também posiciona as sub-redes. A instância nova se conecta ao mesmo volume, e a aplicação volta a funcionar sem nenhuma mudança na Lambda, porque o endpoint do cluster é o mesmo. O tempo estimado de recuperação, já registrado na Entrega 1, é de **10 a 15 minutos**.

Alternativa avaliada e não adotada: uma **réplica Aurora Serverless v2 em `sa-east-1b`** com prioridade de failover 0 ou 1. A AWS promoveria a réplica automaticamente em cerca de 30 segundos a 1 minuto. O custo em operação contínua dobraria a computação do banco (≈ US$ 182,50/mês a mais, seção [Custo](#custo-da-alta-disponibilidade)).

## H5: estado da aplicação fora da instância

A aplicação já é sem estado (*stateless*), então qualquer ambiente de execução da Lambda, em qualquer zona, atende qualquer requisição:

| Tipo de estado | Onde fica |
|---|---|
| Sessão do usuário | **No próprio cliente**, como token JWT assinado (válido por 2 horas). O servidor não guarda sessão: cada requisição traz o token no cabeçalho `Authorization`, e qualquer ambiente da Lambda valida o token com a mesma chave (`SECRET_KEY`, injetada a partir do Secrets Manager) |
| Dados de negócio | Aurora (usuários, cardápios, ingredientes, pedidos) |
| Arquivos enviados | Não existem. A aplicação não tem upload de arquivos. Se um dia tiver, por exemplo uma foto de prato, o destino seria o S3, nunca o disco efêmero (`/tmp`) da Lambda |
| Frontend | S3, servido pelo CloudFront |

## H6: tratamento dos pontos únicos de falha da seção 5.10 da Entrega 1

| # | Ponto único de falha ou risco (Entrega 1, seção 5.10) | Tratamento | Justificativa |
|---|---|---|---|
| 1 | Instância writer única do Aurora em `sa-east-1a` | **Aceito** | O armazenamento já é multi-AZ, então a falha de zona não perde dados. A recuperação manual leva de 10 a 15 minutos. Uma réplica dobraria o custo do banco (H4) |
| 2 | Latência de retomada do Aurora pausado somada ao cold start da Lambda | **Mitigado**, não é falha de zona | SnapStart na Lambda e aquecimento agendado a cada 5 minutos no horário do restaurante (`enable_warmup`, desligado durante a Entrega 2). No dia da apresentação, `aurora_min_capacity = 0.5` evita a pausa |
| 3 | Ausência de saída para a internet com o NAT destruído | **Aceito** | A API não depende de saída para a internet (H3). Só o teste do fluxo 3 é afetado |
| 4 | Dependência exclusiva das credenciais IAM | **Mitigado** | MFA no usuário raiz e nos três usuários IAM (S8), nenhuma credencial no repositório (Gitleaks sem achados, S7). Não é ponto de falha de zona |
| 5 | Esgotamento do crédito e suspensão da conta | **Mitigado** | Alertas do AWS Budgets, NAT sob demanda, pausa automática do Aurora e `terraform destroy` após a apresentação |

## H7: fluxos da Entrega 1 com uma zona fora

Comportamento de cada fluxo se `sa-east-1a` ficar indisponível (o pior caso, porque concentra o writer e o NAT):

| Fluxo | Caminho | Com `sa-east-1a` fora |
|---|---|---|
| 1. Usuário final | Navegador → CloudFront → S3 (frontend) e CloudFront → API Gateway → Lambda (ENIs em `priv-a` e `priv-b`) → Aurora writer | O frontend continua no ar. A Lambda passa a executar só em `priv-b`. **As chamadas que usam o banco falham até o writer ser recriado em `sa-east-1b` (10 a 15 min)**; depois disso, o fluxo volta inteiro |
| 2. Acesso administrativo | Integrante com IAM e MFA → Terraform, AWS CLI, console e RDS Data API | Continua disponível, porque IAM, console e APIs da AWS são regionais ou globais. É por esse fluxo que a recuperação do writer é feita |
| 3. Saída para a internet | `dove-egress-check` em `priv-a`/`priv-b` → `rt-private` → NAT em `pub-a` → Internet Gateway | Indisponível enquanto `sa-east-1a` estiver fora. Não afeta o atendimento (H3) |
| 4. Aquecimento | EventBridge Scheduler → alias `live` da Lambda → Aurora | O agendador continua disparando. As chamadas ao banco falham até a recuperação do writer, assim como no fluxo 1 |

---

## Custo da alta disponibilidade

**Fonte dos preços:** preços unitários da AWS Pricing Calculator usados na Entrega 1 ([`custos/estimativa.pdf`](custos/estimativa.pdf), região `sa-east-1`, consulta de 29/09/2026), em operação contínua (730 h/mês), mesma base do cenário A. Os itens acrescentados foram calculados com esses mesmos preços por hora.

| Versão | Custo mensal estimado | Variação |
|---|---:|---:|
| Arquitetura implantada (Entrega 1, cenário A) | US$ 256,99 | — |
| Versão totalmente redundante (réplica do Aurora e NAT por zona) | ≈ US$ 511,03 | **+ 99%** |

Itens que causam o aumento:

| Item acrescentado | Cálculo | US$/mês | Parcela do aumento |
|---|---|---:|---:|
| Réplica Aurora Serverless v2 em `sa-east-1b` | 1 ACU × 730 h × US$ 0,25 (o armazenamento é compartilhado com o writer e não aumenta) | 182,50 | 72% |
| Segundo NAT Gateway (`pub-b`) | 730 h × US$ 0,093 | 67,89 | 27% |
| IPv4 público do segundo NAT | 730 h × US$ 0,005 | 3,65 | 1% |
| Nova sub-rede `pub-b` e tabelas de rota por zona | Sem cobrança | 0,00 | — |
| **Total acrescentado** | | **254,04** | 100% |

Com a estratégia de operação adotada (Aurora pausado fora do horário e NAT sob demanda), a réplica também pausaria, e o acréscimo cairia para algo próximo de US$ 21/mês, o mesmo valor da redução do Aurora na seção 5.9 da Entrega 1. Mas nessa estratégia o próprio NAT não fica ligado, então a redundância de NAT deixa de fazer sentido.

### O custo se justifica?

**Não, para o perfil de uso do restaurante descrito na seção 5.1 da Entrega 1.**

- **O sistema só é usado 3h30 por dia** (11h00 às 14h30), com 10 a 30 usuários simultâneos. Uma falha de zona da AWS é rara, e para afetar o restaurante ela precisaria acontecer justamente nesse intervalo.
- **O impacto de uma falha é contornável.** Durante os 10 a 15 minutos de recuperação, o restaurante continua funcionando: a cozinha anota pedidos no balcão e os lança depois. Não há perda de dados confirmados, porque o armazenamento do Aurora já é multi-AZ.
- **O NAT redundante não protege o atendimento,** porque a API não usa o NAT (H3). Seriam US$ 71,63/mês sem benefício para o cliente.
- **A réplica dobraria o custo do componente mais caro** (72% do aumento) para reduzir a recuperação de 10–15 minutos para cerca de 1 minuto, numa aplicação sem requisito de disponibilidade contratual.

A redundância passaria a se justificar se o restaurante operasse o dia todo, recebesse pedidos de entrega por aplicativo (em que indisponibilidade significa pedido perdido) ou passasse a atender várias unidades. Nesse caso, a primeira mudança seria a réplica do Aurora (H4), e o NAT por zona só entraria se a API passasse a depender de serviços externos.
