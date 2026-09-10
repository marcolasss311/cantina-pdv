import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cadastro_produto_screen.dart';
import 'services/pastas_service.dart';

class EntradaEstoqueScreen extends StatefulWidget {
  const EntradaEstoqueScreen({super.key});

  @override
  State<EntradaEstoqueScreen> createState() => _EntradaEstoqueScreenState();
}

class _EntradaEstoqueScreenState extends State<EntradaEstoqueScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _quantidadeController = TextEditingController(text: '1');
  final TextEditingController _custoUnitarioController = TextEditingController();
  final TextEditingController _custoTotalController = TextEditingController();

  bool _isScanning = true;
  bool _isLoading = false;
  Map<String, dynamic>? _produtoEncontrado;

  @override
  void dispose() {
    _scannerController.dispose();
    _codigoController.dispose();
    _quantidadeController.dispose();
    _custoUnitarioController.dispose();
    _custoTotalController.dispose();
    super.dispose();
  }

  // Preenche dados do produto selecionado
  void _selecionarProduto(Map<String, dynamic> data) {
    final precoCusto = (data['preco_custo'] as num?)?.toDouble() ?? 0.0;
    final qtd = int.tryParse(_quantidadeController.text) ?? 1;

    setState(() {
      _produtoEncontrado = data;
      _codigoController.text = (data['codigo_barras'] ?? '').toString();
      _custoUnitarioController.text = precoCusto > 0 ? precoCusto.toStringAsFixed(2) : '';
      _custoTotalController.text = (precoCusto * qtd) > 0 ? (precoCusto * qtd).toStringAsFixed(2) : '';
      _isScanning = false;
    });
  }

  // Busca o produto pelo código de barras ou nome no Supabase
  Future<void> _buscarProduto(String query) async {
    final busca = query.trim();
    if (busca.isEmpty) return;

    setState(() {
      _isLoading = true;
      _codigoController.text = busca;
    });

    try {
      // 1. Tenta buscar por código de barras exato (desconsiderando excluídos)
      var data = await Supabase.instance.client
          .from('produtos')
          .select()
          .eq('codigo_barras', busca)
          .maybeSingle();

      if (data != null && (data['codigo_barras'] ?? '').toString().startsWith('__EXCLUIDO__')) {
        data = null;
      }

      // 2. Se não encontrou por código, busca por nome (filtrando excluídos)
      if (data == null) {
        final listByName = await Supabase.instance.client
            .from('produtos')
            .select()
            .ilike('nome', '%$busca%');

        final ativosByName = List<Map<String, dynamic>>.from(listByName)
            .where((p) => !(p['codigo_barras'] ?? '').toString().startsWith('__EXCLUIDO__'))
            .toList();

        if (ativosByName.isNotEmpty) {
          if (ativosByName.length == 1) {
            data = ativosByName.first;
          } else {
            // Múltiplos produtos encontrados com esse nome: abre o seletor com eles
            if (mounted) {
              setState(() => _isLoading = false);
              _abrirSeletorProdutoManual(produtosIniciais: ativosByName);
            }
            return;
          }
        }
      }

      if (!mounted) return;

      if (data == null) {
        // Produto não cadastrado
        setState(() {
          _produtoEncontrado = null;
          _isScanning = false;
        });

        _exibirDialogoNaoCadastrado(busca);
      } else {
        // Produto encontrado
        _selecionarProduto(data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao consultar servidor. Verifique sua conexão com a internet.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _exibirDialogoNaoCadastrado(String codigo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Não Encontrado'),
          ],
        ),
        content: Text(
          'O código "$codigo" ainda não está cadastrado no sistema.\nDeseja cadastrar agora?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _isScanning = true);
            },
            child: const Text('Escanear Outro'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final cadastrou = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => CadastroProdutoScreen(initialBarcode: codigo),
                ),
              );

              if (cadastrou == true) {
                _buscarProduto(codigo);
              } else {
                setState(() => _isScanning = true);
              }
            },
            child: const Text('Cadastrar Produto'),
          ),
        ],
      ),
    );
  }

  // Salva a entrada de estoque no banco
  Future<void> _confirmarEntrada() async {
    if (_produtoEncontrado == null) return;

    final qtdAdicionar = int.tryParse(_quantidadeController.text.trim()) ?? 0;
    if (qtdAdicionar == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma quantidade diferente de zero!')),
      );
      return;
    }

    final custoUnitario = double.tryParse(_custoUnitarioController.text.replaceAll(',', '.').trim()) ??
        ((_produtoEncontrado!['preco_custo'] as num?)?.toDouble() ?? 0.0);
    final custoTotal = double.tryParse(_custoTotalController.text.replaceAll(',', '.').trim()) ?? (custoUnitario * qtdAdicionar);
    final estoqueAtual = int.tryParse(_produtoEncontrado!['quantidade_estoque'].toString()) ?? 0;
    final novoEstoque = estoqueAtual + qtdAdicionar;

    if (novoEstoque < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A quantidade a remover é maior do que o estoque atual!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final produtoId = _produtoEncontrado!['id'];

      // 1. Registra no histórico de Entrada_Estoque (apenas se for adição positiva)
      if (qtdAdicionar > 0) {
        await supabase.from('entrada_estoque').insert({
          'produto_id': produtoId,
          'quantidade_comprada': qtdAdicionar,
          'custo_total_compra': custoTotal,
        });
      }

      // 2. Atualiza o saldo de estoque e o preço de custo na tabela produtos
      await supabase.from('produtos').update({
        'quantidade_estoque': novoEstoque,
        'preco_custo': custoUnitario,
      }).eq('id', produtoId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque de "${_produtoEncontrado!['nome']}" atualizado: $novoEstoque un.',
            ),
            backgroundColor: Colors.green,
          ),
        );

        _reabrirOuVoltar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao atualizar estoque. Verifique sua conexão com a internet.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Modal para selecionar produto da lista (sem código ou manual)
  Future<void> _abrirSeletorProdutoManual({List<Map<String, dynamic>>? produtosIniciais}) async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> todosProdutos = [];
    Map<String, String> pastaMap = {};
    try {
      if (produtosIniciais != null && produtosIniciais.isNotEmpty) {
        todosProdutos = produtosIniciais
            .where((p) => !(p['codigo_barras'] ?? '').toString().startsWith('__EXCLUIDO__'))
            .toList();
      } else {
        final res = await Supabase.instance.client
            .from('produtos')
            .select()
            .order('nome', ascending: true);
        todosProdutos = List<Map<String, dynamic>>.from(res)
            .where((p) => !(p['codigo_barras'] ?? '').toString().startsWith('__EXCLUIDO__'))
            .toList();
      }
      pastaMap = await PastasService.getProdutoPastaMap();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao carregar lista de produtos.')),
        );
      }
      setState(() => _isLoading = false);
      return;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String busca = '';
        String filtroTipo = 'todos'; // 'todos', 'sem_codigo'

        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtrados = todosProdutos.where((p) {
              final nome = (p['nome'] ?? '').toString().toLowerCase();
              final cod = (p['codigo_barras'] ?? '').toString().toLowerCase();
              final isSemCodigo = cod.startsWith('sb-') || cod.isEmpty;

              if (filtroTipo == 'sem_codigo' && !isSemCodigo) return false;
              if (busca.isNotEmpty && !nome.contains(busca.toLowerCase()) && !cod.contains(busca.toLowerCase())) {
                return false;
              }
              return true;
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.inventory_2, color: Colors.deepPurple),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Selecionar Produto para Reposição',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Pesquisar produto pelo nome...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setModalState(() => busca = v.trim()),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: filtroTipo == 'todos',
                          onSelected: (_) => setModalState(() => filtroTipo = 'todos'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.restaurant, size: 16),
                          label: const Text('Sem Código de Barras'),
                          selected: filtroTipo == 'sem_codigo',
                          selectedColor: Colors.amber.shade200,
                          onSelected: (_) => setModalState(() => filtroTipo = 'sem_codigo'),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Expanded(
                      child: filtrados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  const Text('Nenhum produto encontrado', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: filtrados.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final p = filtrados[idx];
                                final id = p['id'].toString();
                                final nome = p['nome'] ?? '';
                                final cod = (p['codigo_barras'] ?? '').toString();
                                final isSemCodigo = cod.startsWith('SB-') || cod.isEmpty;
                                final estoque = p['quantidade_estoque'] ?? 0;
                                final pasta = pastaMap[id];

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSemCodigo ? Colors.amber.shade100 : Colors.deepPurple.shade50,
                                    child: Icon(
                                      isSemCodigo ? Icons.restaurant : Icons.qr_code,
                                      color: isSemCodigo ? Colors.amber.shade900 : Colors.deepPurple,
                                    ),
                                  ),
                                  title: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Wrap(
                                    spacing: 6,
                                    children: [
                                      Text('Estoque: $estoque un.', style: const TextStyle(fontSize: 12)),
                                      if (isSemCodigo)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amber.shade300),
                                          ),
                                          child: Text('Sem código', style: TextStyle(fontSize: 10, color: Colors.amber.shade900)),
                                        ),
                                      if (pasta != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.indigo.shade200),
                                          ),
                                          child: Text('📁 $pasta', style: TextStyle(fontSize: 10, color: Colors.indigo.shade800)),
                                        ),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _selecionarProduto(p);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _reabrirOuVoltar() {
    setState(() {
      _produtoEncontrado = null;
      _codigoController.clear();
      _quantidadeController.text = '1';
      _custoUnitarioController.clear();
      _custoTotalController.clear();
      _isScanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrada / Reposição de Estoque'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.list_alt : Icons.camera_alt),
            tooltip: _isScanning ? 'Digitar Código' : 'Abrir Câmera',
            onPressed: () {
              setState(() {
                _isScanning = !_isScanning;
              });
            },
          )
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: _isScanning ? _buildScanner() : _buildDetalhesEntrada(),
      ),
    );
  }

  // SCANNER DE CÂMERA
  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              final code = barcodes.first.rawValue;
              if (code != null && code.isNotEmpty) {
                _buscarProduto(code);
              }
            }
          },
        ),
        Positioned(
          bottom: 40 + MediaQuery.of(context).viewPadding.bottom,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(180),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Aponte a câmera para o código de barras do produto',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Escolher da Lista (Sem Código / Manual)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _abrirSeletorProdutoManual(),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Digitar código ou nome'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() => _isScanning = false);
                },
              ),
            ],
          ),
        ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
      ],
    );
  }

  // DETALHES DA ENTRADA QUANDO O PRODUTO É LOCALIZADO
  Widget _buildDetalhesEntrada() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
        children: [
          // Botão destacado para escolher produto da lista (sem código / manual)
          ElevatedButton.icon(
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text(
              'Escolher Produto da Lista (Sem Código)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
            onPressed: () => _abrirSeletorProdutoManual(),
          ),
          const SizedBox(height: 14),

          // Campo para digitar código ou pesquisar por nome
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codigoController,
                  decoration: const InputDecoration(
                    labelText: 'Código de Barras ou Nome',
                    hintText: 'Digite o código ou nome...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (val) => _buscarProduto(val),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.search),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: () => _buscarProduto(_codigoController.text),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                icon: const Icon(Icons.camera_alt),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                ),
                tooltip: 'Reabrir Câmera',
                onPressed: () => setState(() => _isScanning = true),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_produtoEncontrado != null) ...[
            // Card de resumo do produto encontrado
            Card(
              elevation: 2,
              color: Colors.deepPurple.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _produtoEncontrado!['nome'] ?? '',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('Trocar'),
                          style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
                          onPressed: () => _abrirSeletorProdutoManual(),
                        ),
                      ],
                    ),
                    if ((_produtoEncontrado!['codigo_barras'] ?? '').toString().startsWith('SB-') ||
                        (_produtoEncontrado!['codigo_barras'] ?? '').toString().isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Text(
                            'Produto sem código de barras',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Estoque Atual', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(
                              '${_produtoEncontrado!['quantidade_estoque']} un.',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Preço de Venda', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(
                              'R\$ ${((_produtoEncontrado!['preco_venda'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Campos para adicionar estoque
            const Text(
              'Dados da Reposição',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantidadeController,
                    decoration: const InputDecoration(
                      labelText: 'Qtd. a Adicionar',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.add_shopping_cart),
                      helperText: 'Ex: 10 unidades',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    onChanged: (val) {
                      final qtd = int.tryParse(val) ?? 0;
                      final custoUnit = double.tryParse(_custoUnitarioController.text.replaceAll(',', '.')) ?? 0.0;
                      if (qtd > 0) {
                        _custoTotalController.text = (custoUnit * qtd).toStringAsFixed(2);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _custoUnitarioController,
                    decoration: const InputDecoration(
                      labelText: 'Custo Unitário (R\$)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.monetization_on_outlined),
                      helperText: 'Preço pago por item',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (val) {
                      final custoUnit = double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
                      final qtd = int.tryParse(_quantidadeController.text) ?? 0;
                      if (qtd > 0) {
                        _custoTotalController.text = (custoUnit * qtd).toStringAsFixed(2);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _custoTotalController,
              decoration: const InputDecoration(
                labelText: 'Custo Total da Compra (R\$)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                helperText: 'Total pago nesta reposição',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Confirmar Entrada de Estoque', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isLoading ? null : _confirmarEntrada,
              ),
            ),
            const SizedBox(height: 32),
          ] else ...[
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 70, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Digite o código ou nome acima, ou toque no botão\n"Escolher Produto da Lista" para repor produtos sem código.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt, color: Colors.deepPurple),
                    label: const Text('Ver todos os produtos', style: TextStyle(color: Colors.deepPurple)),
                    onPressed: () => _abrirSeletorProdutoManual(),
                  ),
                ],
              ),
            )
          ],
        ],
      ),
    );
  }
}
