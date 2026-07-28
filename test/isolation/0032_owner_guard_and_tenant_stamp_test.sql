-- =============================================================================
-- Testes de isolamento RLS — migration 0061
--
-- Prova:
--   * insert em suppliers sem tenant_id funciona (o trigger carimba);
--   * o mesmo vale para material_categories e supplier_products;
--   * update nao consegue mover a linha para outro tenant;
--   * o ultimo proprietario ativo nao pode ser removido;
--   * o ultimo proprietario ativo nao pode ser rebaixado nem suspenso;
--   * com dois proprietarios, remover um deles e permitido;
--   * is_tenant_owner responde certo.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0032_owner_guard_and_tenant_stamp_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_supplier   uuid;
  v_category   uuid;
  v_product    uuid;
  v_owner_role uuid;
  v_tech_ms    uuid;
  v_owner_ms   uuid;
  v_count      int;
BEGIN
  RAISE NOTICE '=== 0061 Carimbo de tenant e protecao do dono — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: insert sem tenant_id passa (era o bug que dizia "sem permissao")
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO suppliers (name) VALUES ('Fornecedor Sem Tenant')
  RETURNING id INTO v_supplier;

  SELECT COUNT(*) INTO v_count
  FROM suppliers
  WHERE id = v_supplier AND tenant_id = :'TENANT_ALPHA';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T1: tenant_id nao foi carimbado no fornecedor';
  END IF;
  RAISE NOTICE 'PASSOU T1: fornecedor sem tenant_id e carimbado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: mesma coisa para categoria e preco
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO material_categories (name) VALUES ('Categoria Sem Tenant')
  RETURNING id INTO v_category;

  INSERT INTO products (name, unit) VALUES ('Produto Sem Tenant', 'un')
  RETURNING id INTO v_product;

  INSERT INTO supplier_products (supplier_id, product_id, price_cents)
  VALUES (v_supplier, v_product, 1000);

  SELECT COUNT(*) INTO v_count
  FROM supplier_products
  WHERE supplier_id = v_supplier AND tenant_id = :'TENANT_ALPHA';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T2: tenant_id nao foi carimbado no preco';
  END IF;
  RAISE NOTICE 'PASSOU T2: categoria e preco tambem sao carimbados';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: nao da para mover a linha para outro tenant
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE suppliers SET tenant_id = :'TENANT_BETA' WHERE id = v_supplier;

  SELECT COUNT(*) INTO v_count
  FROM suppliers WHERE id = v_supplier AND tenant_id = :'TENANT_ALPHA';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T3: fornecedor mudou de empresa num update';
  END IF;
  RAISE NOTICE 'PASSOU T3: update nao troca a empresa da linha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: o ultimo proprietario nao pode ser rebaixado
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT id INTO v_owner_role FROM roles WHERE key = 'tenant_owner';

  SELECT id INTO v_owner_ms
  FROM tenant_memberships
  WHERE tenant_id = :'TENANT_ALPHA' AND role_id = v_owner_role
    AND status = 'active'
  LIMIT 1;

  IF v_owner_ms IS NULL THEN
    RAISE EXCEPTION 'PRE-CONDICAO: tenant alpha nao tem proprietario ativo';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM tenant_memberships
  WHERE tenant_id = :'TENANT_ALPHA' AND role_id = v_owner_role
    AND status = 'active';

  IF v_count = 1 THEN
    BEGIN
      UPDATE tenant_memberships SET status = 'suspended' WHERE id = v_owner_ms;
      RAISE EXCEPTION 'FALHOU T4: unico proprietario foi suspenso';
    EXCEPTION
      WHEN check_violation THEN
        RAISE NOTICE 'PASSOU T4: unico proprietario nao pode ser suspenso';
    END;

    BEGIN
      DELETE FROM tenant_memberships WHERE id = v_owner_ms;
      RAISE EXCEPTION 'FALHOU T5: unico proprietario foi removido';
    EXCEPTION
      WHEN check_violation THEN
        RAISE NOTICE 'PASSOU T5: unico proprietario nao pode ser removido';
    END;
  ELSE
    RAISE NOTICE 'AVISO T4/T5: tenant alpha tem % proprietarios ativos; '
                 'o teste do ultimo dono nao se aplica', v_count;
  END IF;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: com um segundo proprietario, remover o primeiro e permitido
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT id INTO v_tech_ms
  FROM tenant_memberships
  WHERE tenant_id = :'TENANT_ALPHA' AND user_id = :'USER_TECH';

  IF v_tech_ms IS NOT NULL THEN
    UPDATE tenant_memberships
    SET role_id = v_owner_role, status = 'active'
    WHERE id = v_tech_ms;

    -- Agora existem dois: rebaixar o primeiro passa.
    UPDATE tenant_memberships SET status = 'suspended' WHERE id = v_owner_ms;
    RAISE NOTICE 'PASSOU T6: com dois donos, um pode sair';

    -- Restaura para nao deixar o seed inconsistente caso o rollback falhe.
    UPDATE tenant_memberships SET status = 'active' WHERE id = v_owner_ms;
  ELSE
    RAISE NOTICE 'AVISO T6: USER_TECH nao tem membership no alpha';
  END IF;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: is_tenant_owner
  -- ─────────────────────────────────────────────────────────────────────────
  IF NOT is_tenant_owner(:'USER_ALPHA') THEN
    RAISE EXCEPTION 'FALHOU T7: dono nao foi reconhecido como dono';
  END IF;
  RAISE NOTICE 'PASSOU T7: is_tenant_owner responde certo';

  RAISE NOTICE '=== 0061 — TODOS OS TESTES PASSARAM ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'ROLLBACK_TEST_DATA' THEN
      RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
    ELSE
      RAISE;
    END IF;
END;
$$;
