CREATE TABLE "usuarios"(
    "id" bigserial NOT NULL,
    "nome" VARCHAR(120) NOT NULL,
    "email" VARCHAR(160) NOT NULL,
    "senha_hash" VARCHAR(255) NOT NULL,
    "perfil" INTEGER NOT NULL DEFAULT 'operador',
    "ativo" BOOLEAN NOT NULL DEFAULT TRUE,
    "ultimo_login" TIMESTAMP(0) WITH
        TIME zone NULL,
        "criado_em" TIMESTAMP(0)
    WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "atualizado_em" TIMESTAMP(0)
    WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE
    "usuarios" ADD PRIMARY KEY("id");
ALTER TABLE
    "usuarios" ADD CONSTRAINT "usuarios_email_unique" UNIQUE("email");
CREATE TABLE "categorias"(
    "id" bigserial NOT NULL,
    "nome" VARCHAR(100) NOT NULL,
    "descricao" TEXT NULL,
    "ativo" BOOLEAN NOT NULL DEFAULT TRUE,
    "criado_em" TIMESTAMP(0) WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "atualizado_em" TIMESTAMP(0)
    WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE
    "categorias" ADD PRIMARY KEY("id");
ALTER TABLE
    "categorias" ADD CONSTRAINT "categorias_nome_unique" UNIQUE("nome");
CREATE TABLE "fornecedores"(
    "id" bigserial NOT NULL,
    "razao_social" VARCHAR(160) NOT NULL,
    "nome_fantasia" VARCHAR(160) NULL,
    "cnpj" CHAR(14) NULL,
    "email" VARCHAR(160) NULL,
    "telefone" VARCHAR(20) NULL,
    "endereco" TEXT NULL,
    "ativo" BOOLEAN NOT NULL DEFAULT TRUE,
    "criado_em" TIMESTAMP(0) WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "atualizado_em" TIMESTAMP(0)
    WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE
    "fornecedores" ADD PRIMARY KEY("id");
ALTER TABLE
    "fornecedores" ADD CONSTRAINT "fornecedores_cnpj_unique" UNIQUE("cnpj");
CREATE TABLE "produtos"(
    "id" bigserial NOT NULL,
    "nome" VARCHAR(160) NOT NULL,
    "descricao" TEXT NULL,
    "codigo_barras" VARCHAR(50) NOT NULL,
    "categoria_id" BIGINT NOT NULL,
    "fornecedor_id" BIGINT NULL,
    "unidade_medida" VARCHAR(10) NOT NULL DEFAULT 'UN',
    "estoque_minimo" INTEGER NOT NULL,
    "controla_validade" BOOLEAN NOT NULL,
    "dias_alerta_vencimento" INTEGER NOT NULL DEFAULT 30,
    "preco_custo" DECIMAL(12, 2) NULL,
    "ativo" BOOLEAN NOT NULL DEFAULT TRUE,
    "criado_em" TIMESTAMP(0) WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "atualizado_em" TIMESTAMP(0)
    WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE
    "produtos" ADD PRIMARY KEY("id");
ALTER TABLE
    "produtos" ADD CONSTRAINT "produtos_codigo_barras_unique" UNIQUE("codigo_barras");
CREATE INDEX "produtos_categoria_id_index" ON
    "produtos"("categoria_id");
CREATE INDEX "produtos_fornecedor_id_index" ON
    "produtos"("fornecedor_id");
CREATE TABLE "lotes_estoque"(
    "id" bigserial NOT NULL,
    "produto_id" BIGINT NOT NULL,
    "codigo_lote" VARCHAR(50) NOT NULL DEFAULT 'SEM-LOTE',
    "data_validade" DATE NULL,
    "quantidade" INTEGER NOT NULL,
    "criado_em" TIMESTAMP(0) WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "atualizado_em" TIMESTAMP(0)
    WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE
    "lotes_estoque" ADD CONSTRAINT "lotes_estoque_produto_id_codigo_lote_unique" UNIQUE("produto_id", "codigo_lote");
ALTER TABLE
    "lotes_estoque" ADD PRIMARY KEY("id");
CREATE TABLE "movimentacoes_estoque"(
    "id" bigserial NOT NULL,
    "produto_id" BIGINT NOT NULL,
    "lote_id" BIGINT NOT NULL,
    "usuario_id" BIGINT NOT NULL,
    "fornecedor_id" BIGINT NULL,
    "tipo" INTEGER NOT NULL,
    "quantidade" INTEGER NOT NULL,
    "motivo" VARCHAR(255) NULL,
    "documento_ref" VARCHAR(60) NULL,
    "criado_em" TIMESTAMP(0) WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "movimentacoes_estoque_produto_id_criado_em_index" ON
    "movimentacoes_estoque"("produto_id", "criado_em");
ALTER TABLE
    "movimentacoes_estoque" ADD PRIMARY KEY("id");
CREATE INDEX "movimentacoes_estoque_usuario_id_index" ON
    "movimentacoes_estoque"("usuario_id");
CREATE INDEX "movimentacoes_estoque_criado_em_index" ON
    "movimentacoes_estoque"("criado_em");
CREATE TABLE "alertas"(
    "id" bigserial NOT NULL,
    "tipo" INTEGER NOT NULL,
    "produto_id" BIGINT NOT NULL,
    "lote_id" BIGINT NULL,
    "mensagem" VARCHAR(255) NOT NULL,
    "status" INTEGER NOT NULL DEFAULT 'aberto',
    "criado_em" TIMESTAMP(0) WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "resolvido_em" TIMESTAMP(0)
    WITH
        TIME zone NULL,
        "resolvido_por" BIGINT NULL
);
ALTER TABLE
    "alertas" ADD CONSTRAINT "alertas_tipo_produto_id_lote_id_status_unique" UNIQUE(
        "tipo",
        "produto_id",
        "lote_id",
        "status"
    );
CREATE INDEX "alertas_status_criado_em_index" ON
    "alertas"("status", "criado_em");
ALTER TABLE
    "alertas" ADD PRIMARY KEY("id");
CREATE TABLE "log_auditoria"(
    "id" bigserial NOT NULL,
    "usuario_id" BIGINT NULL,
    "acao" VARCHAR(40) NOT NULL,
    "entidade" VARCHAR(40) NOT NULL,
    "entidade_id" BIGINT NULL,
    "detalhes" jsonb NULL,
    "criado_em" TIMESTAMP(0) WITH
        TIME zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE
    "log_auditoria" ADD PRIMARY KEY("id");
CREATE INDEX "log_auditoria_criado_em_index" ON
    "log_auditoria"("criado_em");
ALTER TABLE
    "alertas" ADD CONSTRAINT "alertas_resolvido_por_foreign" FOREIGN KEY("resolvido_por") REFERENCES "usuarios"("id");
ALTER TABLE
    "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_produto_id_foreign" FOREIGN KEY("produto_id") REFERENCES "produtos"("id");
ALTER TABLE
    "log_auditoria" ADD CONSTRAINT "log_auditoria_usuario_id_foreign" FOREIGN KEY("usuario_id") REFERENCES "usuarios"("id");
ALTER TABLE
    "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_lote_id_foreign" FOREIGN KEY("lote_id") REFERENCES "lotes_estoque"("id");
ALTER TABLE
    "lotes_estoque" ADD CONSTRAINT "lotes_estoque_produto_id_foreign" FOREIGN KEY("produto_id") REFERENCES "produtos"("id");
ALTER TABLE
    "alertas" ADD CONSTRAINT "alertas_lote_id_foreign" FOREIGN KEY("lote_id") REFERENCES "lotes_estoque"("id");
ALTER TABLE
    "produtos" ADD CONSTRAINT "produtos_fornecedor_id_foreign" FOREIGN KEY("fornecedor_id") REFERENCES "fornecedores"("id");
ALTER TABLE
    "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_fornecedor_id_foreign" FOREIGN KEY("fornecedor_id") REFERENCES "fornecedores"("id");
ALTER TABLE
    "produtos" ADD CONSTRAINT "produtos_categoria_id_foreign" FOREIGN KEY("categoria_id") REFERENCES "categorias"("id");
ALTER TABLE
    "movimentacoes_estoque" ADD CONSTRAINT "movimentacoes_estoque_usuario_id_foreign" FOREIGN KEY("usuario_id") REFERENCES "usuarios"("id");
ALTER TABLE
    "alertas" ADD CONSTRAINT "alertas_produto_id_foreign" FOREIGN KEY("produto_id") REFERENCES "produtos"("id");