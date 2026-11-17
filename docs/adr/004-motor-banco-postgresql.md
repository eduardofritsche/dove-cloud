# ADR-004: Motor do banco de dados (Aurora PostgreSQL)

**Status:** aceita (Entrega 2). Substitui o [ADR-003](003-localizacao-banco.md) quanto ao motor; a localização do banco (sub-rede privada, writer único em `priv-a`, DB subnet group em `priv-a` e `priv-b`) continua a mesma.

No contexto da implantação da Entrega 2 na conta AWS do grupo, que usa o Free plan, em que a criação de clusters Aurora MySQL é bloqueada e o único motor Aurora liberado é o PostgreSQL,
diante da necessidade de manter o que motivou o ADR-003 (banco relacional gerenciado em sub-rede privada, com pausa em 0 ACU fora do horário do restaurante) sem trocar de conta nem de modelo de cobrança,
decidimos usar o Amazon Aurora PostgreSQL-Compatible Serverless v2 (versão 17.9, faixa de 0 a 2 ACU, pausa automática após 5 minutos sem conexões), com acesso na porta 5432 permitido apenas ao `sg-lambda` e a RDS Data API habilitada para acesso administrativo por IAM,
e descartamos manter o Aurora MySQL em outra conta sem o Free plan, o Amazon RDS for MySQL ou PostgreSQL em instância provisionada e o MySQL ou PostgreSQL instalado em uma instância EC2,
para continuar pagando computação de banco apenas nas horas de uso, manter backup, criptografia e atualizações delegados à AWS e limitar a mudança na aplicação à troca de driver e dialeto, já que o acesso é feito por Spring Data JPA,
aceitando que a decisão do ADR-003 deixou de valer quanto ao motor e precisou ser registrada em errata, que consultas escritas para o MySQL precisam ser revisadas (a consulta `mediaPedidosPorMes` trocou `FUNCTION('MONTH', ...)` por `EXTRACT(MONTH FROM ...)`), que o `banco.sql` do repositório da API, escrito para MySQL, não é mais o script de referência (o esquema é criado pelo Hibernate com `ddl-auto=update`), e que os demais trade-offs do ADR-003 continuam: sem nível gratuito para o Aurora, retomada de ~15 s após a pausa e writer único em `sa-east-1a` como ponto único de falha.
