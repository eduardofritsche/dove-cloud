# ADR-002: Saída para a internet da sub-rede privada

No contexto de uma função Lambda conectada a sub-redes privadas acessando o Aurora,
diante da necessidade de um NAT gerenciado para essa entrega (necessário para conectar as VMs dentro de um sub-rede privada à Internet, mas não usamos VM nesse projeto),
decidimos usar um NAT Gateway gerenciado em sub-rede pública, criado e destruído pelo Terraform,
e descartamos um NAT em instância EC2 (fck-nat) e VPC endpoints,
para usar um NAT gerenciado, mantido pela AWS, confiável e escalável,
aceitando que tenha um custo fixo alto, cobrado mesmo sem uso, o que nos obriga a usá-lo poucas vezes e destruí-lo logo em seguida.