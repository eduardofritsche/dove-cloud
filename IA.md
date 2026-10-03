# Declaração de Uso de Inteligência Artificial

**Projeto:** Dove Restaurante — Infraestrutura em Nuvem (AWS Serverless)  
**Disciplina:** Projeto Integrador | Uniamérica Descomplica  
**Professor:** Gildomiro Bairros  

---

## 1. Ferramentas Utilizadas
- **Antigravity (Google DeepMind / Gemini):** Utilizado como assistente para organização do backlog e auxílio na estruturação textual de seções da documentação técnica.
- **Claude (Anthropic), via Claude Code:** Utilizado como assistente para discussão das alternativas de arquitetura, apoio no preenchimento da calculadora de preços e estruturação textual de seções da documentação técnica.

---

## 2. Partes do Trabalho em que a IA foi Utilizada
1. **Organização e Planejamento das Atividades:**
   - Apoio na extração dos requisitos do edital e organização cronológica do backlog de tarefas do Trello.
2. **Estruturação da Documentação de Riscos e Limitações (Seção 5.10):**
   - Auxílio na redação e organização textual dos tópicos da Seção 5.10 de `docs/arquitetura.md`. As ideias, a identificação dos pontos únicos de falha e as decisões técnicas da infraestrutura foram integralmente concebidas pelo grupo.
3. **Estruturação Documental das Decisões de Arquitetura:**
   - Auxílio em estruturar e traduzir em formato de documentação técnica clara as ideias e decisões arquiteturais propostas e definidas pela equipe.
4. **Estimativa de Custos, ADRs, Tabelas de Rota e README:**
   - Comparação entre as opções de arquitetura e auxilio na estimativa de custos (Seção 5.9).
   - Auxílio nas redações dos ADRs 001 a 003, da Seção 5.4 (Tabelas de Rota) e do `README.md`.
5. **Plano de Endereçamento IP (Seção 5.3):**
   - Auxílio na organização e na lapidação do texto final da seção, a partir da topologia de rede e dos blocos CIDR definidos pelo grupo. A IA foi consultada para esclarecimento de dúvidas pontuais sobre o comportamento da AWS — como a quantidade de endereços reservados por sub-rede e a exigência de duas zonas de disponibilidade no DB subnet group do Aurora —, cujas respostas foram posteriormente conferidas na documentação oficial do provedor.
6. **Tabela de Tecnologias (Seção 5.6):**
   - Auxílio na estruturação e na revisão gramatical do texto final da seção. A escolha do provedor, da região, das versões e de cada tecnologia empregada foi deliberada pelo grupo; a IA contribuiu na organização das justificativas já definidas e no esclarecimento de dúvidas sobre equivalência de serviços entre provedores.

**Não houve uso de IA** na elaboração do diagrama de arquitetura (Seção 5.2), construído pelo grupo no draw.io, nem na execução ou configuração de qualquer recurso na conta AWS.

---

## 3. O que foi Verificado e Corrigido no Conteúdo Gerado
1. **Validação das Definições Técnicas:**
   - Todo o conteúdo textual estruturado pela IA foi revisado para assegurar que representasse com precisão as ideias e decisões deliberadas pelo grupo (como a adoção da arquitetura serverless na AWS e a dispensa de máquinas virtuais).
2. **Ajuste de Concorrência e Horários:**
   - Ajuste de eventuais estimativas de volumetria para refletir com exatidão a operação real do restaurante, mantendo a carga de pico em **10 a 30 usuários simultâneos** e o horário de funcionamento estritamente das **11h00 às 14h30**.
3. **Conferência de Custos e Reescrita dos ADRs:**
   - Os valores da Seção 5.9 foram conferidos na calculadora oficial e no PDF exportado, e as premissas de horas de uso foram revisadas pelo grupo. Os ADRs foram reescritos pelo grupo a partir do rascunho, simplificando o texto e ajustando as decisões ao que foi acordado em equipe.
4. **Conferência de Versões e Limites de Serviço (Seções 5.3 e 5.6):**
   - Todas as versões informadas na Seção 5.6 e os limites técnicos citados na Seção 5.3 foram verificados pelo grupo diretamente na documentação oficial da AWS antes da entrega, por se tratar de informação sujeita a desatualização. Também foi corrigida nomenclatura de outro provedor de nuvem remanescente da fase inicial do projeto, quando o grupo ainda avaliava alternativas antes de definir a AWS.
