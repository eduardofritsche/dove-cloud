# ADR-003: Localização do banco de dados

No contexto de uma API Spring Boot com Spring Data JPA escrita para MySQL 8, modelo relacional e uso concentrado no horário de almoço do restaurante (11h00 às 14h30),
diante da necessidade de persistir os dados sem expô-los à internet, reaproveitar o código existente sem reescrita e pagar apenas pelas horas em que o sistema é usado,
decidimos usar o Amazon Aurora MySQL-Compatible Serverless v2 (versão 3.08 ou superior, faixa de 0 a 2 ACU, pausa automática após 5 minutos sem conexões), com um único writer na sub-rede privada `priv-a`, DB subnet group cobrindo `priv-a` e `priv-b` e acesso na porta 3306 permitido apenas ao `sg-lambda`,
e descartamos o Amazon RDS for MySQL, o MySQL instalado em uma instância EC2 na sub-rede privada e o Amazon DynamoDB,
para não pagar computação de banco fora do horário de uso, delegar backup, criptografia e atualizações à AWS e manter a camada JPA sem alterações,
aceitando que o Aurora Serverless v2 não tem nível gratuito, que a retomada após a pausa leva ~15 segundos e pode estourar o limite de 30 s do API Gateway se coincidir com o cold start da Lambda (exigindo aquecimento agendado), que a Lambda precisa ficar dentro da VPC para alcançá-lo, e que o writer único em `sa-east-1a` é ponto único de falha, com recuperação de ~10 minutos se a instância ou a zona falhar.
