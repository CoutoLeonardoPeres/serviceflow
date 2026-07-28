-- Rollback: 0061_purchases_tenant_stamp_and_owner_guard
--
-- Sem perda de dados. Mas reverter **reintroduz dois defeitos**:
--
--   1. Criar fornecedor, categoria de material ou preço volta a falhar com
--      "Você não tem permissão para esta operação de compras", porque o
--      `tenant_id` deixa de ser carimbado e a policy recusa a linha.
--   2. A empresa volta a poder ficar sem proprietário ativo — nada impede
--      remover ou rebaixar o último `tenant_owner`.
--
-- Só reverta se for reaplicar algo equivalente em seguida.

DROP TRIGGER IF EXISTS trg_suppliers_tenant ON suppliers;
DROP TRIGGER IF EXISTS trg_material_categories_tenant ON material_categories;
DROP TRIGGER IF EXISTS trg_supplier_categories_tenant ON supplier_categories;
DROP TRIGGER IF EXISTS trg_supplier_products_tenant ON supplier_products;
DROP FUNCTION IF EXISTS _sf_stamp_tenant();

DROP TRIGGER IF EXISTS trg_protect_last_owner ON tenant_memberships;
DROP FUNCTION IF EXISTS _sf_protect_last_owner();

DROP FUNCTION IF EXISTS is_tenant_owner(uuid);
