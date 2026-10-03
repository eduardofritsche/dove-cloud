# dove-cloud

Projeto de infraestrutura em nuvem do **Dove Restaurante**, sistema de gestão de pedidos, cardápio diário e cozinha do restaurante Dove, implantado na **AWS** com arquitetura serverless.

| Item | Informação |
|---|---|
| Instituição | Uniamérica Descomplica |
| Disciplina | Projeto Integrador: Trabalho Prático de Infraestrutura em Nuvem |
| Professor | Gildomiro Bairros |
| Provedor / Região | AWS · `sa-east-1` (São Paulo) |
| Infraestrutura como código | Terraform |
| Entrega atual | **Entrega 1:** Projeto de Arquitetura e Decisões de Infraestrutura (tag `entrega-1`) |

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
                         └─ /api/*  → API Gateway (HTTP API) → Lambda (Spring Boot)
                                                                  │ 3306
VPC vpc-dove 10.20.0.0/16 · sa-east-1                             ▼
├─ pub-a   10.20.1.0/24   (sa-east-1a)  NAT Gateway + Elastic IP
├─ priv-a  10.20.10.0/24  (sa-east-1a)  ENIs da Lambda · Aurora Serverless v2 (writer)
└─ priv-b  10.20.11.0/24  (sa-east-1b)  ENIs da Lambda · DB subnet group

Administrador ──(2) IAM (MFA)──► Terraform / AWS CLI / Console
Lambda ──(3) rt-private──► NAT Gateway ──► Internet Gateway ──► Internet
```

| Camada | Serviço AWS | Exposição |
|---|---|---|
| Entrada e CDN | Amazon CloudFront | Pública (HTTPS) |
| Frontend | Amazon S3 | Privado, acessado apenas pelo CloudFront |
| Entrada da API | Amazon API Gateway (HTTP API) | Acessado pelo CloudFront |
| Backend | AWS Lambda (Java 17 + Spring Boot) | Sem IP público; ENIs nas sub-redes privadas |
| Banco de dados | Amazon Aurora MySQL Serverless v2 | Sub-rede privada, acessível apenas pelo `sg-lambda` |
| Saída da sub-rede privada | NAT Gateway | Criado sob demanda (`enable_nat`) |
| Aquecimento | Amazon EventBridge Scheduler | — |

Os três fluxos numerados correspondem aos exigidos pelo enunciado: **(1)** usuário final acessando a aplicação, **(2)** acesso administrativo (adaptado para IAM, sem SSH; ver [ADR-001](docs/adr/001-acesso-administrativo.md)) e **(3)** recurso privado acessando a internet pelo NAT.

## Aplicação

O código da aplicação fica em repositórios separados:

| Componente | Tecnologia | Repositório |
|---|---|---|
| Frontend | Angular 19 | `dove-integrador-web` |
| Backend | Java 17, Spring Boot 3.5.4, Spring Data JPA | `dove-integrador-api` |

## Estrutura do repositório

```
/
├── README.md              # Este arquivo: identificação do grupo e visão geral
├── IA.md                  # Declaração de uso de IA
├── docs/
│   ├── arquitetura.md     # Seções 5.1 a 5.7, 5.9 e 5.10 do enunciado
│   ├── adr/
│   │   ├── 001-acesso-administrativo.md
│   │   ├── 002-saida-internet-subrede-privada.md
│   │   └── 003-localizacao-banco.md
│   ├── diagramas/
│   │   ├── arquitetura.drawio
│   │   └── arquitetura.png
│   └── custos/
│       └── estimativa.pdf # Export da AWS Pricing Calculator (cenário A)
└── infra/                 # Código Terraform (Entrega 2)
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [Arquitetura](docs/arquitetura.md) | Descrição da aplicação, endereçamento IP, rotas, regras de segurança, tecnologias, custos, riscos |
| [ADR-001](docs/adr/001-acesso-administrativo.md) | Estratégia de acesso administrativo |
| [ADR-002](docs/adr/002-saida-internet-subrede-privada.md) | Saída para a internet da sub-rede privada |
| [ADR-003](docs/adr/003-localizacao-banco.md) | Localização do banco de dados |
| [Diagrama](docs/diagramas/arquitetura.png) | Diagrama de arquitetura ([fonte editável](docs/diagramas/arquitetura.drawio)) |
| [Estimativa de custos](docs/custos/estimativa.pdf) | Export da calculadora oficial da AWS |
| [Declaração de uso de IA](IA.md) | Ferramentas de IA usadas e o que foi revisado |

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

Os procedimentos de implantação (`terraform apply`), deploy da aplicação e destruição do ambiente serão documentados aqui na Entrega 2.
