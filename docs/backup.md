# Backup (Entrega 2, Parte D)

Este documento define o que precisa de backup, as metas de recuperação, a política conservadora que o grupo recomendaria para operar o sistema de verdade e a política mínima que está efetivamente configurada na nuvem, segundo os itens B1 a B7. A decisão do grupo está registrada no [ADR-006](adr/006-estrategia-backup.md).

As duas políticas têm papéis diferentes. A **conservadora (GFS)** existe apenas no plano, com análise de custo para 12 meses. A **mínima** está configurada por Terraform e é demonstrada na apresentação, com custo próximo de zero.

## B1: Inventário

O que precisa de backup é apenas o que não pode ser recriado a partir do código.

| Ativo | Precisa de backup | Justificativa |
|---|---|---|
| Banco Aurora PostgreSQL (`dove`) | **Sim** | Único dado gerado por pessoas: usuários, ingredientes, cardápios do dia e pedidos. Não existe em lugar nenhum além do banco. |
| `infra/terraform.tfstate` | **Sim** | Fica local, na máquina de quem executa o `apply`, e não vai para o Git. Perdê-lo não derruba o ambiente, mas quebra o vínculo entre o código e os recursos criados: o `destroy` deixa de funcionar e seria preciso importar cada recurso. Contém a senha do banco e a chave do JWT. |
| Build do frontend (bucket `dove-frontend-*`) | Não | Reproduzível com `npm ci && npx ng build` a partir do `dove-integrador-web`. |
| Pacote da Lambda (bucket `dove-artifacts-*`) | Não | Reproduzível com `mvn clean package` a partir do `dove-integrador-api`. |
| Segredos no Secrets Manager | Não | Gerados uma única vez pelo Terraform (`random_password`) e guardados no state; um ambiente recriado do zero recebe segredos novos. Ver a dependência registrada abaixo. |
| Logs do CloudWatch | Não | Retenção de 7 dias, sem valor de negócio depois da análise. Não entram no RPO. |
| Infraestrutura e código da aplicação | Não | Versionados no Git, que é o backup. |

A aplicação não recebe upload de arquivo do usuário. O cardápio é texto e referência a ingredientes cadastrados, não imagem. Se isso mudar, o bucket que receber os arquivos entra neste inventário com versionamento ativado.

**Dependência entre o banco e o segredo.** A senha do banco é gerada pelo Terraform e vive no state. Restaurar o banco de uma cópia antiga sem o state correspondente produz um cluster cuja senha não é a que está no Secrets Manager. Por isso o state entra no inventário mesmo sendo, em tese, reproduzível: ele e o banco precisam ser recuperados como um par.

## B2: RPO e RTO

| Meta | Valor | Justificativa |
|---|---|---|
| **RPO** (quanto se pode perder) | 5 minutos | O backup contínuo do Aurora permite restaurar a qualquer segundo dentro da janela de retenção; 5 minutos é a granularidade prática. O dado em risco é o pedido em andamento, que o atendente tem no balcão e consegue relançar. |
| **RTO** (quanto se pode demorar) | 1 hora | A restauração point-in-time do Aurora cria um cluster novo (15 a 20 minutos), e apontar a aplicação para ele é um `terraform apply` (5 a 10 minutos). O restante é margem. O atendimento ocorre das 11h00 às 14h30; uma hora de indisponibilidade significa voltar à comanda de papel por um turno, sem perda de venda. |

Há uma terceira dimensão que não se confunde com o RPO: a **janela de detecção**, ou seja, há quanto tempo atrás se consegue voltar. É nela que as duas políticas divergem — 12 meses na conservadora, 1 dia na mínima.

## B3: Política conservadora (GFS)

| Geração | Frequência | Momento de promoção | Retenção | Classe de armazenamento |
|---|---|---|---|---|
| **Son** (filho) | Diária, às 06:00 UTC (03:00 em Brasília) | — | 7 dias | Backup padrão do Aurora |
| **Father** (pai) | Semanal | A cópia de domingo é retida como semanal | 5 semanas | AWS Backup, armazenamento quente |
| **Grandfather** (avô) | Mensal | A semanal do último domingo do mês é retida como mensal | 12 meses | AWS Backup, armazenamento quente |

A janela das 06:00 UTC fica fora do horário de atendimento e depois do fechamento do caixa do dia anterior, então cada cópia diária contém um dia comercial completo.

**Mecanismo por ativo.**

O banco é um serviço gerenciado, então a geração diária usa o backup automático do próprio Aurora, e as gerações semanal e mensal usam snapshots agendados por um plano do AWS Backup com duas regras, uma por geração.

O `terraform.tfstate` passa a um backend S3 com versionamento ativado. As gerações viram regras de ciclo de vida sobre as versões antigas do objeto, com a mesma retenção da tabela acima. O bucket de state é a exceção prevista no enunciado: pode ser criado fora do Terraform.

**Consistência.** Os snapshots do Aurora são tirados na camada de armazenamento, que é transacional, e a restauração executa a recuperação normal do PostgreSQL. Não é o caso de um snapshot de disco de máquina virtual, que seria apenas *crash-consistent*. Não é necessário parar a aplicação para gerar a cópia.

**Não há classe fria para banco relacional.** O AWS Backup oferece transição para armazenamento frio apenas para EFS, DynamoDB e alguns outros recursos. Para RDS e Aurora a calculadora oficial expõe somente o campo de dias em armazenamento quente, e a documentação do serviço não lista a camada fria entre os destinos de um snapshot de banco relacional.

A consequência é direta na política: as gerações semanal e mensal pagam exatamente o mesmo preço por GB, e a única forma de baratear a mensal seria exportar o snapshot para o S3 em formato Parquet e aplicar regra de ciclo de vida para o Glacier. O grupo não adotou esse caminho porque ele troca um mecanismo gerenciado por uma rotina de exportação própria, com agendamento, permissão de escrita no bucket e um formato de restauração diferente do snapshot nativo. Para o volume deste projeto, a economia não paga a complexidade, e isso fica registrado como a primeira otimização a avaliar se o banco crescer.

## B4: Armazenamento

As três gerações ficam em `sa-east-1`: a diária no armazenamento de backup do próprio Aurora, e a semanal e a mensal em um *backup vault* do AWS Backup. O armazenamento de backup do Aurora é replicado entre as três zonas da região, então a perda de uma zona não compromete nenhuma cópia, e o requisito de manter o backup fora da instância, em outra zona, está atendido.

Não há cópia em outra região. O AWS Backup permite copiar o *vault* para `us-east-1`, mas isso aproximadamente dobra o custo de armazenamento e acrescenta transferência de dados, para cobrir apenas o cenário de indisponibilidade de uma região inteira. É a mesma conta que o [ADR-005](adr/005-estrategia-alta-disponibilidade.md) já fez ao recusar a réplica do banco em outra zona: um restaurante que atende três horas e meia por dia não perde venda por uma indisponibilidade dessa ordem. Manter a cópia entre regiões aqui contradiria a decisão de disponibilidade que o próprio grupo tomou.

Todas as cópias são criptografadas. Os snapshots herdam a chave do cluster, que tem `storage_encrypted = true` declarado no código (controle S6). O acesso ao *vault* é restrito por IAM: apenas as identidades do grupo podem criar, restaurar ou excluir cópias (controle S5). Nenhuma credencial de acesso fica gravada dentro de instância, porque não há instância.

## B5: Responsabilidade compartilhada

| Ativo | O que a AWS garante | O que é responsabilidade do grupo |
|---|---|---|
| Banco Aurora | Executar o backup automático na janela configurada, replicar o armazenamento entre três zonas, manter a criptografia e disponibilizar a restauração point-in-time | Definir o período de retenção, decidir quando restaurar, não excluir o cluster sem avaliar o `skip_final_snapshot`, e proteger as credenciais |
| Snapshots e *vault* | Durabilidade das cópias e aplicação do ciclo de vida | Definir as regras do plano, a retenção de cada geração e quem tem permissão no *vault* |
| Buckets S3 | Durabilidade do objeto armazenado | Ativar versionamento onde for necessário e definir as regras de ciclo de vida |
| `terraform.tfstate` | Nada. O arquivo está fora da AWS, na máquina de um integrante | Tudo: guardar, versionar e proteger |
| Conteúdo lógico do banco | Nada. Um `DELETE` indevido é replicado para todas as réplicas em segundos | Tudo: é exatamente o cenário que justifica backup em vez de alta disponibilidade |

A última linha é o ponto central desta parte. A alta disponibilidade descrita em [`alta-disponibilidade.md`](alta-disponibilidade.md) protege contra falha de infraestrutura, não contra erro de operação. E o Terraform recria a infraestrutura, mas não recria os dados.

## B6: Política mínima configurada

Está configurada por Terraform, em `infra/database.tf`, e aplica apenas a geração **Son** do GFS.

| Item | Configuração |
|---|---|
| Mecanismo | Backup automático do Aurora, o mecanismo aceito para serviço gerenciado |
| Retenção | 1 dia (`db_backup_retention_days`, com validação no `variables.tf` limitando o valor a 1 ou 2) |
| Janela | 06:00–07:00 UTC, igual à da geração diária da política conservadora (`db_backup_window`) |
| Criptografia | `storage_encrypted = true` no cluster; as cópias herdam a chave |
| Marcação | `copy_tags_to_snapshot = true`, para que as cópias carreguem as tags `projeto` e `grupo` (R10) |
| Custo | Próximo de zero: o Aurora não cobra pelo armazenamento de backup até o tamanho do cluster, e o banco do projeto está abaixo de 1 GB |

**Evidência.** São três provas, e elas respondem a perguntas diferentes.

A primeira mostra que a política está configurada — retenção, janela e criptografia:

```bash
aws rds describe-db-clusters --region sa-east-1 \
  --db-cluster-identifier dove-aurora \
  --query "DBClusters[0].[BackupRetentionPeriod,PreferredBackupWindow,StorageEncrypted]"
```

A segunda mostra que **existe cópia restaurável agora**, e é a prova mais importante:

```bash
aws rds describe-db-clusters --region sa-east-1 \
  --db-cluster-identifier dove-aurora \
  --query "DBClusters[0].[EarliestRestorableTime,LatestRestorableTime]"
```

O intervalo entre esses dois horários é a janela de restauração point-in-time. Ele aparece poucos minutos depois da criação do cluster e prova que o backup contínuo está rodando, com dado gravado e recuperável. É também a prova direta do RPO declarado no B2.

A terceira lista os snapshots automáticos já materializados:

```bash
aws rds describe-db-cluster-snapshots --region sa-east-1 \
  --db-cluster-identifier dove-aurora --snapshot-type automated \
  --query "DBClusterSnapshots[].[DBClusterSnapshotIdentifier,SnapshotCreateTime,StorageEncrypted,PercentProgress]"
```

> O primeiro snapshot automático só aparece depois da primeira janela das 06:00 UTC posterior à criação do cluster, então essa terceira consulta pode voltar vazia em um ambiente criado há poucas horas. As duas primeiras funcionam desde o início, e a segunda já satisfaz o requisito de cópia existente. Ainda assim, o ambiente da apresentação é criado com antecedência e a evidência é capturada durante os testes, como o enunciado recomenda.

No console, as mesmas informações ficam em **RDS → Bancos de dados → `dove-aurora` → aba Manutenção e backups**, que mostra o período de retenção, a janela e o horário de restauração mais antigo. Os snapshots automáticos ficam em **RDS → Snapshots → aba Sistema**.

A saída das três consultas fica em [`evidencias/backup-politica-minima.txt`](evidencias/backup-politica-minima.txt), e as capturas do console em [`evidencias/backup-politica-minima.png`](evidencias/backup-politica-minima.png), com a aba Manutenção e backups, e [`evidencias/backup-criptografia.png`](evidencias/backup-criptografia.png), com a chave de criptografia do cluster. O bloco abaixo gera o arquivo de texto:

```bash
{
  echo "# Politica minima de backup - coletado em $(date -u +%FT%TZ)"
  echo "## Retencao, janela e criptografia"
  aws rds describe-db-clusters --region sa-east-1 --db-cluster-identifier dove-aurora \
    --query "DBClusters[0].[BackupRetentionPeriod,PreferredBackupWindow,StorageEncrypted]" --output text
  echo "## Janela de restauracao point-in-time"
  aws rds describe-db-clusters --region sa-east-1 --db-cluster-identifier dove-aurora \
    --query "DBClusters[0].[EarliestRestorableTime,LatestRestorableTime]" --output text
  echo "## Snapshots automaticos"
  aws rds describe-db-cluster-snapshots --region sa-east-1 --db-cluster-identifier dove-aurora \
    --snapshot-type automated \
    --query "DBClusterSnapshots[].[DBClusterSnapshotIdentifier,SnapshotCreateTime,StorageEncrypted]" --output text
} > docs/evidencias/backup-politica-minima.txt
```

**O que a política mínima não protege.** A janela de detecção cai de 12 meses para 1 dia. Um erro descoberto 48 horas depois de acontecer não tem como ser desfeito: não existe cópia daquele momento. Também não há cópia fora da região, então uma indisponibilidade regional prolongada deixa o banco inacessível. E, como o `terraform destroy` previsto para depois da apresentação usa `skip_final_snapshot = true`, os backups automáticos são apagados junto com o cluster — comportamento desejado no ambiente acadêmico e inaceitável em produção. Durante o trabalho o ambiente não é destruído entre as sessões (só o NAT é ligado e desligado, seção 5.9 da Entrega 1), e é por isso que já existe cópia automática para a demonstração.

## B7: Custos

| Política | Período | Custo |
|---|---|---|
| Conservadora (GFS) | 12 meses | US$ 1,48 no ano, chegando a US$ 0,23 no mês 12 — ver [`custos/backup-gfs-12-meses.xlsx`](custos/backup-gfs-12-meses.xlsx) |
| Mínima configurada | Período de trabalho da Entrega 2 | US$ 0,00 |

A política mínima não gera custo porque o Aurora inclui armazenamento de backup gratuito até 100% do tamanho do cluster, e o banco do projeto fica abaixo desse limite com folga.

A planilha traz as premissas adotadas, os valores unitários obtidos na calculadora oficial e o custo mês a mês, do mês 1 ao 12. O volume inicial não é estimado: são os 0,048 GB medidos no cluster em 20/11/2026 pela métrica `VolumeBytesUsed` do CloudWatch, registrada em [`evidencias/backup-politica-minima.txt`](evidencias/backup-politica-minima.txt). O crescimento de 0,01 GB por mês é premissa declarada, derivada de cerca de 60 pedidos por dia com três itens em média. O crescimento do custo vem do acúmulo das cópias até cada geração atingir sua retenção: a diária estabiliza em uma semana, a semanal em pouco mais de um mês, e a mensal só estabiliza no mês 12.

**Qual parâmetro mais influencia o custo anual.** A retenção da geração *Grandfather*, a mensal. Ela responde por 42% do custo do ano, contra 39% da semanal e 19% da diária.

A razão é que as três gerações pagam quase o mesmo preço por GB, já que não existe camada fria para banco relacional. Sem diferença de preço, vence em custo quem acumula mais volume, e a mensal é a única que acumula durante os doze meses inteiros: no mês 12 ela sozinha guarda 1,24 GB, contra 0,79 GB da semanal e 1,11 GB da diária — e a diária ainda abate a franquia gratuita do Aurora. Essa proporção não depende do tamanho do banco: ela se mantém igual se o volume inicial dobrar ou cair pela metade.

A conclusão foi conferida contra a calculadora oficial. Modelando a mesma política diretamente no AWS Backup, com 100 GB de dados primários, a AWS atribui US$ 21,95 dos US$ 34,73 mensais à geração mensal, ou 63%. A diferença de proporção vem das premissas de crescimento, mas a ordem é a mesma.

Reduzir a retenção mensal de 12 para 6 meses corta cerca de metade dessa linha. O que se perderia: a capacidade de voltar a qualquer mês do último ano. O caso concreto é um erro silencioso de dados — um preço cadastrado errado, um cardápio duplicado — percebido só no fechamento anual. Com 6 meses, o primeiro semestre já não existe mais. Para um restaurante que precisa guardar registro fiscal por prazos longos, é uma redução que o grupo não recomenda.
