WITH 
-- ===================================================================================
-- 1. BASE DE ITENS MATRIZ: Identifica a relação entre produtos agrupadores e insumos
-- ===================================================================================
cte_item_matriz AS (
    SELECT ace.empresa_id,
           ace.codigo_item AS acessorio_matriz,
           ace.descricao AS ds_acessorio_matriz,
           ace.status AS sit_acessorio_matriz,
           ace.tipo_item,
           ace.tipo_ficha,
           ace.item_agrupador,
           MAX(CASE WHEN attr.atributo_id = 10788 THEN SUBSTR(attr.valor_padrao, 1, INSTR(attr.valor_padrao, ' - ') - 1) END) AS mp_princ,
           MAX(CASE WHEN attr.atributo_id = 10789 THEN attr.valor_padrao END) AS versao_princ,
           MAX(CASE WHEN attr.atributo_id = 10790 THEN attr.valor_padrao END) AS mp_equiv,
           MAX(CASE WHEN attr.atributo_id = 10791 THEN attr.valor_padrao END) AS versoes_equiv
      FROM erp.dim_item_accessory ace
     INNER JOIN erp.dim_item_attributes attr
        ON attr.empresa_id = ace.empresa_id
       AND attr.codigo_item = ace.codigo_item 
     WHERE ace.empresa_id = 6 
       AND ace.tipo_item = 20
       AND ace.codigo_item NOT LIKE '%/%'
     GROUP BY ace.empresa_id, ace.codigo_item, ace.descricao, ace.status, 
              ace.tipo_item, ace.tipo_ficha, ace.item_agrupador
),

-- ===================================================================================
-- 2. SPLIT DE INSUMOS: Expande múltiplas versões de matéria-prima separadas por vírgula
-- ===================================================================================
cte_matriz_split AS (
    SELECT m.empresa_id,
           m.acessorio_matriz,
           m.mp_princ AS insumo,
           TRIM(REGEXP_SUBSTR(m.versao_princ, '[^,]+', 1, t.column_value)) AS versao
      FROM cte_item_matriz m
     CROSS JOIN TABLE(CAST(MULTISET(
             SELECT LEVEL FROM dual 
             CONNECT BY LEVEL <= REGEXP_COUNT(m.versao_princ, ',') + 1
           ) AS sys.odcinumberlist)) t
     WHERE m.versao_princ IS NOT NULL
),
cte_matriz_split_equiv AS (
    SELECT m.empresa_id,
           m.acessorio_matriz,
           m.mp_equiv AS insumo,
           TRIM(REGEXP_SUBSTR(m.versoes_equiv, '[^,]+', 1, t.column_value)) AS versao
      FROM cte_item_matriz m
     CROSS JOIN TABLE(CAST(MULTISET(
             SELECT LEVEL FROM dual 
             CONNECT BY LEVEL <= REGEXP_COUNT(m.versoes_equiv, ',') + 1
           ) AS sys.odcinumberlist)) t
     WHERE m.versoes_equiv IS NOT NULL
),
cte_agrupa_insumos AS (
    SELECT empresa_id, acessorio_matriz, insumo || '/' || versao AS mp
      FROM cte_matriz_split 
    UNION ALL
    SELECT empresa_id, acessorio_matriz, 
           CASE WHEN versao IS NULL THEN NULL ELSE insumo || '/' || versao END AS mp
      FROM cte_matriz_split_equiv
     WHERE insumo IS NOT NULL
),

-- ===================================================================================
-- 3. CÁLCULO DE SALDOS: Coleta posições de estoque, previsão de consumo e ordens (Compras/Produção)
-- ===================================================================================
saldo_estoque_forecast AS (
    SELECT m.empresa_id,
           m.acessorio_matriz,
           SUM(erp.fn_convert_uom(s.empresa_id, s.item_id, s.versao_id, 'KG', s.quantidade, 'I')) AS qtd_saldo_kg                                                          
      FROM erp.fact_inventory_balances s
     INNER JOIN erp.dim_warehouse dep
        ON dep.empresa_id = s.empresa_id
       AND dep.codigo_deposito = s.deposito_id
       AND dep.flag_calculo_mrp = 'S'
     INNER JOIN cte_agrupa_insumos m
        ON s.empresa_id = m.empresa_id
       AND (s.item_id || '/' || s.versao_id = m.mp or
            s.item_id||'i' || '/' || s.versao_id = m.mp)
     WHERE s.quantidade > 0
     GROUP BY m.empresa_id, m.acessorio_matriz
),
saldo_mes_forecast AS (
    SELECT hist.empresa_id, 
           hist.codigo_item,
           ace.item_agrupador AS acessorio_matriz,
           hist.data_execucao AS data_fim,  
           ace.tipo_ficha,
           SUM(hist.valor_venda) AS mil_mes,
           SUM(hist.custo_producao) AS kg_mes       
      FROM erp.fact_accessory_history hist
     INNER JOIN erp.dim_item_accessory ace
        ON ace.empresa_id = hist.empresa_id
       AND ace.codigo_item = hist.codigo_item
       AND ace.tipo_item = 20
     WHERE hist.empresa_id = 6 
       AND hist.tipo_historico IN (22, 23)    
       AND TRUNC(SYSDATE) BETWEEN hist.data_previsao AND hist.data_execucao
     GROUP BY hist.empresa_id, hist.codigo_item, hist.data_execucao, ace.tipo_ficha, ace.item_agrupador
),
saldo_oc_forecast AS (
    SELECT s.empresa_id,
           m.acessorio_matriz,
           s.item_id,
           s.versao_id,
           s.data_previsao_entrega,
           SUM(s.quantidade) AS qtd_compra
      FROM erp.fact_purchase_orders s
     INNER JOIN cte_agrupa_insumos m
        ON s.empresa_id = m.empresa_id
       AND s.item_id || '/' || s.versao_id = m.mp
     WHERE s.status_pedido IN ('P')
     GROUP BY s.empresa_id, m.acessorio_matriz, s.item_id, s.versao_id, s.data_previsao_entrega
),
cte_acessorio_refile AS (
    SELECT ace.empresa_id,
           ace.codigo_item AS acessorio_matriz,
           MAX(CASE WHEN attr.atributo_id = 160019 THEN attr.valor_padrao END) AS fct_vinc       
      FROM erp.dim_item_accessory ace
     INNER JOIN erp.dim_item_attributes attr
        ON attr.empresa_id = ace.empresa_id
       AND attr.codigo_item = ace.codigo_item 
     WHERE ace.empresa_id = 6 
       AND ace.tipo_item = 20
       AND ace.tipo_ficha = 41
     GROUP BY ace.empresa_id, ace.codigo_item
),
saldo_refile_forecast AS (
    SELECT ace.empresa_id,
           cte.fct_vinc AS acessorio_matriz,
           ace.codigo_item,
           TRUNC(ace.data_execucao, 'MM') AS mes_referencia,
           ace.data_execucao AS data_fim,
           ace.custo_producao AS qtd_refile
      FROM erp.fact_accessory_history ace
     INNER JOIN cte_acessorio_refile cte
        ON cte.empresa_id = ace.empresa_id
       AND cte.acessorio_matriz = ace.codigo_item 
),
saldo_op_aberta AS (
    SELECT s.empresa_id,
           m.acessorio_matriz,
           s.componente_id item,
           s.versao_id versao,
           sysdate as previsao_ent,
           round(SUM(erp.fn_convert_uom(s.empresa_id, s.componente_id, s.versao_id, 'KG', s.total_aplicado, 'I')),0) AS op_Aberta
      FROM erp.fact_production_components s
     INNER join erp.fact_production_orders op
        on op.empresa_id = s.empresa_id
       and op.ordem_producao = s.ordem_producao
       and op.status in ('A','P')
       and op.produto_id not in ('116490') 
     INNER JOIN cte_agrupa_insumos m
        ON s.empresa_id = m.empresa_id
       AND (s.componente_id || '/' || s.versao_id = m.mp or
            s.componente_id||'i' || '/' || s.versao_id = m.mp)
     WHERE not exists (select 1
                         from erp.fact_production_routing rec
                        where rec.empresa_id = s.empresa_id
                          and rec.ordem_producao = s.ordem_producao
                          and rec.etapa_id = 20
                          and rec.status != 'F'
                          )
     GROUP BY s.empresa_id, m.acessorio_matriz, s.componente_id, s.versao_id, op.data_entrega
),
saldo_op_prog AS (
    SELECT s.empresa_id,
           m.acessorio_matriz,
           s.componente_id item,
           s.versao_id versao,
           rec.data_programacao_ini as previsao_ent,
           round(SUM(erp.fn_convert_uom(s.empresa_id, s.componente_id, s.versao_id, 'KG', s.total_aplicado, 'I')),0) AS op_prog
      FROM erp.fact_production_components s
     INNER join erp.fact_production_orders op
        on op.empresa_id = s.empresa_id
       and op.ordem_producao = s.ordem_producao
       and op.status in ('A','P') 
     INNER JOIN erp.fact_production_routing rec
        on rec.empresa_id = s.empresa_id
       and rec.ordem_producao = s.ordem_producao
       and rec.etapa_id = 20
       and rec.status in ('F')
     INNER JOIN cte_agrupa_insumos m
        ON s.empresa_id = m.empresa_id
       AND (s.componente_id || '/' || s.versao_id = m.mp or
            s.componente_id||'i' || '/' || s.versao_id = m.mp)
     GROUP BY s.empresa_id, m.acessorio_matriz, s.componente_id, s.versao_id, rec.data_programacao_ini
),

-- ===================================================================================
-- 4. UNIFICAÇÃO TEMPORAL: Combina todos os vetores através de LATERAL JOIN para expansão de meses
-- ===================================================================================
dados_unificados AS (
    SELECT s.empresa_id, s.acessorio_matriz, CAST(NULL AS VARCHAR2(100)) AS acessorio,
           TRUNC(SYSDATE, 'MM') AS mes_referencia, 0 AS mil_mes, 0 AS kg_mes, 
           0 AS compra_mes, CAST(NULL AS DATE) AS data_fim, s.qtd_saldo_kg, 0 AS qtd_refile, 0 as op_Aberta, 0 as op_prog
      FROM saldo_estoque_forecast s
    UNION ALL
    SELECT t.empresa_id, t.acessorio_matriz, t.codigo_item, m.mes_referencia,
           t.mil_mes, t.kg_mes, 0 AS compra_mes, t.data_fim, 0 AS qtd_saldo_kg, 0 AS qtd_refile, 0 as op_Aberta, 0 as op_prog
      FROM saldo_mes_forecast t,
           LATERAL (
               SELECT ADD_MONTHS(TRUNC(SYSDATE, 'MM'), LEVEL - 1) AS mes_referencia
                 FROM dual
               CONNECT BY LEVEL <= MONTHS_BETWEEN(TRUNC(t.data_fim, 'MM'), TRUNC(SYSDATE, 'MM')) + 1
           ) m
     WHERE t.data_fim >= TRUNC(SYSDATE, 'MM')
    UNION ALL
    SELECT s.empresa_id, s.acessorio_matriz, CAST(NULL AS VARCHAR2(100)) AS acessorio,
           TRUNC(s.data_previsao_entrega, 'MM') AS mes_referencia, 0 AS mil_mes, 0 AS kg_mes,
           s.qtd_compra AS compra_mes, CAST(NULL AS DATE) AS data_fim, 0 AS qtd_saldo_kg, 0 AS qtd_refile, 0 as op_Aberta, 0 as op_prog
      FROM saldo_oc_forecast s   
    UNION ALL
    SELECT s.empresa_id, s.acessorio_matriz, CAST(NULL AS VARCHAR2(100)) AS acessorio,
           TRUNC(s.previsao_ent, 'MM') AS mes_referencia, 0 AS mil_mes, 0 AS kg_mes,
           0 AS compra_mes, CAST(NULL AS DATE) AS data_fim, 0 AS qtd_saldo_kg, 0 AS qtd_refile, s.op_Aberta, 0 as op_prog
      FROM saldo_op_aberta s   
    UNION ALL
    SELECT s.empresa_id, s.acessorio_matriz, CAST(NULL AS VARCHAR2(100)) AS acessorio,
           TRUNC(s.previsao_ent, 'MM') AS mes_referencia, 0 AS mil_mes, 0 AS kg_mes,
           0 AS compra_mes, CAST(NULL AS DATE) AS data_fim, 0 AS qtd_saldo_kg, 0 AS qtd_refile, 0 as op_Aberta, s.op_prog
      FROM saldo_op_prog s 
    UNION ALL    
    SELECT r.empresa_id, r.acessorio_matriz, r.codigo_item AS acessorio,
           m.mes_referencia, 0 AS mil_mes, 0 AS kg_mes, 0 AS compra_mes,
           CAST(NULL AS DATE) AS data_fim, 0 AS qtd_saldo_kg, r.qtd_refile, 0 as op_Aberta, 0 as op_prog
      FROM saldo_refile_forecast r,
           LATERAL (
               SELECT ADD_MONTHS(TRUNC(SYSDATE, 'MM'), LEVEL - 1) AS mes_referencia
                 FROM dual
               CONNECT BY LEVEL <= MONTHS_BETWEEN(TRUNC(r.data_fim, 'MM'), TRUNC(SYSDATE, 'MM')) + 1
           ) m        
),
agrupado_por_mes AS (
    SELECT empresa_id,
           acessorio_matriz,
           mes_referencia,
           SUM(mil_mes) AS mil_mes,
           SUM(op_Aberta) as op_Aberta,
           sum(op_prog) as op_prog,
           SUM(kg_mes) AS kg_mes,
           MAX(data_fim) AS data_fim,
           SUM(compra_mes) AS compra_mes,
           SUM(qtd_refile) AS qtd_refile,
           SUM(qtd_saldo_kg) AS estoque_atual
      FROM dados_unificados
     GROUP BY empresa_id, acessorio_matriz, mes_referencia
),

-- ===================================================================================
-- 5. CÁLCULO DE SALDO ACUMULADO (RUNNING TOTAL): Saldo = Estoque + Entradas - Consumo
-- ===================================================================================
calculo_acumulado AS (
    SELECT empresa_id,
           acessorio_matriz,
           mes_referencia,
           mil_mes,
           op_Aberta,
           op_prog,
           kg_mes,
           data_fim,
           estoque_atual,
           compra_mes,
           qtd_refile,
           SUM(estoque_atual - kg_mes + compra_mes + qtd_refile) OVER (
               PARTITION BY empresa_id, acessorio_matriz 
               ORDER BY mes_referencia
               ROWS UNBOUNDED PRECEDING
           ) AS saldo_final_calculado
      FROM agrupado_por_mes
)

-- ===================================================================================
-- 6. QUERY FINAL: Projeção Analítica Pronta para BI
-- ===================================================================================
SELECT empresa_id,
       acessorio_matriz,
       mes_referencia,
       op_Aberta,
       op_prog,
       mil_mes,
       LAG(saldo_final_calculado, 1, estoque_atual) OVER (
           PARTITION BY empresa_id, acessorio_matriz 
           ORDER BY mes_referencia
       ) AS saldo_inicial,
       kg_mes AS forecast_mes,
       compra_mes,
       qtd_refile AS refile,
       saldo_final_calculado AS saldo_final
  FROM calculo_acumulado
 ORDER BY empresa_id, 
          acessorio_matriz, 
          mes_referencia;
