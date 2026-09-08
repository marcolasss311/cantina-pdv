# 🍔 Cantina PDV - Sistema de Vendas, Estoque e Gestão

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/Plataforma-Android%20%7C%20iOS%20%7C%20Web-blue?style=for-the-badge" alt="Plataforma" />
</p>

O **Cantina PDV** é um sistema completo e moderno de Ponto de Venda (PDV), controle de estoque e relatórios financeiros, desenvolvido em **Flutter** com backend em tempo real no **Supabase (PostgreSQL)**.

Projetado especialmente para cantinas, lanchonetes, pequenos comércios e estabelecimentos de alimentação que necessitam de rapidez no atendimento, controle rigoroso de estoque e clareza nos lucros.

---

## 🌟 Funcionalidades Principais

### 🛒 1. Frente de Caixa Ágil (Vendas)
* **Destaque para Pastas e Categorias:** Interface limpa organizada em cards com ícones e contadores de produtos (ex: *Hambúrgueres*, *Salgados*, *Bebidas*, *Doces*).
* **Produtos com e sem Código de Barras:** Suporte tanto para produtos industrializados (bipados com a câmera) quanto alimentos preparados/artesanais (sem código).
* **Carrinho de Compras Interativo:** Controle de limites por estoque disponível, resumo dinâmico e visualização rápida dos itens.
* **Finalização de Vendas:**
  * Modal com 4 métodos de pagamento: **Dinheiro**, **PIX**, **Débito/Crédito** e **Outros**.
  * Cálculo automático de troco para pagamentos em dinheiro.

### 📦 2. Entrada e Reposição de Estoque
* **Leitura com Câmera:** Scanner integrado via câmera do dispositivo para leitura rápida de códigos de barras (EAN-13, QR Code, etc.).
* **Reposição Manual e Produtos sem Código:** Botão para selecionar produtos diretamente de uma lista pesquisável com filtro rápido para itens sem código.
* **Cálculo de Custos:** Entrada de quantidade, custo unitário e custo total da compra com recálculo automático.

### 📊 3. Histórico de Vendas & Dashboard Financeiro
* **Remoção Parcial e Cancelamento:** Permite remover unidades específicas de um produto vendido ou cancelar a venda inteira, devolvendo o estoque ao sistema em tempo real.
* **Carregamento Otimizado:** Histórico paginado para máxima performance e economia de dados.
* **Dashboard de Lucros:** Acompanhamento de faturamento bruto, custos e lucro líquido.
* **Filtros Temporais:** Métricas consolidadas por **Dia**, **Semana** e **Mês**.
* **Detalhamento por Pagamento:** Faturamento segmentado por cada método de pagamento (Dinheiro, PIX, Cartão, Outros).

### 🏷️ 4. Gestão e Cadastro de Produtos
* **Cadastro Rápido:** Formulário com validação de nome, categoria/pasta, preço de custo e preço de venda.
* **Identificador Automático:** Criação automática de códigos internos (`SB-...`) para produtos sem código de barras físico.
* **Edição Completa:** Ajuste rápido de nomes, custos e preços diretamente na lista inicial.
* **Exclusão Segura em Cascata:** Limpeza inteligente de integridade referencial no banco de dados para evitar conflitos de chaves estrangeiras.

---

## 🛠️ Tecnologias Utilizadas

* **Framework:** [Flutter](https://flutter.dev/) (Dart 3.x)
* **Backend & Banco de Dados:** [Supabase](https://supabase.com/) (PostgreSQL)
* **Leitor de Código de Barras:** `mobile_scanner`
* **Armazenamento Local:** `shared_preferences`
* **Design & UI:** Material Design 3 com layout responsivo e suporte seguro a telas com entalhe (`SafeArea`)

---

## 📁 Estrutura do Projeto

```text
lib/
├── main.dart                      # Ponto de entrada e inicialização do Supabase
├── home_screen.dart               # Tela inicial com catálogo, busca, edição e menu
├── vendas_screen.dart             # Frente de caixa com categorias, scanner e carrinho
├── entrada_estoque_screen.dart    # Reposição de estoque (câmera e manual)
├── historico_vendas_screen.dart   # Histórico, dashboard de lucros e relatórios
├── cadastro_produto_screen.dart   # Cadastro e edição de produtos
├── models/                        # Modelos de dados
│   ├── produto.dart
│   ├── venda.dart
│   ├── item_venda.dart
│   └── entrada_estoque.dart
└── services/
    └── pastas_service.dart        # Gerenciamento local das categorias e pastas
```

---

## 🗄️ Esquema do Banco de Dados (Supabase)

O sistema utiliza as seguintes tabelas no PostgreSQL:

```sql
-- 1. Tabela de Produtos
CREATE TABLE produtos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nome TEXT NOT NULL,
  preco_custo NUMERIC(10, 2) DEFAULT 0.0,
  preco_venda NUMERIC(10, 2) NOT NULL,
  quantidade_estoque INT DEFAULT 0,
  codigo_barras TEXT
);

-- 2. Tabela de Vendas
CREATE TABLE vendas (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  data_venda TIMESTAMPTZ DEFAULT now(),
  valor_total NUMERIC(10, 2) NOT NULL,
  metodo_pagamento TEXT DEFAULT 'OUTROS'
);

-- 3. Itens das Vendas
CREATE TABLE itens_venda (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  venda_id UUID REFERENCES vendas(id) ON DELETE CASCADE,
  produto_id UUID REFERENCES produtos(id) ON DELETE CASCADE,
  quantidade_vendida INT NOT NULL,
  preco_unitario NUMERIC(10, 2) NOT NULL,
  subtotal NUMERIC(10, 2) NOT NULL
);

-- 4. Histórico de Entradas de Estoque
CREATE TABLE entrada_estoque (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  produto_id UUID REFERENCES produtos(id) ON DELETE CASCADE,
  quantidade_comprada INT NOT NULL,
  custo_total_compra NUMERIC(10, 2) NOT NULL,
  data_entrada TIMESTAMPTZ DEFAULT now()
);
```

---

## 🚀 Como Executar o Projeto

### Pré-requisitos
* [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado (versão 3.13 ou superior)
* [Git](https://git-scm.com/)
* Dispositivo físico Android/iOS conectado ou emulador configurado

### Passo a Passo

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/marcolasss311/cantina-pdv.git
   cd cantina-pdv
   ```

2. **Instale as dependências:**
   ```bash
   flutter pub get
   ```

3. **Configuração do Supabase:**
   Crie um projeto no [Supabase](https://supabase.com), crie as tabelas com o script SQL acima e configure a URL e a Anon Key no arquivo `lib/main.dart`:
   ```dart
   await Supabase.initialize(
     url: 'SUA_URL_DO_SUPABASE',
     anonKey: 'SUA_ANON_KEY',
   );
   ```

4. **Execute a aplicação:**
   ```bash
   flutter run
   ```

---

<p align="center">Desenvolvido com ❤️ em Flutter</p>
