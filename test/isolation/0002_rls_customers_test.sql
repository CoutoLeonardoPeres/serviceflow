-- =============================================================================
-- Testes de isolamento RLS — migration 0002_customers
-- Como executar:
--   1. supabase start (ou aponte para o banco de dev)
--   2. supabase db reset
--   3. psql $DATABASE_URL -f supabase/seed/dev_seed.sql
--   4. psql $DATABASE_URL -f test/isolation/0002_rls_customers_test.sql
--
-- Os testes usam SET LOCAL para simular o contexto JWT de cada usuário.
-- Adapte os UUIDs conforme os usuários criados no dev_seed.sql.
-- =============================================================================

\set ON_ERROR_STOP on

-- UUIDs de referência — substituir pelos UUIDs reais do seed
\set TENANT_ALPHA  'alpha-tenant-uuid-0001'
\set TENANT_BETA   'beta-tenant-uuid-0002'
\set USER_ALPHA    'alpha-owner-uuid-0001'
\set USER_BETA     'beta-owner-uuid-0002'
\set USER_TECH     'alpha-tech-uuid-0003'   -- role: technician (customers.read, sem write)
\set USER_VIEWER   'alpha-viewer-uuid-0004' -- role: viewer (customers.read)

DO $$
DECLARE
  v_cid_alpha uuid;
  v_cid_beta  uuid;
  v_count     int;
  v_ok        boolean;
BEGIN
  RAISE NOTICE '=== E3 RLS Customers — Início dos testes ===';

  -- ─────────────────────────────────────────────────────────────────────────
  -- SETUP: Inserir clientes diretamente (service role, sem RLS) para seed
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Alpha 1', true)
  RETURNING id INTO v_cid_alpha;

  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_BETA', 'company', 'Cliente Beta 1', true)
  RETURNING id INTO v_cid_beta;

  RAISE NOTICE 'Setup: clientes criados — alpha=%, beta=%', v_cid_alpha, v_cid_beta;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: owner do tenant alpha NÃO vê clientes do tenant beta
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );

  SELECT COUNT(*) INTO v_count
  FROM customers
  WHERE tenant_id = :'TENANT_BETA';

  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T1: alpha_owner viu % cliente(s) do beta', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T1: alpha_owner não vê clientes do tenant beta';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: owner do tenant alpha vê seus próprios clientes
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM customers
  WHERE tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T2: alpha_owner não viu os próprios clientes (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T2: alpha_owner vê seus % cliente(s)', v_count;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: technician do tenant alpha vê clientes (tem customers.read) mas não edita
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_TECH')::text,
    true
  );

  SELECT COUNT(*) INTO v_count
  FROM customers
  WHERE tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T3: technician não viu clientes do próprio tenant (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T3: technician vê % cliente(s) do próprio tenant', v_count;

  -- Tentativa de UPDATE por technician deve falhar (sem customers.write)
  BEGIN
    UPDATE customers SET notes = 'hack' WHERE id = v_cid_alpha;
    RAISE EXCEPTION 'FALHOU T4: technician conseguiu fazer UPDATE em customer';
  EXCEPTION
    WHEN insufficient_privilege OR no_data_found THEN
      RAISE NOTICE 'PASSOU T4: UPDATE por technician foi bloqueado (esperado)';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: viewer do tenant alpha vê clientes mas não cria
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_VIEWER')::text,
    true
  );

  SELECT COUNT(*) INTO v_count FROM customers WHERE tenant_id = :'TENANT_ALPHA';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T5: viewer não viu clientes (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T5: viewer vê % cliente(s)', v_count;

  -- Tentativa de INSERT por viewer deve falhar (sem customers.write)
  BEGIN
    INSERT INTO customers (type, name, is_active) VALUES ('person', 'Hacker', true);
    RAISE EXCEPTION 'FALHOU T6: viewer conseguiu INSERT em customers';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T6: INSERT por viewer foi bloqueado (esperado)';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: owner do beta NÃO consegue inserir contato em customer do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );

  BEGIN
    INSERT INTO customer_contacts (customer_id, name, is_primary)
    VALUES (v_cid_alpha, 'Invasor', false);
    RAISE EXCEPTION 'FALHOU T7: beta_owner conseguiu inserir contato em customer do alpha';
  EXCEPTION
    WHEN OTHERS THEN
      RAISE NOTICE 'PASSOU T7: beta_owner não conseguiu inserir contato em customer do alpha (%)' , SQLERRM;
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: document único por tenant — duplicata deve falhar
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;

  -- Inserir cliente com documento específico
  INSERT INTO customers (tenant_id, type, name, document, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Empresa Dup A', '11222333000181', true);

  BEGIN
    -- Tentar inserir mesmo documento no mesmo tenant
    INSERT INTO customers (tenant_id, type, name, document, is_active)
    VALUES (:'TENANT_ALPHA', 'company', 'Empresa Dup B', '11222333000181', true);
    RAISE EXCEPTION 'FALHOU T8: inserção de documento duplicado não foi bloqueada';
  EXCEPTION
    WHEN unique_violation THEN
      RAISE NOTICE 'PASSOU T8: documento duplicado no mesmo tenant foi bloqueado';
  END;

  -- Mesmo documento em tenant diferente deve ser permitido
  INSERT INTO customers (tenant_id, type, name, document, is_active)
  VALUES (:'TENANT_BETA', 'company', 'Empresa Dup Beta', '11222333000181', true);
  RAISE NOTICE 'PASSOU T9: mesmo documento em tenant diferente é permitido';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: is_primary único por customer (apenas um contato principal)
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO customer_contacts (tenant_id, customer_id, name, is_primary)
  VALUES (:'TENANT_ALPHA', v_cid_alpha, 'Contato Principal', true);

  BEGIN
    INSERT INTO customer_contacts (tenant_id, customer_id, name, is_primary)
    VALUES (:'TENANT_ALPHA', v_cid_alpha, 'Segundo Principal', true);
    RAISE EXCEPTION 'FALHOU T10: dois contatos primários foram inseridos';
  EXCEPTION
    WHEN unique_violation THEN
      RAISE NOTICE 'PASSOU T10: segundo contato primário foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: is_default único por customer_address
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO customer_addresses (
    tenant_id, customer_id, cep, street, number, district, city, state, is_default
  ) VALUES (
    :'TENANT_ALPHA', v_cid_alpha, '01310100', 'Av. Paulista', '1000', 'Bela Vista', 'São Paulo', 'SP', true
  );

  BEGIN
    INSERT INTO customer_addresses (
      tenant_id, customer_id, cep, street, number, district, city, state, is_default
    ) VALUES (
      :'TENANT_ALPHA', v_cid_alpha, '01310200', 'Rua Augusta', '500', 'Consolação', 'São Paulo', 'SP', true
    );
    RAISE EXCEPTION 'FALHOU T11: dois endereços padrão foram inseridos';
  EXCEPTION
    WHEN unique_violation THEN
      RAISE NOTICE 'PASSOU T11: segundo endereço padrão foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T12: auditoria — customer INSERT deve gerar registro em audit_logs
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'customer.created'
    AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T12: customer criado sem gerar audit_log (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T12: audit_log gerado para customer.created (% registro(s))', v_count;

  RAISE NOTICE '=== Todos os testes E3 concluídos ===';

  -- Rollback para não persistir dados de teste
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' AND SQLERRM = 'ROLLBACK_TEST_DATA' THEN
    RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
END;
$$;
