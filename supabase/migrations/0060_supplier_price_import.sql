-- =============================================================================
-- Migration: 0060_supplier_price_import
-- Descricao: Importacao da tabela de precos do fornecedor por planilha — F7-P2
-- Depende de: 0042_stock_ledger, 0044_suppliers_purchase_orders,
--             0059_material_catalog_suppliers
-- Rollback: supabase/rollbacks/0060_supplier_price_import_rollback.sql
--
-- ORIGEM: fornecedor atualiza tabela de preco todo mes. Digitar 300 itens a
-- mao nao acontece — na pratica o preco envelhece no sistema e quem monta o
-- orcamento volta a chutar, que era exatamente o problema que a 0059 resolveu.
--
-- POR QUE NO BANCO E NAO NO APP: a importacao mexe em duas tabelas por linha
-- (`products` e `supplier_products`) e precisa ser tudo ou nada. Feita em
-- laco de HTTP, uma queda no meio deixa metade da tabela nova e metade velha,
-- sem ninguem saber onde parou. Aqui e uma transacao so.
--
-- CASAMENTO (escolha do usuario: modelo do sistema, casando pelo codigo do
-- fornecedor), na ordem:
--   1. vinculo que ja existe em `supplier_products` para aquele codigo;
--   2. codigo de barras, quando a planilha traz;
--   3. nome exato do produto, ignorando caixa e espaco;
--   4. cria o produto, se p_create_missing.
-- Sem isso, reimportar a mesma planilha criaria produto duplicado a cada mes.
-- =============================================================================

CREATE OR REPLACE FUNCTION import_supplier_prices(
  p_supplier_id uuid,
  p_rows jsonb,
  p_create_missing boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_row jsonb;
  v_code text;
  v_name text;
  v_barcode text;
  v_unit text;
  v_brand text;
  v_category text;
  v_category_id uuid;
  v_price integer;
  v_pack numeric;
  v_min numeric;
  v_valid date;
  v_product_id uuid;
  v_existing supplier_products;
  v_line int := 0;
  v_created_products int := 0;
  v_created_prices int := 0;
  v_updated_prices int := 0;
  v_unchanged int := 0;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('purchases.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para importar precos.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM suppliers
    WHERE id = p_supplier_id AND tenant_id = v_tenant_id
  ) THEN
    RAISE EXCEPTION 'Fornecedor nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'Planilha invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- O trigger de historico (0059) le daqui para marcar a origem do preco.
  PERFORM set_config('serviceflow.price_source', 'spreadsheet', true);

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_line := v_line + 1;

    v_code    := NULLIF(btrim(COALESCE(v_row->>'supplier_code', '')), '');
    v_name    := NULLIF(btrim(COALESCE(v_row->>'name', '')), '');
    v_barcode := NULLIF(btrim(COALESCE(v_row->>'barcode', '')), '');
    v_unit    := LOWER(NULLIF(btrim(COALESCE(v_row->>'unit', '')), ''));
    v_brand   := NULLIF(btrim(COALESCE(v_row->>'brand', '')), '');
    v_category := NULLIF(btrim(COALESCE(v_row->>'category', '')), '');

    BEGIN
      v_price := round(COALESCE((v_row->>'price')::numeric, -1) * 100)::integer;
    EXCEPTION WHEN others THEN
      v_price := -1;
    END;

    v_pack := COALESCE(NULLIF(v_row->>'pack_quantity', '')::numeric, 1);
    v_min  := COALESCE(NULLIF(v_row->>'min_quantity', '')::numeric, 0);

    BEGIN
      v_valid := NULLIF(v_row->>'valid_until', '')::date;
    EXCEPTION WHEN others THEN
      v_valid := NULL;
    END;

    -- Validacoes de linha. Uma linha ruim nao derruba o arquivo inteiro: ela
    -- e reportada e o resto entra. Abortar tudo por causa de um preco em
    -- branco faria o operador caçar a linha no Excel sem saber qual e.
    IF v_code IS NULL THEN
      v_errors := v_errors || jsonb_build_object(
        'line', v_line, 'reason', 'Código do fornecedor em branco');
      CONTINUE;
    END IF;

    IF v_price < 0 THEN
      v_errors := v_errors || jsonb_build_object(
        'line', v_line, 'code', v_code, 'reason', 'Preço inválido ou ausente');
      CONTINUE;
    END IF;

    IF v_unit IS NOT NULL AND v_unit NOT IN
       ('un','m','m2','m3','kg','g','l','ml','cx','pc','h') THEN
      v_errors := v_errors || jsonb_build_object(
        'line', v_line, 'code', v_code,
        'reason', 'Unidade "' || v_unit || '" não reconhecida');
      CONTINUE;
    END IF;

    -- 1. Vinculo existente pelo codigo do fornecedor.
    SELECT * INTO v_existing
    FROM supplier_products
    WHERE tenant_id = v_tenant_id
      AND supplier_id = p_supplier_id
      AND supplier_code = v_code;

    v_product_id := v_existing.product_id;

    -- 2. Codigo de barras.
    IF v_product_id IS NULL AND v_barcode IS NOT NULL THEN
      SELECT id INTO v_product_id
      FROM products
      WHERE tenant_id = v_tenant_id AND barcode = v_barcode
      LIMIT 1;
    END IF;

    -- 3. Nome exato, sem diferenciar caixa nem espaco nas pontas.
    IF v_product_id IS NULL AND v_name IS NOT NULL THEN
      SELECT id INTO v_product_id
      FROM products
      WHERE tenant_id = v_tenant_id
        AND lower(btrim(name)) = lower(v_name)
      LIMIT 1;
    END IF;

    -- 4. Cria.
    IF v_product_id IS NULL THEN
      IF NOT p_create_missing THEN
        v_errors := v_errors || jsonb_build_object(
          'line', v_line, 'code', v_code,
          'reason', 'Produto não encontrado no catálogo');
        CONTINUE;
      END IF;
      IF v_name IS NULL THEN
        v_errors := v_errors || jsonb_build_object(
          'line', v_line, 'code', v_code,
          'reason', 'Produto novo precisa de nome');
        CONTINUE;
      END IF;

      IF v_category IS NOT NULL THEN
        SELECT id INTO v_category_id
        FROM material_categories
        WHERE tenant_id = v_tenant_id
          AND lower(btrim(name)) = lower(v_category);

        -- Categoria que veio na planilha e nao existe e criada: recusar
        -- obrigaria a cadastrar a mao antes de cada importacao.
        IF v_category_id IS NULL THEN
          INSERT INTO material_categories (tenant_id, name, created_by)
          VALUES (v_tenant_id, v_category, auth.uid())
          ON CONFLICT (tenant_id, name) DO NOTHING
          RETURNING id INTO v_category_id;

          IF v_category_id IS NULL THEN
            SELECT id INTO v_category_id
            FROM material_categories
            WHERE tenant_id = v_tenant_id
              AND lower(btrim(name)) = lower(v_category);
          END IF;
        END IF;
      ELSE
        v_category_id := NULL;
      END IF;

      INSERT INTO products (
        tenant_id, name, unit, barcode, brand, category_id,
        track_stock, created_by
      ) VALUES (
        v_tenant_id, v_name, COALESCE(v_unit, 'un'), v_barcode, v_brand,
        v_category_id, true, auth.uid()
      )
      RETURNING id INTO v_product_id;

      v_created_products := v_created_products + 1;
    END IF;

    -- Preco.
    IF v_existing.id IS NOT NULL THEN
      IF v_existing.price_cents = v_price
         AND v_existing.pack_quantity = v_pack
         AND v_existing.min_quantity = v_min
         AND v_existing.valid_until IS NOT DISTINCT FROM v_valid THEN
        v_unchanged := v_unchanged + 1;
      ELSE
        UPDATE supplier_products
        SET price_cents = v_price,
            pack_quantity = v_pack,
            min_quantity = v_min,
            valid_until = v_valid,
            is_active = true,
            updated_at = now(),
            updated_by = auth.uid()
        WHERE id = v_existing.id;
        v_updated_prices := v_updated_prices + 1;
      END IF;
    ELSE
      INSERT INTO supplier_products (
        tenant_id, supplier_id, product_id, supplier_code,
        price_cents, pack_quantity, min_quantity, valid_until, updated_by
      ) VALUES (
        v_tenant_id, p_supplier_id, v_product_id, v_code,
        v_price, v_pack, v_min, v_valid, auth.uid()
      )
      -- Mesmo produto ja ligado a este fornecedor por outro codigo: atualiza
      -- em vez de estourar. Acontece quando o fornecedor renomeia o codigo.
      ON CONFLICT (supplier_id, product_id) DO UPDATE
        SET supplier_code = EXCLUDED.supplier_code,
            price_cents = EXCLUDED.price_cents,
            pack_quantity = EXCLUDED.pack_quantity,
            min_quantity = EXCLUDED.min_quantity,
            valid_until = EXCLUDED.valid_until,
            is_active = true,
            updated_at = now(),
            updated_by = auth.uid();
      v_created_prices := v_created_prices + 1;
    END IF;

    v_existing := NULL;
    v_product_id := NULL;
    v_category_id := NULL;
  END LOOP;

  PERFORM log_audit(
    v_tenant_id,
    'supplier.prices.imported',
    'suppliers',
    p_supplier_id::text,
    NULL,
    jsonb_build_object(
      'lines', v_line,
      'created_products', v_created_products,
      'created_prices', v_created_prices,
      'updated_prices', v_updated_prices,
      'unchanged', v_unchanged,
      'errors', jsonb_array_length(v_errors)
    )
  );

  RETURN jsonb_build_object(
    'lines', v_line,
    'created_products', v_created_products,
    'created_prices', v_created_prices,
    'updated_prices', v_updated_prices,
    'unchanged', v_unchanged,
    'errors', v_errors
  );
END;
$$;

GRANT EXECUTE ON FUNCTION import_supplier_prices(uuid, jsonb, boolean)
  TO authenticated;
