import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/pastas_service.dart';

class ItemCarrinho {
  final Map<String, dynamic> produto;
  int quantidade;

  ItemCarrinho({required this.produto, this.quantidade = 1});

  double get precoUnitario => (produto['preco_venda'] as num?)?.toDouble() ?? 0.0;
  double get subtotal => precoUnitario * quantidade;
  int get estoqueMaximo => int.tryParse(produto['quantidade_estoque'].toString()) ?? 0;
}

class VendasScreen extends StatefulWidget {
  const VendasScreen({super.key});

  @override
  State<VendasScreen> createState() => _VendasScreenState();
}

class _VendasScreenState extends State<VendasScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  List<Map<String, dynamic>> _produtos = [];
  final Map<String, ItemCarrinho> _carrinho = {}; // Chave: produto_id
  List<String> _pastas = [];
  String? _pastaSelecionada;
  Map<String, String> _produtoPastaMap = {};

  String _filtroTexto = '';
  bool _mostrarTodos = false;
  bool _isLoading = true;
  bool _isFinalizando = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _carregarProdutos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // Carrega produtos do Supabase e pastas locais
  Future<void> _carregarProdutos() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('produtos')
          .select()
          .order('nome', ascending: true);
      final pastas = await PastasService.getPastas();
      final pastaMap = await PastasService.getProdutoPastaMap();

      if (mounted) {
        setState(() {
          _produtos = List<Map<String, dynamic>>.from(data)
              .where((p) => !(p['codigo_barras'] ?? '').toString().startsWith('__EXCLUIDO__'))
              .toList();
          _pastas = pastas;
          _produtoPastaMap = pastaMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao carregar lista de produtos. Verifique sua conexão.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Total geral do carrinho
  double get _totalVenda {
    return _carrinho.values.fold(0.0, (soma, item) => soma + item.subtotal);
  }

  int get _totalItensCarrinho {
    return _carrinho.values.fold(0, (soma, item) => soma + item.quantidade);
  }

  // Adiciona produto ao carrinho
  void _adicionarAoCarrinho(Map<String, dynamic> produto) {
    final id = produto['id'].toString();
    final estoque = int.tryParse(produto['quantidade_estoque'].toString()) ?? 0;

    if (estoque <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${produto['nome']}" está esgotado no estoque!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      if (_carrinho.containsKey(id)) {
        if (_carrinho[id]!.quantidade < estoque) {
          _carrinho[id]!.quantidade++;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Limite de estoque atingido ($estoque un.)'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        _carrinho[id] = ItemCarrinho(produto: produto, quantidade: 1);
      }
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${produto['nome']} adicionado ao carrinho!'),
        duration: const Duration(milliseconds: 900),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  // Remove ou diminui do carrinho
  void _removerDoCarrinho(String produtoId) {
    setState(() {
      if (_carrinho.containsKey(produtoId)) {
        if (_carrinho[produtoId]!.quantidade > 1) {
          _carrinho[produtoId]!.quantidade--;
        } else {
          _carrinho.remove(produtoId);
        }
      }
    });
  }

  // Bipa o produto pelo código de barras e adiciona direto
  void _processarCodigoBarras(String codigo) {
    final code = codigo.trim();
    if (code.isEmpty) return;

    final produto = _produtos.firstWhere(
      (p) => (p['codigo_barras'] ?? '').toString() == code,
      orElse: () => {},
    );

    if (produto.isNotEmpty) {
      setState(() => _isScanning = false);
      _adicionarAoCarrinho(produto);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Código "$code" não encontrado na lista de produtos.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Abre modal quadrado com 4 opções de pagamento: DINHEIRO, PIX, DEBITO/CREDITO, OUTROS
  void _abrirModalFormaPagamento() {
    if (_carrinho.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        title: Column(
          children: [
            const Text(
              'Forma de Pagamento',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Total: R\$ ${_totalVenda.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.green,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Selecione como o cliente vai pagar:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Grid 2x2 de botões quadrados de pagamento
              Row(
                children: [
                  Expanded(
                    child: _buildSquarePaymentOption(
                      label: 'DINHEIRO',
                      icon: Icons.payments_outlined,
                      color: Colors.green.shade700,
                      bgColor: Colors.green.shade50,
                      onTap: () {
                        Navigator.pop(ctx);
                        _finalizarVenda('DINHEIRO');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSquarePaymentOption(
                      label: 'PIX',
                      icon: Icons.qr_code_2,
                      color: Colors.teal.shade700,
                      bgColor: Colors.teal.shade50,
                      onTap: () {
                        Navigator.pop(ctx);
                        _finalizarVenda('PIX');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildSquarePaymentOption(
                      label: 'DÉBITO / CRÉDITO',
                      icon: Icons.credit_card,
                      color: Colors.blue.shade700,
                      bgColor: Colors.blue.shade50,
                      onTap: () {
                        Navigator.pop(ctx);
                        _finalizarVenda('DEBITO/CREDITO');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSquarePaymentOption(
                      label: 'OUTROS',
                      icon: Icons.more_horiz,
                      color: Colors.purple.shade700,
                      bgColor: Colors.purple.shade50,
                      onTap: () {
                        Navigator.pop(ctx);
                        _finalizarVenda('OUTROS');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSquarePaymentOption({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: color.withAlpha(80), width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 36),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Finaliza a venda e desconta do estoque no banco
  Future<void> _finalizarVenda(String formaPagamento) async {
    if (_carrinho.isEmpty) return;

    setState(() => _isFinalizando = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Registra na tabela de vendas
      final vendaRes = await supabase
          .from('vendas')
          .insert({
            'valor_total': _totalVenda,
            'forma_pagamento': formaPagamento,
            'data_hora': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final vendaId = vendaRes['id'];

      // 2. Grava itens_venda e abate estoque em produtos
      for (final item in _carrinho.values) {
        // Insere item da venda
        await supabase.from('itens_venda').insert({
          'venda_id': vendaId,
          'produto_id': item.produto['id'],
          'quantidade_vendida': item.quantidade,
          'subtotal': item.subtotal,
        });

        // Abate estoque
        final novoEstoque = item.estoqueMaximo - item.quantidade;
        await supabase.from('produtos').update({
          'quantidade_estoque': novoEstoque < 0 ? 0 : novoEstoque,
        }).eq('id', item.produto['id']);
      }

      if (mounted) {
        final totalFormatado = _totalVenda.toStringAsFixed(2);
        setState(() {
          _carrinho.clear();
          _isFinalizando = false;
        });

        // Atualiza a lista com o novo saldo
        _carregarProdutos();

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 56),
            title: const Text('Venda Realizada!'),
            content: Text(
              'Venda de R\$ $totalFormatado finalizada com sucesso via $formaPagamento!\nO estoque já foi atualizado.',
              textAlign: TextAlign.center,
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFinalizando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao finalizar venda. Verifique a internet e tente novamente.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // DIÁLOGOS DE GERENCIAMENTO DE PASTAS
  Future<void> _dialogoNovaPasta() async {
    final controller = TextEditingController();
    final criada = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.create_new_folder, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Nova Pasta'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nome da Pasta',
            hintText: 'Ex: Hambúrguer, Prato Executivo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () async {
              final nome = controller.text.trim();
              if (nome.isNotEmpty) {
                await PastasService.criarPasta(nome);
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (criada == true) {
      final pastas = await PastasService.getPastas();
      setState(() {
        _pastas = pastas;
        _pastaSelecionada = controller.text.trim();
      });
    }
  }

  Future<void> _dialogoGerenciarProdutosPasta(String pasta) async {
    final idsSelecionados = <String>{};
    for (final entry in _produtoPastaMap.entries) {
      if (entry.value == pasta) {
        idsSelecionados.add(entry.key);
      }
    }

    String busca = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final produtosFiltrados = _produtos.where((p) {
            final nome = (p['nome'] ?? '').toString().toLowerCase();
            return nome.contains(busca.toLowerCase());
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.folder_open, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Produtos da pasta "$pasta"',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Filtrar produtos...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setDialogState(() => busca = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: produtosFiltrados.isEmpty
                        ? const Center(child: Text('Nenhum produto encontrado'))
                        : ListView.separated(
                            itemCount: produtosFiltrados.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final p = produtosFiltrados[idx];
                              final id = p['id'].toString();
                              final nome = p['nome'] ?? '';
                              final checked = idsSelecionados.contains(id);

                              return CheckboxListTile(
                                value: checked,
                                title: Text(nome, style: const TextStyle(fontSize: 14)),
                                subtitle: Text(
                                  (p['codigo_barras'] ?? '').toString().startsWith('SB-')
                                      ? 'Sem código de barras'
                                      : 'Cód: ${p['codigo_barras'] ?? ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                dense: true,
                                onChanged: (val) {
                                  setDialogState(() {
                                    if (val == true) {
                                      idsSelecionados.add(id);
                                    } else {
                                      idsSelecionados.remove(id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                onPressed: () async {
                  // Salva associações
                  await PastasService.setProdutosPasta(idsSelecionados.toList(), pasta);
                  // Remove desmarcados que antes pertenciam a essa pasta
                  final desmarcados = _produtos
                      .map((p) => p['id'].toString())
                      .where((id) => !idsSelecionados.contains(id) && _produtoPastaMap[id] == pasta)
                      .toList();
                  if (desmarcados.isNotEmpty) {
                    await PastasService.removerProdutosDaPasta(desmarcados);
                  }

                  final novoMap = await PastasService.getProdutoPastaMap();
                  if (mounted) {
                    setState(() {
                      _produtoPastaMap = novoMap;
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _dialogoOpcoesPasta(String pasta) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add, color: Colors.indigo),
              title: const Text('Adicionar / Remover Produtos'),
              onTap: () {
                Navigator.pop(ctx);
                _dialogoGerenciarProdutosPasta(pasta);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Renomear Pasta'),
              onTap: () async {
                Navigator.pop(ctx);
                final controller = TextEditingController(text: pasta);
                final renomeou = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Renomear Pasta'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Novo nome'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancelar')),
                      ElevatedButton(
                        onPressed: () {
                          if (controller.text.trim().isNotEmpty) {
                            Navigator.pop(dCtx, true);
                          }
                        },
                        child: const Text('Salvar'),
                      ),
                    ],
                  ),
                );

                if (renomeou == true) {
                  final novoNome = controller.text.trim();
                  await PastasService.renomearPasta(pasta, novoNome);
                  final pastas = await PastasService.getPastas();
                  final pastaMap = await PastasService.getProdutoPastaMap();
                  setState(() {
                    _pastas = pastas;
                    _produtoPastaMap = pastaMap;
                    _pastaSelecionada = novoNome;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Excluir Pasta', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmou = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('Excluir Pasta?'),
                    content: Text('Os produtos dentro da pasta "$pasta" continuarão cadastrados, mas não estarão mais organizados nesta pasta.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancelar')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: const Text('Excluir'),
                      ),
                    ],
                  ),
                );

                if (confirmou == true) {
                  await PastasService.excluirPasta(pasta);
                  final pastas = await PastasService.getPastas();
                  final pastaMap = await PastasService.getProdutoPastaMap();
                  setState(() {
                    _pastas = pastas;
                    _produtoPastaMap = pastaMap;
                    _pastaSelecionada = null;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Modal para ver detalhes do carrinho
  void _abrirModalCarrinho() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final itens = _carrinho.values.toList();

            final bottomPadding = MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).viewPadding.bottom +
                16.0;

            return SafeArea(
              top: false,
              bottom: true,
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shopping_cart, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Text(
                        'Itens da Venda ($_totalItensCarrinho)',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (itens.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() => _carrinho.clear());
                            setModalState(() {});
                            Navigator.pop(ctx);
                          },
                          child: const Text('Limpar', style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                  const Divider(),
                  if (itens.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(
                        child: Text('Carrinho vazio', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: itens.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = itens[idx];
                          final id = item.produto['id'].toString();

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.produto['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('R\$ ${item.precoUnitario.toStringAsFixed(2)} un.'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () {
                                    _removerDoCarrinho(id);
                                    setModalState(() {});
                                    setState(() {});
                                  },
                                ),
                                Text(
                                  '${item.quantidade}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                  onPressed: () {
                                    if (item.quantidade < item.estoqueMaximo) {
                                      setState(() => item.quantidade++);
                                      setModalState(() {});
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Estoque máximo atingido!'),
                                          duration: Duration(milliseconds: 800),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'R\$ ${item.subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                        'R\$ ${_totalVenda.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: itens.isEmpty || _isFinalizando
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _abrirModalFormaPagamento();
                          },
                    child: _isFinalizando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Finalizar Venda', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
        );
      },
    );
  }

  // Card individual para a Grid de Pastas/Categorias
  Widget _buildFolderCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required VoidCallback onTap,
    VoidCallback? onOptions,
  }) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [backgroundColor, Colors.white],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: color.withAlpha(40),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (onOptions != null)
                    IconButton(
                      icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Opções da Pasta',
                      onPressed: onOptions,
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Grid Principal destacando as Pastas / Categorias
  Widget _buildGridPastas() {
    final produtosSemPasta = _produtos.where((p) => _produtoPastaMap[p['id'].toString()] == null).toList();

    return RefreshIndicator(
      onRefresh: _carregarProdutos,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.folder_special, color: Colors.indigo, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Categorias / Pastas',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.indigo),
                label: const Text('Nova Pasta', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                onPressed: _dialogoNovaPasta,
              ),
            ],
          ),
          const SizedBox(height: 10),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.22,
            ),
            itemCount: _pastas.length + 2 + (produtosSemPasta.isNotEmpty ? 1 : 0),
            itemBuilder: (context, index) {
              // 1º Card: Todos os Produtos
              if (index == 0) {
                return _buildFolderCard(
                  title: 'Todos os Produtos',
                  subtitle: '${_produtos.length} produtos',
                  icon: Icons.apps,
                  color: Colors.indigo,
                  backgroundColor: Colors.indigo.shade50,
                  onTap: () {
                    setState(() {
                      _mostrarTodos = true;
                      _pastaSelecionada = null;
                    });
                  },
                );
              }

              // Pastas criadas pelo usuário
              final folderIndex = index - 1;
              if (folderIndex < _pastas.length) {
                final pasta = _pastas[folderIndex];
                final count = _produtos.where((p) => _produtoPastaMap[p['id'].toString()] == pasta).length;
                return _buildFolderCard(
                  title: pasta,
                  subtitle: '$count ${count == 1 ? "produto" : "produtos"}',
                  icon: Icons.folder,
                  color: Colors.deepOrange.shade700,
                  backgroundColor: Colors.orange.shade50,
                  onOptions: () => _dialogoOpcoesPasta(pasta),
                  onTap: () {
                    setState(() {
                      _pastaSelecionada = pasta;
                      _mostrarTodos = false;
                    });
                  },
                );
              }

              // Produtos sem pasta (se houver)
              if (produtosSemPasta.isNotEmpty && index == _pastas.length + 1) {
                return _buildFolderCard(
                  title: 'Sem Pasta',
                  subtitle: '${produtosSemPasta.length} avulsos',
                  icon: Icons.folder_off_outlined,
                  color: Colors.blueGrey,
                  backgroundColor: Colors.blueGrey.shade50,
                  onTap: () {
                    setState(() {
                      _pastaSelecionada = '__SEM_PASTA__';
                      _mostrarTodos = false;
                    });
                  },
                );
              }

              // Card "+ Nova Pasta"
              return InkWell(
                onTap: _dialogoNovaPasta,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.indigo.shade200, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.indigo.shade50,
                        child: const Icon(Icons.add, color: Colors.indigo, size: 24),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '+ Nova Pasta',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Criar categoria',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return _buildScanner();
    }

    final produtosFiltrados = _produtos.where((p) {
      final nome = (p['nome'] ?? '').toString().toLowerCase();
      final codigo = (p['codigo_barras'] ?? '').toString().toLowerCase();
      final matchesTexto = _filtroTexto.isEmpty || nome.contains(_filtroTexto) || codigo.contains(_filtroTexto);
      if (!matchesTexto) return false;

      if (_pastaSelecionada != null) {
        final id = p['id'].toString();
        if (_pastaSelecionada == '__SEM_PASTA__') {
          return _produtoPastaMap[id] == null;
        }
        return _produtoPastaMap[id] == _pastaSelecionada;
      }
      return true;
    }).toList();

    final exibirGridPastas = _filtroTexto.isEmpty && _pastaSelecionada == null && !_mostrarTodos;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Frente de Caixa (Vendas)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Bipar Produto com Câmera',
            onPressed: () => setState(() => _isScanning = true),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
          // Campo de busca por texto ou código
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar produto ou código...',
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                    onSubmitted: (val) {
                      _processarCodigoBarras(val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.qr_code_scanner),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.all(14),
                  ),
                  tooltip: 'Escanear Código',
                  onPressed: () => setState(() => _isScanning = true),
                ),
              ],
            ),
          ),

          if (exibirGridPastas)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildGridPastas(),
            )
          else ...[
            // Barra Horizontal de Seleção de Pastas
            Container(
              height: 44,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.folder_special, size: 16),
                    label: const Text('Categorias'),
                    selected: false,
                    onSelected: (_) {
                      _searchController.clear();
                      setState(() {
                        _pastaSelecionada = null;
                        _mostrarTodos = false;
                        _filtroTexto = '';
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.apps, size: 16),
                    label: const Text('Todos'),
                    selected: _mostrarTodos && _pastaSelecionada == null,
                    selectedColor: Colors.indigo,
                    labelStyle: TextStyle(
                      color: (_mostrarTodos && _pastaSelecionada == null) ? Colors.white : Colors.indigo.shade900,
                      fontWeight: (_mostrarTodos && _pastaSelecionada == null) ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      setState(() {
                        _mostrarTodos = true;
                        _pastaSelecionada = null;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ..._pastas.map((pasta) {
                    final isSelected = _pastaSelecionada == pasta;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        avatar: Icon(
                          isSelected ? Icons.folder_open : Icons.folder,
                          size: 16,
                          color: isSelected ? Colors.white : Colors.indigo,
                        ),
                        label: Text(pasta),
                        selected: isSelected,
                        selectedColor: Colors.indigo,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.indigo.shade900,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          setState(() {
                            _pastaSelecionada = val ? pasta : null;
                            _mostrarTodos = false;
                          });
                        },
                      ),
                    );
                  }),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16, color: Colors.indigo),
                    label: const Text('Nova Pasta', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 12)),
                    backgroundColor: Colors.indigo.shade50,
                    side: BorderSide(color: Colors.indigo.shade200),
                    onPressed: _dialogoNovaPasta,
                  ),
                ],
              ),
            ),

            // Barra de Navegação de Pasta / Busca
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _pastaSelecionada = null;
                        _mostrarTodos = false;
                        _filtroTexto = '';
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text('Pastas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filtroTexto.isNotEmpty
                          ? 'Busca: "$_filtroTexto" (${produtosFiltrados.length} itens)'
                          : (_mostrarTodos
                              ? 'Todos os Produtos (${produtosFiltrados.length} itens)'
                              : (_pastaSelecionada == '__SEM_PASTA__'
                                  ? 'Sem Pasta (${produtosFiltrados.length} itens)'
                                  : 'Pasta: $_pastaSelecionada (${produtosFiltrados.length} itens)')),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_pastaSelecionada != null && _pastaSelecionada != '__SEM_PASTA__') ...[
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.playlist_add, size: 16, color: Colors.indigo),
                      label: const Text('Itens', style: TextStyle(color: Colors.indigo, fontSize: 11)),
                      onPressed: () => _dialogoGerenciarProdutosPasta(_pastaSelecionada!),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.indigo, size: 16),
                      tooltip: 'Opções da Pasta',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _dialogoOpcoesPasta(_pastaSelecionada!),
                    ),
                  ],
                ],
              ),
            ),

          // Lista com Pull-to-Refresh
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _carregarProdutos,
                    child: produtosFiltrados.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Text(
                                  _pastaSelecionada != null
                                      ? 'Nenhum produto na pasta "$_pastaSelecionada".\nToque em "Itens" acima para adicionar!'
                                      : 'Nenhum produto disponível para venda.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey, fontSize: 15),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            itemCount: produtosFiltrados.length,
                            itemBuilder: (context, index) {
                              final p = produtosFiltrados[index];
                              final id = p['id'].toString();
                              final nome = p['nome'] ?? 'Sem nome';
                              final codigo = (p['codigo_barras'] ?? '').toString();
                              final isSemBarras = codigo.startsWith('SB-') || codigo.isEmpty;
                              final preco = (p['preco_venda'] as num?)?.toDouble() ?? 0.0;
                              final estoque = int.tryParse(p['quantidade_estoque'].toString()) ?? 0;
                              final estaNoCarrinho = _carrinho.containsKey(id);
                              final qtdCarrinho = estaNoCarrinho ? _carrinho[id]!.quantidade : 0;
                              final esgotado = estoque <= 0;
                              final pastaDoProduto = _produtoPastaMap[id];

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 1,
                                child: ListTile(
                                  onTap: esgotado ? null : () => _adicionarAoCarrinho(p),
                                  leading: CircleAvatar(
                                    backgroundColor: esgotado
                                        ? Colors.red.shade100
                                        : (isSemBarras ? Colors.amber.shade100 : Colors.indigo.shade50),
                                    child: Icon(
                                      isSemBarras ? Icons.restaurant : Icons.fastfood,
                                      color: esgotado ? Colors.red : (isSemBarras ? Colors.amber.shade900 : Colors.indigo),
                                    ),
                                  ),
                                  title: Text(
                                    nome,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: esgotado ? Colors.grey : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            'R\$ ${preco.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: esgotado ? Colors.grey : Colors.green.shade800,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: esgotado ? Colors.red.shade50 : Colors.indigo.shade50,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              esgotado ? 'Esgotado' : '$estoque un.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: esgotado ? Colors.red : Colors.indigo,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          if (isSemBarras)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.shade100,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Sem código',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            )
                                          else
                                            Text(
                                              'Cód: $codigo',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                          if (pastaDoProduto != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.indigo.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '📁 $pastaDoProduto',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.indigo.shade800,
                                                ),
                                              ),
                                            ),
                                          if (estaNoCarrinho)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '$qtdCarrinho no carrinho',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton.filled(
                                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                                    style: IconButton.styleFrom(
                                      backgroundColor: esgotado ? Colors.grey.shade300 : Colors.indigo,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: esgotado ? null : () => _adicionarAoCarrinho(p),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ],
    ),
    ),

      // Barra Inferior de Resumo do Carrinho (usando bottomNavigationBar para respeitar a barra do Android)
      bottomNavigationBar: _carrinho.isEmpty
          ? null
          : SafeArea(
              top: false,
              bottom: true,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(25),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: _abrirModalCarrinho,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shopping_cart, color: Colors.indigo, size: 20),
                              const SizedBox(width: 6),
                              Text(
                                '$_totalItensCarrinho itens',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Text(
                            'R\$ ${_totalVenda.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isFinalizando ? null : _abrirModalFormaPagamento,
                      child: _isFinalizando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Finalizar Venda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // TELA DO SCANNER DA CÂMERA
  Widget _buildScanner() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Código de Barras'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _isScanning = false),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null && code.isNotEmpty) {
                  _processarCodigoBarras(code);
                }
              }
            },
          ),
          Positioned(
            bottom: 40 + MediaQuery.of(context).viewPadding.bottom,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(180),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Aponte para o código de barras para adicionar à venda',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
