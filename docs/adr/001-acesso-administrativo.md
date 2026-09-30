# ADR-001: Estratégia de acesso administrativo

No contexto de uma arquitetura serverless na AWS em que os recursos são gerenciados e o banco fica em sub-rede privada sem IP público,
diante da necessidade de os integrantes terem acesso administrativo aos recursos e conteúdos,
decidimos garantir o acesso por meio de AWS IAM (Identity and Access Management) e operado via Terraform e AWS CLI,
e descartamos soluções via ssh como Bastion Host e SSM,
para delegar o acesso via IAM e eliminar a necessidade de uma instância extra para manter e porta 22, 
aceitando que a segurança do ambiente passa a depender inteiramente das credenciais IAM de cada integrante.