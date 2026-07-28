-- =============================================================================
-- Migration: 0062_barcode_digits_only
-- Descricao: codigo de barras so aceita digitos, no banco e na importacao
-- Depende de: 0059_material_catalog_suppliers, 0060_supplier_price_import
-- Rollback: supabase/rollbacks/0062_barcode_digits_only_rollback.sql
--
-- ORIGEM: o Excel trata 13 digitos como numero e mostra `7,89123E+12`. Quando
-- o fornecedor salva e devolve o arquivo, o codigo de barras volta assim — e
-- "7,89123E+12" tem 11 caracteres, entao passava no CHECK de tamanho da 0059
-- e era gravado como se fosse codigo. O produto ficava cadastrado com um
-- codigo que nao existe, e ninguem perceberia ate tentar bipar.
--
-- O app ja recusa a linha na leitura da planilha (price_sheet.dart). Esta
-- migration fecha a mesma porta no banco: o app e conveniencia, a fronteira
-- de confianca e aqui. Vale tambem para digitacao manual e para qualquer
-- integracao futura.
-- =============================================================================

-- Limpa o que ja entrou errado antes de apertar a regra: com dado invalido
-- na tabela, o ALTER falharia e a migration inteira nao aplicaria.
UPDATE products
SET barcode = NULL
WHERE barcode IS NOT NULL
  AND barcode !~ '^[0-9]+$';

ALTER TABLE products DROP CONSTRAINT IF EXISTS products_barcode_check;
ALTER TABLE products
  ADD CONSTRAINT products_barcode_check
  CHECK (barcode IS NULL OR barcode ~ '^[0-9]{6,20}$');

-- ── A importacao passa a reportar a linha em vez de gravar lixo ─────────────
CREATE OR REPLACE FUNCTION _sf_clean_barcode(p_raw text)
RETURNS text LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text;
BEGIN
  IF p_raw IS NULL THEN RETURN NULL; END IF;

  -- `="789..."` e a formula que o proprio modelo usa para forcar texto no
  -- Excel; chega de volta assim e precisa ser desembrulhada.
  v := btrim(p_raw);
  v := regexp_replace(v, '^="?', '');
  v := regexp_replace(v, '"?$', '');
  v := btrim(replace(v, '"', ''));

  IF v = '' THEN RETURN NULL; END IF;

  -- Notacao cientifica e perda de informacao: o numero original nao esta mais
  -- ali. Devolve o marcador para a chamadora recusar a linha.
  IF v ~* '^[0-9]+([.,][0-9]+)?e[+-]?[0-9]+$' THEN
    RETURN '__SCIENTIFIC__';
  END IF;

  RETURN v;
END;
$$;

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

  PERFORM set_config('serviceflow.price_source', 'spreadsheet', true);

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    v_line := v_line + 1;

    v_code    := NULLIF(btrim(COALESCE(v_row->>'supplier_code', '')), '');
    v_name    := NULLIF(btrim(COALESCE(v_row->>'name', '')), '');
    v_barcode := _sf_clean_barcode(v_row->>'barcode');
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

    IF v_barcode = '__SCIENTIFIC__' THEN
      v_errors := v_errors || jsonb_build_object(
        'line', v_line, 'code', v_code,
        'reason', 'Código de barras em notação científica. Formate a coluna como Texto e reenvie.');
      CONTINUE;
    END IF;

    IF v_barcode IS NOT NULL AND v_barcode !~ '^[0-9]{6,20}$' THEN
      v_errors := v_errors || jsonb_build_object(
        'line', v_line, 'code', v_code,
        'reason', 'Código de barras deve ter de 6 a 20 dígitos, sem letras nem pontuação.');
      CONTINUE;
    END IF;

    IF v_unit IS NOT NULL AND v_unit NOT IN
       ('un','m','m2','m3','kg','g','l','ml','cx','pc','h') THEN
      v_errors := v_errors || jsonb_build_object(
        'line', v_line, 'code', v_code,
        'reason', 'Unidade "' || v_unit || '" não reconhecida');
      CONTINUE;
    END IF;

    SELECT * INTO v_existing
    FROM supplier_products
    WHERE tenant_id = v_tenant_id
      AND supplier_id = p_supplier_id
      AND supplier_code = v_code;

    v_product_id := v_existing.product_id;

    IF v_product_id IS NULL AND v_barcode IS NOT NULL THEN
      SELECT id INTO v_product_id
      FROM products
      WHERE tenant_id = v_tenant_id AND barcode = v_barcode
      LIMIT 1;
    END IF;

    IF v_product_id IS NULL AND v_name IS NOT NULL THEN
      SELECT id INTO v_product_id
      FROM products
      WHERE tenant_id = v_tenant_id
        AND lower(btrim(name)) = lower(v_name)
      LIMIT 1;
    END IF;

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
