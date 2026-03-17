-- ============================================
-- CRM HUB — Supabase Database Schema
-- Plotting Engage
-- ============================================

-- Extensão UUID (já ativa no Supabase por padrão)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABELA: empresas
-- ============================================
CREATE TABLE empresas (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  nome        TEXT NOT NULL,
  nif         TEXT UNIQUE NOT NULL,
  pais        TEXT DEFAULT 'Angola',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  master_id   UUID  -- referência ao utilizador master (preenchida após criar utilizador)
);

-- ============================================
-- TABELA: utilizadores
-- ============================================
CREATE TABLE utilizadores (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  email       TEXT UNIQUE NOT NULL,
  nome        TEXT NOT NULL,
  role        TEXT NOT NULL CHECK (role IN ('master', 'administrador', 'colaborador')),
  ativo       BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Agora podemos adicionar a FK de empresas.master_id
ALTER TABLE empresas
  ADD CONSTRAINT fk_master FOREIGN KEY (master_id) REFERENCES utilizadores(id);

-- ============================================
-- TABELA: projectos
-- ============================================
CREATE TABLE projectos (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id  UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  nome        TEXT NOT NULL,
  data        DATE,
  logo_url    TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABELA: plantas
-- ============================================
CREATE TABLE plantas (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  projecto_id   UUID NOT NULL REFERENCES projectos(id) ON DELETE CASCADE,
  nome          TEXT NOT NULL,
  largura       INTEGER NOT NULL DEFAULT 20,
  comprimento   INTEGER NOT NULL DEFAULT 10,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABELA: clientes (compradores de stands)
-- ============================================
CREATE TABLE clientes (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_nome  TEXT NOT NULL,
  nif           TEXT,
  email         TEXT,
  telefone      TEXT,
  pais          TEXT DEFAULT 'Angola',
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABELA: stands
-- ============================================
CREATE TABLE stands (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  planta_id   UUID NOT NULL REFERENCES plantas(id) ON DELETE CASCADE,
  numero      TEXT NOT NULL,
  tipo        TEXT NOT NULL CHECK (tipo IN ('stand', 'corredor')) DEFAULT 'stand',
  vendido     BOOLEAN DEFAULT FALSE,
  celulas     JSONB,          -- ex: [[0,0],[0,1],[1,0]] — células da grelha
  cliente_id  UUID REFERENCES clientes(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(planta_id, numero)
);

-- ============================================
-- TABELA: documentos (anexos dos stands)
-- ============================================
CREATE TABLE documentos (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  stand_id    UUID NOT NULL REFERENCES stands(id) ON DELETE CASCADE,
  url         TEXT NOT NULL,
  nome        TEXT,
  tipo        TEXT,           -- 'image/jpeg', 'application/pdf', etc.
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TABELA: actividade (log de mensagens)
-- ============================================
CREATE TABLE actividade (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  empresa_id      UUID NOT NULL REFERENCES empresas(id) ON DELETE CASCADE,
  utilizador_id   UUID REFERENCES utilizadores(id) ON DELETE SET NULL,
  utilizador_nome TEXT,
  accao           TEXT NOT NULL,
  entidade        TEXT,        -- 'stand', 'planta', 'projecto', etc.
  entidade_id     UUID,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- Cada empresa só vê os seus próprios dados
-- ============================================

ALTER TABLE empresas     ENABLE ROW LEVEL SECURITY;
ALTER TABLE utilizadores ENABLE ROW LEVEL SECURITY;
ALTER TABLE projectos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE plantas      ENABLE ROW LEVEL SECURITY;
ALTER TABLE stands       ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE documentos   ENABLE ROW LEVEL SECURITY;
ALTER TABLE actividade   ENABLE ROW LEVEL SECURITY;

-- Política: utilizador autenticado só acede à sua empresa
CREATE POLICY "empresa_propria" ON empresas
  FOR ALL USING (id = (
    SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
  ));

CREATE POLICY "utilizadores_empresa" ON utilizadores
  FOR ALL USING (empresa_id = (
    SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
  ));

CREATE POLICY "projectos_empresa" ON projectos
  FOR ALL USING (empresa_id = (
    SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
  ));

CREATE POLICY "plantas_empresa" ON plantas
  FOR ALL USING (projecto_id IN (
    SELECT id FROM projectos WHERE empresa_id = (
      SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
    )
  ));

CREATE POLICY "stands_empresa" ON stands
  FOR ALL USING (planta_id IN (
    SELECT p.id FROM plantas p
    JOIN projectos pr ON pr.id = p.projecto_id
    WHERE pr.empresa_id = (
      SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
    )
  ));

CREATE POLICY "clientes_empresa" ON clientes
  FOR ALL USING (id IN (
    SELECT cliente_id FROM stands s
    JOIN plantas p ON p.id = s.planta_id
    JOIN projectos pr ON pr.id = p.projecto_id
    WHERE pr.empresa_id = (
      SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
    )
  ));

CREATE POLICY "documentos_empresa" ON documentos
  FOR ALL USING (stand_id IN (
    SELECT s.id FROM stands s
    JOIN plantas p ON p.id = s.planta_id
    JOIN projectos pr ON pr.id = p.projecto_id
    WHERE pr.empresa_id = (
      SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
    )
  ));

CREATE POLICY "actividade_empresa" ON actividade
  FOR ALL USING (empresa_id = (
    SELECT empresa_id FROM utilizadores WHERE id = auth.uid()
  ));

-- ============================================
-- STORAGE BUCKET para documentos/logos
-- (executar via Supabase Dashboard > Storage)
-- ============================================
-- Nome do bucket: "crmhub-docs"
-- Tornar público: NÃO (privado, acesso via signed URL)

-- ============================================
-- DADOS DE EXEMPLO (opcional)
-- ============================================
/*
INSERT INTO empresas (nome, nif, pais) VALUES ('Plotting Engage', '5000000001', 'Angola');

INSERT INTO utilizadores (empresa_id, email, nome, role)
VALUES (
  (SELECT id FROM empresas WHERE nif = '5000000001'),
  'master@plottingengage.ao', 'Master Admin', 'master'
);

INSERT INTO projectos (empresa_id, nome, data)
VALUES (
  (SELECT id FROM empresas WHERE nif = '5000000001'),
  'FIB — Feira Internacional de Benguela', '2025-08-01'
);

INSERT INTO plantas (projecto_id, nome, largura, comprimento)
VALUES (
  (SELECT id FROM projectos WHERE nome LIKE 'FIB%'),
  'Pavilhão 1', 20, 10
);
*/
