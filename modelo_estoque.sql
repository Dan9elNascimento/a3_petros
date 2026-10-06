-- =====================================================================
-- SISTEMA DE ESTOQUE INTELIGENTE - Modelo de dados (PostgreSQL 14+)
-- Referência para os modelos SQLAlchemy / migrations Alembic.
-- =====================================================================

-- ---------- TIPOS ENUM ----------
CREATE TYPE perfil_usuario     AS ENUM ('admin', 'operador');
CREATE TYPE tipo_movimentacao  AS ENUM ('entrada', 'saida', 'ajuste_entrada', 'ajuste_saida');
CREATE TYPE tipo_alerta        AS ENUM ('estoque_baixo', 'vencimento_proximo', 'vencido');
CREATE TYPE status_alerta      AS ENUM ('aberto', 'visto', 'resolvido');

-- ---------- USUÁRIOS ----------
CREATE TABLE usuarios (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome            VARCHAR(120) NOT NULL,
    email           VARCHAR(160) NOT NULL UNIQUE,
    senha_hash      VARCHAR(255) NOT NULL,              -- hash Argon2, nunca a senha
    perfil          perfil_usuario NOT NULL DEFAULT 'operador',
    ativo           BOOLEAN NOT NULL DEFAULT TRUE,
    ultimo_login    TIMESTAMPTZ,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- CATEGORIAS ----------
CREATE TABLE categorias (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome            VARCHAR(100) NOT NULL UNIQUE,
    descricao       TEXT,
    ativo           BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- FORNECEDORES ----------
CREATE TABLE fornecedores (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    razao_social    VARCHAR(160) NOT NULL,
    nome_fantasia   VARCHAR(160),
    cnpj            CHAR(14) UNIQUE,                    -- somente dígitos
    email           VARCHAR(160),
    telefone        VARCHAR(20),
    endereco        TEXT,
    ativo           BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_fornecedor_cnpj CHECK (cnpj IS NULL OR cnpj ~ '^[0-9]{14}$')
);

-- ---------- PRODUTOS ----------
CREATE TABLE produtos (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome                    VARCHAR(160) NOT NULL,
    descricao               TEXT,
    codigo_barras           VARCHAR(50) NOT NULL UNIQUE,
    categoria_id            BIGINT NOT NULL REFERENCES categorias(id) ON DELETE RESTRICT,
    fornecedor_id           BIGINT REFERENCES fornecedores(id) ON DELETE SET NULL,  -- fornecedor principal
    unidade_medida          VARCHAR(10) NOT NULL DEFAULT 'UN',
    estoque_minimo          INTEGER NOT NULL DEFAULT 0,
    controla_validade       BOOLEAN NOT NULL DEFAULT FALSE,
    dias_alerta_vencimento  INTEGER NOT NULL DEFAULT 30,   -- antecedência do alerta
    preco_custo             NUMERIC(12,2),
    ativo                   BOOLEAN NOT NULL DEFAULT TRUE,
    criado_em               TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_produto_estoque_minimo CHECK (estoque_minimo >= 0),
    CONSTRAINT ck_produto_dias_alerta    CHECK (dias_alerta_vencimento >= 0),
    CONSTRAINT ck_produto_preco          CHECK (preco_custo IS NULL OR preco_custo >= 0)
);
CREATE INDEX ix_produtos_categoria  ON produtos (categoria_id);
CREATE INDEX ix_produtos_fornecedor ON produtos (fornecedor_id);
CREATE INDEX ix_produtos_nome       ON produtos (lower(nome));

-- ---------- LOTES (quantidade e validade ficam aqui) ----------
-- Produtos sem controle de validade usam um lote padrão ('SEM-LOTE').
CREATE TABLE lotes_estoque (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    produto_id      BIGINT NOT NULL REFERENCES produtos(id) ON DELETE RESTRICT,
    codigo_lote     VARCHAR(50) NOT NULL DEFAULT 'SEM-LOTE',
    data_validade   DATE,
    quantidade      INTEGER NOT NULL DEFAULT 0,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_lote_produto UNIQUE (produto_id, codigo_lote),
    CONSTRAINT ck_lote_quantidade CHECK (quantidade >= 0)   -- impede estoque negativo
);
CREATE INDEX ix_lotes_validade ON lotes_estoque (data_validade) WHERE quantidade > 0;

-- ---------- MOVIMENTAÇÕES (histórico imutável) ----------
CREATE TABLE movimentacoes_estoque (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    produto_id      BIGINT NOT NULL REFERENCES produtos(id)      ON DELETE RESTRICT,
    lote_id         BIGINT NOT NULL REFERENCES lotes_estoque(id) ON DELETE RESTRICT,
    usuario_id      BIGINT NOT NULL REFERENCES usuarios(id)      ON DELETE RESTRICT,
    fornecedor_id   BIGINT REFERENCES fornecedores(id)           ON DELETE SET NULL, -- só em entradas
    tipo            tipo_movimentacao NOT NULL,
    quantidade      INTEGER NOT NULL,
    motivo          VARCHAR(255),                -- obrigatório em ajustes (regra na API)
    documento_ref   VARCHAR(60),                 -- nº nota fiscal / pedido
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_mov_quantidade CHECK (quantidade > 0)
);
CREATE INDEX ix_mov_produto_data ON movimentacoes_estoque (produto_id, criado_em DESC);
CREATE INDEX ix_mov_usuario      ON movimentacoes_estoque (usuario_id);
CREATE INDEX ix_mov_data         ON movimentacoes_estoque (criado_em DESC);

-- ---------- ALERTAS ----------
CREATE TABLE alertas (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo            tipo_alerta NOT NULL,
    produto_id      BIGINT NOT NULL REFERENCES produtos(id)      ON DELETE CASCADE,
    lote_id         BIGINT REFERENCES lotes_estoque(id)          ON DELETE CASCADE,
    mensagem        VARCHAR(255) NOT NULL,
    status          status_alerta NOT NULL DEFAULT 'aberto',
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolvido_em    TIMESTAMPTZ,
    resolvido_por   BIGINT REFERENCES usuarios(id) ON DELETE SET NULL
);
-- Evita alerta duplicado enquanto o anterior não foi resolvido
CREATE UNIQUE INDEX ux_alertas_ativos
    ON alertas (tipo, produto_id, COALESCE(lote_id, 0))
    WHERE status <> 'resolvido';
CREATE INDEX ix_alertas_status ON alertas (status, criado_em DESC);

-- ---------- AUDITORIA ----------
CREATE TABLE log_auditoria (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id      BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    acao            VARCHAR(40) NOT NULL,        -- LOGIN, CRIAR, EDITAR, DESATIVAR, AJUSTE...
    entidade        VARCHAR(40) NOT NULL,        -- usuarios, produtos, ...
    entidade_id     BIGINT,
    detalhes        JSONB,
    criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_auditoria_data ON log_auditoria (criado_em DESC);

-- =====================================================================
-- VIEWS (alimentam dashboard e relatórios)
-- =====================================================================

-- Saldo total por produto
CREATE VIEW vw_produtos_estoque AS
SELECT p.id AS produto_id,
       p.nome,
       p.codigo_barras,
       p.categoria_id,
       p.estoque_minimo,
       COALESCE(SUM(l.quantidade), 0)::INTEGER AS quantidade_total,
       COALESCE(SUM(l.quantidade), 0) <= p.estoque_minimo AS estoque_baixo
FROM produtos p
LEFT JOIN lotes_estoque l ON l.produto_id = p.id
WHERE p.ativo
GROUP BY p.id;

-- Lotes com validade (a vencer ou vencidos)
CREATE VIEW vw_lotes_validade AS
SELECT l.id AS lote_id,
       p.id AS produto_id,
       p.nome,
       l.codigo_lote,
       l.data_validade,
       l.quantidade,
       (l.data_validade - CURRENT_DATE) AS dias_para_vencer,
       CASE
           WHEN l.data_validade < CURRENT_DATE THEN 'vencido'
           WHEN l.data_validade <= CURRENT_DATE + p.dias_alerta_vencimento THEN 'vencimento_proximo'
           ELSE 'ok'
       END AS situacao
FROM lotes_estoque l
JOIN produtos p ON p.id = l.produto_id
WHERE p.ativo AND l.quantidade > 0 AND l.data_validade IS NOT NULL;

-- Movimentação diária (gráficos do dashboard)
CREATE VIEW vw_movimentacao_diaria AS
SELECT criado_em::DATE AS dia,
       tipo,
       COUNT(*)        AS total_movimentacoes,
       SUM(quantidade) AS total_itens
FROM movimentacoes_estoque
GROUP BY criado_em::DATE, tipo;

-- =====================================================================
-- FUNÇÃO DE ALERTAS (executar por agendador, ex.: a cada hora / diária)
-- =====================================================================
CREATE OR REPLACE FUNCTION gerar_alertas() RETURNS VOID AS $$
BEGIN
    -- 1) Estoque baixo
    INSERT INTO alertas (tipo, produto_id, mensagem)
    SELECT 'estoque_baixo', v.produto_id,
           'Estoque baixo: ' || v.nome || ' (' || v.quantidade_total ||
           ' un., mínimo ' || v.estoque_minimo || ')'
    FROM vw_produtos_estoque v
    WHERE v.estoque_baixo
    ON CONFLICT DO NOTHING;

    -- 2) Vencimento próximo / vencido
    INSERT INTO alertas (tipo, produto_id, lote_id, mensagem)
    SELECT x.tipo, x.produto_id, x.lote_id,
           CASE WHEN x.tipo = 'vencido'
                THEN 'Lote vencido: ' || x.nome || ' (lote ' || x.codigo_lote || ')'
                ELSE 'Vence em ' || x.dias_para_vencer || ' dia(s): ' || x.nome ||
                     ' (lote ' || x.codigo_lote || ')'
           END
    FROM (
        SELECT (CASE WHEN situacao = 'vencido' THEN 'vencido'
                     ELSE 'vencimento_proximo' END)::tipo_alerta AS tipo,
               produto_id, lote_id, nome, codigo_lote, dias_para_vencer
        FROM vw_lotes_validade
        WHERE situacao <> 'ok'
    ) x
    ON CONFLICT DO NOTHING;

    -- 3) Resolve automaticamente alertas de estoque que já normalizaram
    UPDATE alertas a
       SET status = 'resolvido', resolvido_em = now()
      FROM vw_produtos_estoque v
     WHERE a.produto_id = v.produto_id
       AND a.tipo = 'estoque_baixo'
       AND a.status <> 'resolvido'
       AND NOT v.estoque_baixo;

    -- 4) Resolve alertas de lotes zerados
    UPDATE alertas a
       SET status = 'resolvido', resolvido_em = now()
      FROM lotes_estoque l
     WHERE a.lote_id = l.id
       AND a.tipo IN ('vencimento_proximo', 'vencido')
       AND a.status <> 'resolvido'
       AND l.quantidade = 0;
END;
$$ LANGUAGE plpgsql;
