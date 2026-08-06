# Otimização de Forecast de Matéria-Prima Importada

📌 O Desafio de Negócio
O time de Planejamento de Necessidades de Materiais (MRP) sofria com um processo altamente moroso e manual para gerenciar o forecast de matérias-primas importadas. Diariamente, a equipe extraía múltiplos relatórios sistêmicos para consolidar dados em pesadas planilhas de Excel. Além do alto custo em horas operacionais, essa arquitetura descentralizada abria margem para rupturas de estoque ou superávit de insumos importados, o que impactava diretamente o fluxo de caixa e o planejamento fabril.

🎯 O Objetivo
* Eliminar a dependência de planilhas locais para projeção de consumo.
* Centralizar variáveis de cálculo: posição de estoque, ordens de produção (abertas e programadas) e pedidos de compra.
* Viabilizar uma visão de *Rolling Forecast* mensal de maneira automatizada e sistêmica.
* Entregar uma base de dados modelada e otimizada, pronta para ingestão em ferramentas de BI.

📐 Arquitetura do Fluxo de Dados
```mermaid
graph LR
    A["ERP (Módulo MRP/PCP)"] -->|Extração Bruta| B["SQL Pipeline Engine"]
    B -->|Limpeza & Split| C["Modelagem de Insumos"]
    B -->|Lateral Joins| D["Expansão Temporal"]
    C --> E["Motor de Cálculo"]
    D --> E
    E -->|Running Totals| F["Visão Consolidada"]
    F -->|Conexão Direta| G["Ferramenta de BI (Dashboard)"]
```
## 🛠️ A Solução Técnica

Modularização Avançada com CTEs: O fluxo foi dividido logicamente (Base de matrizes, cálculo de demandas, unificação temporal) para facilitar a manutenção e leitura.

Manipulação de Arrays (Cross Join & Multiset): Utilização de REGEXP_SUBSTR combinada com geração dinâmica de linhas via CONNECT BY LEVEL para processar dados armazenados em listas delimitadas por vírgula no banco de origem.

Expansão Temporal (LATERAL JOIN): Abordagem otimizada para projetar meses futuros gerando o "esqueleto" do calendário automaticamente, sem depender de uma dimensão de tempo estática.

Window Functions (SUM OVER, LAG): Empregadas para calcular o saldo acumulado (Running Total) e resgatar saldos iniciais projetados, com processamento em memória muito superior a sub-queries correlacionadas.

## 🚀 Impacto Esperado (ou Real)

Eficiência Operacional: Redução radical do tempo gasto em tarefas operacionais, mitigando a consolidação de planilhas.

Maior Acuracidade Estratégica: Projeção confiável do "Estoque Projetado" considerando as compras pendentes e a produção em fila, essencial para matérias-primas com alto Lead Time (importadas).

Escalabilidade & Governança: Centralização da lógica da "verdade do dado" dentro do Banco de Dados, permitindo que a camada semântica no BI foque exclusivamente em visualizações e cruzamentos de alto nível.
