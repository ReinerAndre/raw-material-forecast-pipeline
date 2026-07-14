```markdown
# Guia de Execução e Uso: Motor de Forecast MRP

Este documento detalha as dependências e o comportamento da extração desenvolvida. 

## 1. Pré-Requisitos e Ambiente
* **Banco de Dados:** Oracle Database (requer suporte a funções regulares como `REGEXP_SUBSTR` e `LATERAL` joins introduzidos no Oracle 12c+).
* **Permissões:** Acesso de leitura (SELECT) concedido às tabelas de ERP de produção, almoxarifado, pedidos de compras e atributos de itens (`dim_item_accessory`, `fact_inventory_balances`, `fact_production_orders`, etc.).

## 2. Como Executar
O script foi encapsulado em um grande bloco de `CTE (Common Table Expressions)`. Para utilizá-lo, basta acionar a query SQL na ferramenta de ETL/ELT de sua preferência ou criar uma `MATERIALIZED VIEW` / `VIEW` no Data Warehouse para que a ferramenta de Data Visualization (Power BI, Tableau, Metabase) possa se conectar de forma nativa.

*Dica de Performance:* Em ambientes de produção muito robustos, avalie materializar as etapas de `saldo_op_aberta` e `saldo_op_prog` temporariamente.

## 3. Dicionário de Dados Final (Output)
A query final retorna uma estrutura granular projetada ao nível de "Matriz de Acessório vs Mês". 

| Coluna | Descrição da Métrica |
| :--- | :--- |
| `empresa_id` | Identificador único da empresa. |
| `acessorio_matriz` | Código agrupador do material importado. |
| `mes_referencia` | Data truncada no primeiro dia do mês. Utilizada como eixo de tempo no BI. |
| `op_Aberta` | Volume (Kg) de matéria-prima comprometida em OPs abertas. |
| `op_prog` | Volume (Kg) de matéria-prima programada em fila na etapa produtiva alvo. |
| `mil_mes` | Custo projetado financeiro das vendas (se aplicável/mapeado no histórico). |
| `saldo_inicial` | Cálculo contínuo baseado no estoque do mês anterior. |
| `forecast_mes` | Consumo (em Kg) previsto de matéria-prima para o mês. |
| `compra_mes` | Entradas planejadas via Pedidos de Compra. |
| `refile` | Resíduo de produção contabilizado (se houver devolução de sobra). |
| `saldo_final` | *Saldo Inicial + (Compras + Refile) - Forecast de Consumo*. Métrica fundamental para identificar riscos de ruptura de estoque. |
```
