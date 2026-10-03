# Declaração de Uso de Inteligência Artificial

**Projeto:** Dove Restaurante — Infraestrutura em Nuvem (AWS Serverless)  
**Disciplina:** Projeto Integrador | Uniamérica Descomplica  
**Professor:** Gildomiro Bairros  

---

## 1. Ferramentas Utilizadas
- **Antigravity (Google DeepMind / Gemini):** Utilizado como assistente para organização do backlog e auxílio na estruturação textual de seções da documentação técnica.
- **Claude (Anthropic), via Claude Code:** Utilizado como assistente para discussão das alternativas de arquitetura, apoio no preenchimento da calculadora de preços e extruturação textual de seções da documentação técnica.

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

---

## 3. O que foi Verificado e Corrigido no Conteúdo Gerado
1. **Validação das Definições Técnicas:**
   - Todo o conteúdo textual estruturado pela IA foi revisado para assegurar que representasse com precisão as ideias e decisões deliberadas pelo grupo (como a adoção da arquitetura serverless na AWS e a dispensa de máquinas virtuais).
2. **Ajuste de Concorrência e Horários:**
   - Ajuste de eventuais estimativas de volumetria para refletir com exatidão a operação real do restaurante, mantendo a carga de pico em **10 a 30 usuários simultâneos** e o horário de funcionamento estritamente das **11h00 às 14h30**.
3. **Conferência de Custos e Reescrita dos ADRs:**
   - Os valores da Seção 5.9 foram conferidos na calculadora oficial e no PDF exportado, e as premissas de horas de uso foram revisadas pelo grupo. Os ADRs foram reescritos pelo grupo a partir do rascunho, simplificando o texto e ajustando as decisões ao que foi acordado em equipe.
