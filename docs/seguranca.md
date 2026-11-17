# Segurança (Entrega 2, Parte B)

Este documento reúne os controles de segurança aplicados (S1 a S8), o tratamento dos achados das ferramentas de análise e a análise de ameaças da arquitetura implantada.

**Escopo.** A arquitetura é 100% serverless (ADR-001): não há instâncias EC2, bastion nem porta 22. Os controles pensados para máquinas virtuais (S1, e os requisitos R6 a R9 da Parte A) foram adaptados ou dispensados, com autorização do professor, conforme indicado em cada item. Os recursos citados estão em `infra/`.

---

## 1. Controles aplicados (S1 a S8)

| # | Controle | Situação | Como foi aplicado | Evidência / demonstração |
|---|---|---|---|---|
| S1 | Endurecimento do SSH | **Não aplicável** | Não existem instâncias nem servidor SSH. A administração é feita só por IAM, via Terraform, AWS CLI e console (ADR-001). Nenhum security group libera a porta 22 | `infra/security.tf` e `infra/lambda.tf`: nenhuma regra com porta 22. Dispensa autorizada pelo professor (seção 5.6 de `arquitetura.md`) |
| S2 | Saída restrita | **Aplicado** | `sg-lambda`: única saída é TCP 5432 para o `sg-db` (referência por ID). `sg-db`: nenhuma regra de saída. `sg-egress-check`: única saída é TCP 443, usada só pela função de teste do NAT. O security group padrão da VPC foi esvaziado (`aws_default_security_group`) | `infra/security.tf`, `infra/lambda.tf`, `infra/network.tf`. Console: VPC → Security Groups |
| S3 | HTTPS | **Aplicado** | O CloudFront é a única entrada, com `viewer_protocol_policy = "redirect-to-https"` (HTTP é redirecionado). O certificado é válido, emitido pela AWS para `*.cloudfront.net`. A ligação CloudFront → API Gateway é `https-only` com TLS 1.2 | `infra/frontend.tf`. Demonstração: `curl -v https://<app_url>` e `curl -I http://<app_url>` (retorna 301) |
| S4 | Gestão de segredos | **Aplicado** | A senha do banco e a chave do JWT são geradas pelo Terraform (`random_password`) e guardadas no **Secrets Manager**. Não aparecem no código, em `.tfvars` nem no Git. São injetadas na Lambda como variáveis de ambiente no deploy, para que a aplicação funcione sem NAT (ADR-002) | `infra/database.tf`, `infra/secrets.tf`, `infra/lambda.tf`. Limitação aceita: achado CKV_AWS_173 (seção 2) |
| S5 | Menor privilégio para identidades | **Aplicado** | A role da Lambda tem apenas `AWSLambdaVPCAccessExecutionRole` (criar ENIs e gravar logs). A role do EventBridge pode apenas invocar o alias `live` da API. Só o API Gateway do projeto pode invocar a Lambda (`source_arn`). O bucket do frontend só pode ser lido por esta distribuição do CloudFront (OAC + `AWS:SourceArn`). Nenhuma chave de acesso é gravada em recurso algum | `infra/iam.tf`, `infra/apigateway.tf`, `infra/frontend.tf` |
| S6 | Criptografia em repouso | **Aplicado** | Aurora com `storage_encrypted = true` declarado (os backups automáticos e snapshots herdam). Buckets S3 com `sse_algorithm = "AES256"` declarado. Secrets Manager, logs do CloudWatch e variáveis de ambiente da Lambda são criptografados pelo serviço com chaves gerenciadas pela AWS | `infra/database.tf`, `infra/lambda.tf`, `infra/frontend.tf`. Console: RDS → cluster → *Encryption: Enabled* |
| S7 | Análise automatizada | **Aplicado** | Checkov executado em `infra/` (143 verificações aprovadas, 49 reprovadas, tratadas na seção 2). Após a correção do CKV2_AWS_32, nova execução: 144 aprovadas, 48 reprovadas. Gitleaks 8.30.1 no histórico completo do Git (24 commits com alterações, todas as branches) e nos arquivos atuais: nenhum segredo encontrado | [`evidencias/checkov-infra.txt`](evidencias/checkov-infra.txt) (antes), [`evidencias/checkov-infra-pos-correcao.txt`](evidencias/checkov-infra-pos-correcao.txt) (depois) e [`evidencias/gitleaks.txt`](evidencias/gitleaks.txt) |
| S8 | Proteção da conta (MFA) | **Aplicado** | MFA virtual ativo nos três usuários IAM dos integrantes (Eduardo, Lethicia e Lucas), usados no console e na CLI | [`evidencias/mfa.jpg`](evidencias/mfa.jpg): console IAM → Usuários, coluna MFA = *Virtual (1)* para os três, sem dados sensíveis |

**Observação sobre DNS (S2).** A matriz da Entrega 1 previa uma regra de saída UDP/TCP 53 para o resolvedor da VPC. Ela não foi criada porque o tráfego para o resolvedor da Amazon (`10.20.0.2`) não é filtrado por security groups, e a resolução do endpoint do Aurora funciona sem a regra. Pelo mesmo motivo de menor privilégio, a saída 443 para a internet saiu do `sg-lambda` e foi isolada em um security group próprio da função de teste do NAT. As duas mudanças constam em `errata.md`.

---

## 2. Tratamento dos achados

**Ferramenta:** Checkov 3.4.5 (`checkov -d infra --framework terraform`), executado em 16/11/2026 ([`evidencias/checkov-infra.txt`](evidencias/checkov-infra.txt)) e novamente em 17/11/2026, após a correção do CKV2_AWS_32 ([`evidencias/checkov-infra-pos-correcao.txt`](evidencias/checkov-infra-pos-correcao.txt)).

**Severidade.** A versão aberta do Checkov não informa severidade, por isso o grupo a classificou com o critério abaixo:

| Severidade | Critério |
|---|---|
| Crítica | Permite a um atacante sem credenciais obter privilégio de administrador ou acesso aos dados |
| Alta | Expõe segredo ou dado sensível, ou enfraquece um controle obrigatório (S1 a S8) |
| Média | Reduz a capacidade de detectar, investigar ou recuperar um incidente |
| Baixa | Boa prática de operação ou de custo, sem impacto direto na confidencialidade ou integridade |

### 2.1 Achados de severidade alta ou crítica

| Achado | Severidade | Recurso | Decisão | Justificativa |
|---|---|---|---|---|
| CKV_AWS_173: variáveis de ambiente da Lambda sem chave KMS própria | Alta | `aws_lambda_function.api` | Aceito | A senha do banco e a chave do JWT ficam em variáveis de ambiente, criptografadas em repouso com a chave gerenciada `aws/lambda`, mas legíveis por quem tiver `lambda:GetFunctionConfiguration`. Ler do Secrets Manager em tempo de execução exigiria NAT ligado ou um VPC endpoint de interface (cobrado por hora em cada zona), o que contraria o ADR-002. O mínimo exigido pelo S4 (segredos fora do código e do Git) é atendido. Risco residual: ameaça T3 |
| CKV_AWS_174: CloudFront aceita TLS abaixo de 1.2 | Alta | `aws_cloudfront_distribution.main` | Aceito | Com o certificado padrão `*.cloudfront.net` a AWS não permite fixar a versão mínima de TLS. Fixar TLS 1.2 exige domínio próprio e certificado no ACM, fora do orçamento. Navegadores atuais negociam TLS 1.2 ou 1.3. O trecho CloudFront → API Gateway já exige TLS 1.2 |
| CKV2_AWS_42: CloudFront sem certificado próprio | Alta | `aws_cloudfront_distribution.main` | Aceito | Mesma causa do CKV_AWS_174. O certificado da AWS é válido e confiável pelos navegadores, o que atende ao S3 |
| CKV_AWS_309: rota do API Gateway sem autorizador | Alta | `aws_apigatewayv2_route.api` | Aceito | A autenticação é feita pela aplicação (Spring Security com JWT), não pelo API Gateway. Login e cadastro precisam ser públicos. Um autorizador JWT no API Gateway duplicaria a validação. Risco residual: depende de a aplicação proteger cada rota (ameaças T1 e T2) |
| A1 (revisão manual): cadastro público aceita o campo `tipo` | Crítica | `POST /api/usuario` (API) | **Corrigido** | `UsuarioService.save` gravava o `tipo` enviado pelo cliente, e a rota é `permitAll`: qualquer pessoa podia se cadastrar como `ADMIN`. Agora o `UsuarioController` força `tipo = CLIENTE` quando quem chama não é um ADMIN autenticado, e descarta `id` e `pedidos` do corpo (um `id` enviado sobrescreveria um usuário existente). Testes em `UsuarioControllerTest`. Ameaça T1 |
| A2 (revisão manual): consulta pública de usuário devolve o hash da senha | Alta | `GET /api/usuario/findByUsername` e `findByEmail` (API) | **Corrigido** | As rotas eram `permitAll` e retornavam a entidade inteira, incluindo `senha` (hash BCrypt), CPF, e-mail e pedidos. Agora a senha é `WRITE_ONLY` (nunca serializada em nenhuma resposta), e as buscas devolvem só `{"existe": true}` ou 404, exceto para o próprio usuário ou um ADMIN. As rotas continuam públicas porque a tela de cadastro as usa para checar duplicidade, e o aquecimento (`infra/warmup.tf`) segue funcionando sem alteração. Ameaça T2 |
| A3 (revisão manual): qualquer usuário logado lê, altera ou apaga o cadastro de outros | Alta | `GET/PUT/DELETE /api/usuario/**` (API) | **Corrigido** | Bastava estar autenticado (inclusive como CLIENTE recém-cadastrado) para listar todos os usuários com CPF e e-mail, editar ou excluir qualquer conta e trocar a senha de outro usuário (`PUT /senha/{id}` era `permitAll`). Agora listagem, relatórios e exclusão exigem `ADMIN` (`SecurityConfig`), e as rotas por `id` só atendem o próprio usuário ou um ADMIN (403 nos demais casos). Ameaças T1 e T2 |
| A4 (revisão manual): pedidos, cardápio e ingredientes sem controle por perfil | Alta | `/api/pedidos/**`, `/api/cardapios/**`, `/api/ingredientes/**` (API) | **Corrigido** | Qualquer cliente logado podia criar, alterar ou apagar cardápios e ingredientes, listar os pedidos de todos (o front filtrava só na tela), alterar ou apagar o pedido de outra pessoa e criar pedido em nome de outro usuário. O `GET /api/cardapios/hoje` também devolvia nome e username de quem fez cada pedido do dia. Agora escrita em cardápio e ingredientes exige `FUNCIONARIO` ou `ADMIN`. O cliente só lista, lê, altera e apaga os próprios pedidos, e o pedido é sempre criado em nome dele. Indicadores de pedidos ficam restritos à equipe, e o cardápio deixa de serializar o usuário dos pedidos. Testes em `PedidoControllerTest`. Ameaça T1 |

### 2.2 Demais achados (média e baixa)

| Achado | Severidade | Recurso(s) | Decisão | Justificativa |
|---|---|---|---|---|
| CKV2_AWS_57: segredos sem rotação automática | Média | `aws_secretsmanager_secret.db_master`, `.jwt` | Aceito | A rotação exige uma Lambda rotacionadora com acesso ao banco e um novo deploy da API para pegar o valor. O ambiente vive poucas semanas e é recriado com segredos novos a cada `destroy`/`apply` |
| CKV_AWS_139: Aurora sem proteção contra exclusão | Média | `aws_rds_cluster.main` | Aceito | O enunciado exige `terraform destroy` ao final. Em produção seria `true`. Ameaça T3 |
| CKV2_AWS_8: Aurora fora de um plano do AWS Backup | Média | `aws_rds_cluster.main` | Aceito | A política mínima (Parte D) usa o backup automático nativo do Aurora, com retenção de 1 dia. O AWS Backup entra na política conservadora em `backup.md` |
| CKV_AWS_162: autenticação IAM do banco desativada | Média | `aws_rds_cluster.main` | Aceito | A aplicação usa usuário e senha via JDBC. A autenticação IAM exigiria gerar tokens na Lambda, a cada 15 minutos |
| CKV_AWS_68, CKV2_AWS_47: CloudFront sem WAF | Média | `aws_cloudfront_distribution.main` | Aceito | O WAF custa a partir de US$ 5/mês por Web ACL mais regras. A mitigação adotada é o limite de requisições do API Gateway (20 req/s, pico de 50). Ameaça T4 |
| CKV2_AWS_32: CloudFront sem política de cabeçalhos de segurança | Média | `aws_cloudfront_distribution.main` | **Corrigido** | Associada a política gerenciada `Managed-SecurityHeadersPolicy` aos dois comportamentos (frontend e `/api/*`), sem custo. As respostas passam a trazer `Strict-Transport-Security`, `X-Frame-Options: SAMEORIGIN`, `X-Content-Type-Options: nosniff`, `Referrer-Policy` e `X-XSS-Protection`. O achado não aparece na segunda execução do Checkov. Evidência na AWS: [`evidencias/teste-cabecalhos-e-autorizacao.txt`](evidencias/teste-cabecalhos-e-autorizacao.txt) |
| CKV_AWS_324, CKV2_AWS_27: Aurora sem exportação de logs e de consultas | Média | `aws_rds_cluster.main` | Aceito | Gera volume e custo no CloudWatch. Os acessos ficam registrados nos logs do API Gateway e da Lambda |
| CKV_AWS_86, CKV_AWS_18: CloudFront e S3 sem log de acesso | Média | CloudFront, `aws_s3_bucket.frontend`, `.artifacts` | Aceito | Os logs de acesso do API Gateway (`/aws/apigateway/dove-api`) registram IP, método, rota e status de cada chamada à API. O conteúdo estático é público por natureza |
| CKV2_AWS_11: VPC sem flow logs | Média | `aws_vpc.main` | Aceito | Custo de ingestão no CloudWatch. A VPC só tem ENIs da Lambda e o Aurora, com regras restritas por security group |
| CKV_AWS_158: logs sem chave KMS própria | Baixa | 3 grupos de log | Aceito | O CloudWatch já criptografa os logs com chave da AWS. Uma chave própria (CMK) custa US$ 1/mês cada |
| CKV_AWS_149, CKV_AWS_327, CKV_AWS_145: criptografia sem chave KMS própria | Baixa | Segredos, Aurora, buckets | Aceito | A criptografia está ativa (S6) com chaves gerenciadas pela AWS. A chave própria só traria controle sobre a política da chave, a um custo de US$ 1/mês por chave |
| CKV_AWS_338: logs retidos por menos de 1 ano | Baixa | 3 grupos de log | Aceito | Retenção de 7 dias, adequada a um ambiente acadêmico de poucas semanas |
| CKV_AWS_272: Lambda sem assinatura de código | Baixa | `aws_lambda_function.api`, `.egress_check` | Aceito | O pacote é gerado e publicado pelo próprio grupo via Terraform. A assinatura exige o AWS Signer no processo de build |
| CKV_AWS_116, CKV_AWS_50: Lambda sem fila de erros (DLQ) e sem X-Ray | Baixa | Lambdas | Aceito | As invocações são síncronas (API Gateway). DLQ só vale para invocações assíncronas. O X-Ray é dispensável para o volume do projeto |
| CKV_AWS_115: Lambda sem limite de concorrência reservada | Baixa | Lambdas | Aceito | Contas novas têm cota de concorrência baixa, e reservar parte dela pode impedir o deploy. O limite de requisições do API Gateway cumpre o papel |
| CKV_AWS_118, CKV_AWS_353: RDS sem monitoramento avançado e Performance Insights | Baixa | `aws_rds_cluster_instance.writer` | Aceito | Recursos de diagnóstico de desempenho, com custo adicional |
| CKV_AWS_310: CloudFront sem origem de failover | Baixa | `aws_cloudfront_distribution.main` | Aceito | Tratado na proposta de alta disponibilidade (`alta-disponibilidade.md`) |
| CKV_AWS_374: CloudFront sem restrição geográfica | Baixa | `aws_cloudfront_distribution.main` | Aceito | Clientes podem acessar de fora do Brasil, por exemplo em viagem |
| CKV_AWS_21, CKV_AWS_144, CKV2_AWS_61, CKV2_AWS_62: S3 sem versionamento, replicação, ciclo de vida e notificações | Baixa | `aws_s3_bucket.frontend`, `.artifacts` | Aceito | Os dois buckets guardam apenas artefatos reproduzíveis pelo código (build do Angular e pacote da API). Não há dado de usuário em S3 |

**Resumo:** 49 achados do Checkov (4 de severidade alta, todos aceitos com justificativa; nenhum crítico; 1 de severidade média corrigido, o CKV2_AWS_32) e 4 achados da revisão manual da API (1 crítico e 3 altos), todos corrigidos no repositório `dove-integrador-api` (branch `fix/seguranca-usuario`).

---

## 3. Análise de ameaças

| # | Ameaça | Ativo afetado | Controle aplicado | Risco residual |
|---|---|---|---|---|
| T1 | Um visitante se cadastra pela rota pública `POST /api/usuario` enviando `"tipo": "ADMIN"` e passa a gerenciar usuários e pedidos | Contas de usuário, cardápio e pedidos | Perfil forçado como `CLIENTE` no cadastro público (A1). Gestão de usuários restrita a `ADMIN` e rotas por `id` restritas ao próprio usuário (A3). Cardápio e ingredientes só alterados pela equipe, e pedidos só acessíveis ao dono ou à equipe (A4) | Um administrador com credencial vazada continua tendo acesso total. As regras de autorização são testadas no controller, mas não há teste de integração da cadeia de filtros do Spring Security |
| T2 | Um atacante consulta `GET /api/usuario/findByUsername?username=...` com nomes comuns, confirma quais usuários existem e obtém o hash BCrypt da senha para quebrá-lo offline | Senhas, CPF e e-mail dos usuários | A resposta pública só informa se o usuário existe; hash, CPF e e-mail não são mais expostos (A2). BCrypt torna a quebra lenta. O API Gateway limita a 20 req/s | A enumeração de usuários continua possível (200 ou 404). Senhas fracas: o cadastro aceita senhas a partir de 3 caracteres, e não há bloqueio após tentativas de login erradas |
| T3 | A chave de acesso IAM de um integrante vaza (máquina comprometida, chave colada em chat). O atacante lê as variáveis de ambiente da Lambda, obtém a senha do banco e a chave do JWT, ou apaga o cluster junto com os backups automáticos | Toda a conta AWS: banco, backups e segredos | MFA nas contas (S8). Nenhuma credencial no repositório (`.gitignore`, Gitleaks). Alertas do AWS Budgets para uso anômalo | As chaves de acesso de longa duração na máquina dos integrantes não exigem MFA para uso na CLI. Sem `deletion_protection` (CKV_AWS_139), quem tem acesso pode apagar o banco e os backups automáticos do Aurora |
| T4 | Um bot dispara milhares de requisições à API (pelo CloudFront ou direto no endpoint `execute-api`, que é público) para derrubar o serviço ou gerar custo | Disponibilidade da API e crédito da conta | Limite do API Gateway (20 req/s, pico de 50). Aurora limitado a 2 ACU. Alertas do AWS Budgets em US$ 10, 30 e 60 | Sem WAF, o limite vale para todos os clientes juntos: um ataque também bloqueia os usuários legítimos durante o almoço |
| T5 | Quem obtém a `SECRET_KEY` do JWT (pela ameaça T3 ou pelo `tfstate`) forja um token com perfil `ADMIN`, sem precisar de senha | Todas as rotas autenticadas da API | Chave aleatória de 64 caracteres gerada pelo Terraform, fora do código e do Git. Tokens expiram em 2 horas | Não há rotação automática (CKV2_AWS_57). Um token forjado vale até a chave ser trocada, o que exige novo `apply` |
| T6 | Uma dependência vulnerável da API (como o caso Log4Shell) permite executar código na Lambda, e o atacante tenta enviar dados do banco para um servidor externo | Dados do banco | O `sg-lambda` só permite saída para o banco na porta 5432. Mesmo com o NAT ligado, a Lambda da API não alcança a internet (S2) | O código executado ainda pode ler e alterar o banco com as credenciais da aplicação, que é o usuário administrador do Aurora |
| T7 | Um atacante tenta conectar direto ao PostgreSQL, pela internet ou a partir de outro recurso da VPC | Banco de dados | Aurora sem IP público, em sub-rede privada sem rota de entrada. O `sg-db` só aceita conexões do `sg-lambda` | A Data API está habilitada (`enable_http_endpoint`): quem tiver permissão IAM e o ARN do segredo executa SQL pela internet. Isso se reduz à ameaça T3 |
| T8 | O `terraform.tfstate`, que contém a senha do banco e a chave do JWT em texto claro, é enviado ao Git ou compartilhado entre integrantes por mensagem | Segredos da aplicação | `*.tfstate` no `.gitignore`. Gitleaks no histórico (S7) | O state fica no disco local de um integrante, sem criptografia nem controle de acesso. Um backend remoto (S3 criptografado) resolveria, ao custo de um bucket criado fora do Terraform |

---

## 4. Pendências antes da tag `entrega-2`

- [x] Corrigir A1 a A4 na API (`dove-integrador-api`, branch `fix/seguranca-usuario`). O aquecimento não precisou mudar.
- [x] Fazer merge da branch, gerar o pacote (`mvn package`), copiar para `infra/artifacts/dove-lambda.zip` e aplicar.
- [x] Corrigir CKV2_AWS_32 (política de cabeçalhos de segurança no CloudFront) e rodar o Checkov de novo. Esse é o "achado corrigido" da demonstração D5.
- [x] Aplicar a correção na AWS (`terraform apply`) e salvar a saída de `curl -sI https://<app_url>` mostrando os cabeçalhos: [`evidencias/teste-cabecalhos-e-autorizacao.txt`](evidencias/teste-cabecalhos-e-autorizacao.txt).
- [x] Rodar o Gitleaks no histórico e salvar em `evidencias/gitleaks.txt` (nenhum segredo encontrado).
- [x] Salvar a captura do MFA em `evidencias/mfa.jpg`.
- [x] Registrar em `errata.md` as mudanças na matriz de security groups (porta 5432 no lugar da 3306, saída 443 e 53 removidas do `sg-lambda`, novo `sg-egress-check`).
