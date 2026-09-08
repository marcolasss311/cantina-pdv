import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cadastro_produto_screen.dart';
import 'entrada_estoque_screen.dart';
import 'vendas_screen.dart';
import 'historico_vendas_screen.dart';
import 'services/pastas_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _produtos = [];
  Map<String, String> _produtoPastaMap = {};
  String _filtroTexto = '';
  bool _isLoading = true;
  bool _temErro = false;

  @override
  void initState() {
    super.initState();
    _carregarProdutos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Carrega os produtos de forma estável via REST (sem piscar erro de WebSocket)
  Future<void> _carregarProdutos() async {
    try {
      final data = await Supabase.instance.client
          .from('produtos')
          .select()
          .order('nome', ascending: true);
      final pastaMap = await PastasService.getProdutoPastaMap();

      if (mounted) {
        setState(() {
          _produtos = List<Map<String, dynamic>>.from(data);
          _produtoPastaMap = pastaMap;
          _isLoading = false;
          _temErro = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Só mostra tela de erro se não houver produtos em cache
          if (_produtos.isEmpty) {
            _temErro = true;
          }
        });

        if (_produtos.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Falha ao atualizar. Verifique sua conexão.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  // Diálogo para editar nome, pasta, preço de custo e preço de venda do produto
  Future<void> _abrirDialogoEditarProduto(Map<String, dynamic> produto) async {
    final id = produto['id'].toString();
    final nomeController = TextEditingController(text: produto['nome'] ?? '');
    final custoController = TextEditingController(text: (produto['preco_custo'] ?? '').toString());
    final vendaController = TextEditingController(text: (produto['preco_venda'] ?? '').toString());
    final formKey = GlobalKey<FormState>();

    final pastas = await PastasService.getPastas();
    String? pastaSelecionada = _produtoPastaMap[id];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Editar Produto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Produto',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.fastfood),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: pastaSelecionada,
                    decoration: const InputDecoration(
                      labelText: 'Pasta / Categoria',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder_open, color: Colors.indigo),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'Nenhuma pasta (Sem categoria)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...pastas.map(
                        (p) => DropdownMenuItem<String>(
                          value: p,
                          child: Text(
                            p,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() => pastaSelecionada = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: custoController,
                    decoration: const InputDecoration(
                      labelText: 'Preço de Custo / Pago (R\$)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.monetization_on_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Informe o custo';
                      if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Valor inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: vendaController,
                    decoration: const InputDecoration(
                      labelText: 'Preço de Venda (R\$)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Informe o preço de venda';
                      if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Valor inválido';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final novoNome = nomeController.text.trim();
                  final novoCusto = double.tryParse(custoController.text.replaceAll(',', '.').trim());
                  final novoVenda = double.parse(vendaController.text.replaceAll(',', '.').trim());

                  Navigator.pop(ctx);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  try {
                    final supabase = Supabase.instance.client;
                    final updates = <String, dynamic>{
                      'nome': novoNome,
                      'preco_venda': novoVenda,
                    };
                    if (novoCusto != null) {
                      updates['preco_custo'] = novoCusto;
                    }

                    await supabase
                        .from('produtos')
                        .update(updates)
                        .eq('id', id);

                    await PastasService.setProdutoPasta(id, pastaSelecionada);

                    _carregarProdutos();

                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('Produto "$novoNome" atualizado com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Erro ao atualizar produto no servidor.'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Salvar Alterações'),
            ),
          ],
        ),
      ),
    );
  }

  // Confirmar exclusão do produto com limpeza de dependências
  Future<void> _confirmarExclusao(String id, String nome) async {
    final supabase = Supabase.instance.client;

    // Verificar se o produto possui histórico de vendas
    int totalVendasVinculadas = 0;
    try {
      final itens = await supabase
          .from('itens_venda')
          .select('produto_id')
          .eq('produto_id', id);
      totalVendasVinculadas = (itens as List).length;
    } catch (_) {}

    if (!mounted) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Excluir Produto'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tem certeza que deseja excluir o produto "$nome"?'),
            if (totalVendasVinculadas > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Este produto possui $totalVendasVinculadas registro(s) em vendas passadas. Ao excluir, seus registros de venda e movimentações serão limpos com segurança.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir Definitivamente'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      setState(() => _isLoading = true);
      try {
        // 1. Limpar registros na tabela entrada_estoque (se houver)
        try {
          await supabase.from('entrada_estoque').delete().eq('produto_id', id);
        } catch (_) {}

        // 2. Limpar itens_venda vinculados
        final itens = await supabase
            .from('itens_venda')
            .select('venda_id, subtotal')
            .eq('produto_id', id);

        if ((itens as List).isNotEmpty) {
          final vendaIds = (itens as List)
              .map((it) => it['venda_id'].toString())
              .toSet();

          for (final vid in vendaIds) {
            final outrosItens = await supabase
                .from('itens_venda')
                .select('subtotal')
                .eq('venda_id', vid)
                .neq('produto_id', id);

            if ((outrosItens as List).isEmpty) {
              // Se a venda só tinha esse item, removemos a venda
              await supabase.from('vendas').delete().eq('id', vid);
            } else {
              // Se a venda tem outros itens, recalculamos o total da venda
              final novoTotal = (outrosItens as List).fold<double>(
                0.0,
                (acc, it) =>
                    acc + (double.tryParse(it['subtotal'].toString()) ?? 0.0),
              );
              await supabase
                  .from('vendas')
                  .update({'valor_total': novoTotal})
                  .eq('id', vid);
            }
          }

          // Exclui os itens_venda do produto
          await supabase.from('itens_venda').delete().eq('produto_id', id);
        }

        // 3. Exclui o produto de produtos
        await supabase.from('produtos').delete().eq('id', id);

        // 4. Remove a associação de pasta local
        await PastasService.setProdutoPasta(id, null);

        // 5. Recarrega a lista
        await _carregarProdutos();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Produto "$nome" excluído com sucesso.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir produto: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final produtosFiltrados = _produtos.where((p) {
      final nome = (p['nome'] ?? '').toString().toLowerCase();
      final codigo = (p['codigo_barras'] ?? '').toString().toLowerCase();
      return nome.contains(_filtroTexto) || codigo.contains(_filtroTexto);
    }).toList();

    final totalItens = _produtos.fold<int>(
      0,
      (soma, p) => soma + (int.tryParse(p['quantidade_estoque'].toString()) ?? 0),
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Cantina PDV',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          // 3 Barras clicáveis no canto superior direito para abrir o menu lateral
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu, size: 28),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),

      // Menu Lateral que abre pelas 3 barras no topo direito
      endDrawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Colors.indigo,
              ),
              child: const SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.point_of_sale, size: 48, color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'Cantina PDV',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Sistema de Vendas & Estoque',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.point_of_sale, color: Colors.green),
              title: const Text('Frente de Caixa (Vendas)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Registrar vendas e abater do estoque'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VendasScreen()),
                );
                _carregarProdutos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.trending_up, color: Colors.teal),
              title: const Text('Histórico & Lucro', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Dashboard de vendas e lucro líquido'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoricoVendasScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.inventory_2, color: Colors.deepPurple),
              title: const Text('Repor Estoque'),
              subtitle: const Text('Dar entrada de produtos via câmera'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EntradaEstoqueScreen()),
                );
                _carregarProdutos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_box, color: Colors.indigo),
              title: const Text('Cadastrar Novo Produto'),
              subtitle: const Text('Adicionar produto ao catálogo'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CadastroProdutoScreen()),
                );
                _carregarProdutos();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.blue),
              title: const Text('Atualizar Dados'),
              onTap: () {
                Navigator.pop(context);
                _carregarProdutos();
              },
            ),
          ],
        ),
      ),

      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Cartões de Acesso Rápido no topo: VENDAS e REPOR ESTOQUE
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                // Botão de Nova Venda
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const VendasScreen()),
                      );
                      _carregarProdutos();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade600, Colors.teal.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withAlpha(50),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.shopping_cart_checkout, color: Colors.white, size: 30),
                          SizedBox(height: 6),
                          Text(
                            'Nova Venda',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Frente de Caixa',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Botão de Repor Estoque
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const EntradaEstoqueScreen()),
                      );
                      _carregarProdutos();
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.deepPurple.shade600, Colors.indigo.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepPurple.withAlpha(50),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.qr_code_scanner, color: Colors.white, size: 30),
                          SizedBox(height: 6),
                          Text(
                            'Repor Estoque',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Entrada via Câmera',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Barra de Pesquisa rápida
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou código...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filtroTexto.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filtroTexto = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (val) {
                setState(() => _filtroTexto = val.trim().toLowerCase());
              },
            ),
          ),

          // Lista de Produtos com PULL-TO-REFRESH
          Expanded(
            child: RefreshIndicator(
              onRefresh: _carregarProdutos,
              color: Colors.indigo,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _temErro
                      ? ListView(
                          children: [
                            const SizedBox(height: 60),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.wifi_off_rounded, size: 64, color: Colors.orange.shade700),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Sem conexão com o servidor',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Verifique se o celular está conectado ao Wi-Fi ou aos dados móveis.',
                                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Tentar Novamente'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: _carregarProdutos,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : produtosFiltrados.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.only(bottom: 120),
                              children: [
                                const SizedBox(height: 60),
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inventory_2_outlined, size: 70, color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        _produtos.isEmpty
                                            ? 'Nenhum produto cadastrado ainda.'
                                            : 'Nenhum produto encontrado na busca.',
                                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(height: 12),
                                      if (_produtos.isEmpty)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.add),
                                          label: const Text('Cadastrar Primeiro Produto'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.indigo,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => const CadastroProdutoScreen()),
                                            );
                                            _carregarProdutos();
                                          },
                                        )
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                // Header com contadores
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${produtosFiltrados.length} produtos exibidos',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'Total em estoque: $totalItens un.',
                                        style: const TextStyle(fontSize: 13, color: Colors.indigo, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                                    itemCount: produtosFiltrados.length,
                                    itemBuilder: (context, index) {
                                      final p = produtosFiltrados[index];
                                      final id = p['id'].toString();
                                      final nome = p['nome'] ?? 'Sem nome';
                                      final codigo = (p['codigo_barras'] ?? '').toString();
                                      final bool semCodigo = codigo.isEmpty || codigo.startsWith('SB-');
                                      final String textoCodigo = semCodigo ? 'Sem código de barras' : codigo;
                                      final String? pastaDoProduto = _produtoPastaMap[id];
                                      final precoVenda = (p['preco_venda'] as num?)?.toDouble() ?? 0.0;
                                      final precoCusto = (p['preco_custo'] as num?)?.toDouble() ?? 0.0;
                                      final estoque = int.tryParse(p['quantidade_estoque'].toString()) ?? 0;

                                      // Cores do estoque
                                      Color estoqueColor;
                                      String estoqueStatus;
                                      if (estoque == 0) {
                                        estoqueColor = Colors.red;
                                        estoqueStatus = 'Esgotado';
                                      } else if (estoque <= 5) {
                                        estoqueColor = Colors.orange.shade800;
                                        estoqueStatus = 'Baixo';
                                      } else {
                                        estoqueColor = Colors.green.shade700;
                                        estoqueStatus = 'Disponível';
                                      }

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 1.5,
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Linha Superior: Nome, Editar e Excluir
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      nome,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.edit, color: Colors.indigo, size: 20),
                                                    tooltip: 'Editar Produto (Nome/Pasta/Preços)',
                                                    onPressed: () => _abrirDialogoEditarProduto(p),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                                    tooltip: 'Excluir Produto',
                                                    onPressed: () => _confirmarExclusao(id, nome),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),

                                              // Código de barras e Preços (Custo e Venda)
                                              Row(
                                                children: [
                                                  Icon(
                                                    semCodigo ? Icons.fastfood_outlined : Icons.qr_code,
                                                    size: 15,
                                                    color: semCodigo ? Colors.orange.shade800 : Colors.grey,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      textoCodigo,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: semCodigo ? Colors.orange.shade900 : Colors.grey.shade700,
                                                        fontWeight: semCodigo ? FontWeight.w600 : FontWeight.normal,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                        'Venda: R\$ ${precoVenda.toStringAsFixed(2)}',
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.indigo,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Custo: R\$ ${precoCusto.toStringAsFixed(2)}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey.shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const Divider(height: 16),

                                              // Linha Limpa de Status do Estoque e Pasta (se houver)
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: estoqueColor.withAlpha(30),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: estoqueColor.withAlpha(100)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        CircleAvatar(radius: 4, backgroundColor: estoqueColor),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          '$estoque un. ($estoqueStatus)',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.bold,
                                                            color: estoqueColor,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (pastaDoProduto != null && pastaDoProduto.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.indigo.shade50,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.indigo.shade200),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.folder_open, size: 13, color: Colors.indigo),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            pastaDoProduto,
                                                            style: const TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.indigo,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
        ],
      ),
    ),

      // Botão Flutuante para Cadastrar Novo Produto
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_novo_produto',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CadastroProdutoScreen()),
          );
          _carregarProdutos();
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo Produto'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }
}
