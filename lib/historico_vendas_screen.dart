import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PeriodoFiltro { hoje, semana, mes, geral }

class HistoricoVendasScreen extends StatefulWidget {
  final int initialIndex;
  const HistoricoVendasScreen({super.key, this.initialIndex = 0});

  @override
  State<HistoricoVendasScreen> createState() => _HistoricoVendasScreenState();
}

class _HistoricoVendasScreenState extends State<HistoricoVendasScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _todasVendas = [];
  List<Map<String, dynamic>> _todosProdutos = [];
  bool _isLoading = true;
  String? _erro;

  PeriodoFiltro _filtroSelecionado = PeriodoFiltro.geral;
  int _limiteVendasExibidas = 5; // Carrega de 5 em 5 vendas para manter o app leve

  // Controle da aba de Zerar Vendas
  final TextEditingController _zerarConfirmacaoController = TextEditingController();
  bool _zerarBotaoHabilitado = false;
  bool _isZerando = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _carregarDados();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _zerarConfirmacaoController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() {
      _isLoading = true;
      _erro = null;
    });

    try {
      final supabase = Supabase.instance.client;

      // 1. Busca todas as vendas e itens com os produtos vinculados
      final vendasRes = await supabase
          .from('vendas')
          .select('''
            id,
            data_hora,
            valor_total,
            forma_pagamento,
            itens_venda (
              produto_id,
              quantidade_vendida,
              subtotal,
              produtos (
                id,
                nome,
                preco_custo,
                preco_venda,
                quantidade_estoque
              )
            )
          ''')
          .order('data_hora', ascending: false);

      // 2. Busca catálogo completo de produtos para o relatório
      final produtosRes = await supabase
          .from('produtos')
          .select()
          .order('nome', ascending: true);

      if (mounted) {
        setState(() {
          _todasVendas = List<Map<String, dynamic>>.from(vendasRes);
          _todosProdutos = List<Map<String, dynamic>>.from(produtosRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Não foi possível carregar os dados. Verifique sua conexão.';
          _isLoading = false;
        });
      }
    }
  }

  // Filtra as vendas com base no período selecionado (Hoje / Semana / Mês / Geral)
  List<Map<String, dynamic>> get _vendasFiltradasPorPeriodo {
    final agora = DateTime.now();

    return _todasVendas.where((v) {
      final dataStr = v['data_hora']?.toString();
      if (dataStr == null) return false;

      final dt = DateTime.tryParse(dataStr)?.toLocal();
      if (dt == null) return false;

      switch (_filtroSelecionado) {
        case PeriodoFiltro.hoje:
          return dt.year == agora.year && dt.month == agora.month && dt.day == agora.day;
        case PeriodoFiltro.semana:
          final seteDiasAtras = agora.subtract(const Duration(days: 7));
          return dt.isAfter(seteDiasAtras);
        case PeriodoFiltro.mes:
          final trintaDiasAtras = agora.subtract(const Duration(days: 30));
          return dt.isAfter(trintaDiasAtras);
        case PeriodoFiltro.geral:
          return true;
      }
    }).toList();
  }

  // Métricas calculadas para o período selecionado
  double get _faturamentoPeriodo {
    return _vendasFiltradasPorPeriodo.fold(0.0, (soma, v) {
      return soma + ((v['valor_total'] as num?)?.toDouble() ?? 0.0);
    });
  }

  double get _custoPeriodo {
    double custo = 0.0;
    for (final v in _vendasFiltradasPorPeriodo) {
      final itens = v['itens_venda'] as List<dynamic>? ?? [];
      for (final item in itens) {
        final qtd = (item['quantidade_vendida'] as num?)?.toInt() ?? 0;
        final prod = item['produtos'] as Map<String, dynamic>?;
        final precoCusto = (prod?['preco_custo'] as num?)?.toDouble() ?? 0.0;
        custo += (precoCusto * qtd);
      }
    }
    return custo;
  }

  double get _lucroPeriodo => _faturamentoPeriodo - _custoPeriodo;

  // Faturamento agrupado por forma de pagamento
  Map<String, double> get _faturamentoPorFormaPagamento {
    final map = <String, double>{
      'DINHEIRO': 0.0,
      'PIX': 0.0,
      'DEBITO/CREDITO': 0.0,
      'OUTROS': 0.0,
    };

    for (final v in _vendasFiltradasPorPeriodo) {
      final forma = (v['forma_pagamento'] ?? 'OUTROS').toString().toUpperCase();
      final total = ((v['valor_total'] as num?)?.toDouble() ?? 0.0);
      if (forma.contains('DINHEIRO')) {
        map['DINHEIRO'] = (map['DINHEIRO'] ?? 0.0) + total;
      } else if (forma.contains('PIX')) {
        map['PIX'] = (map['PIX'] ?? 0.0) + total;
      } else if (forma.contains('DEBITO') || forma.contains('CREDITO') || forma.contains('CARTAO')) {
        map['DEBITO/CREDITO'] = (map['DEBITO/CREDITO'] ?? 0.0) + total;
      } else {
        map['OUTROS'] = (map['OUTROS'] ?? 0.0) + total;
      }
    }
    return map;
  }

  // Quantidade de vendas por forma de pagamento
  Map<String, int> get _qtdVendasPorFormaPagamento {
    final map = <String, int>{
      'DINHEIRO': 0,
      'PIX': 0,
      'DEBITO/CREDITO': 0,
      'OUTROS': 0,
    };

    for (final v in _vendasFiltradasPorPeriodo) {
      final forma = (v['forma_pagamento'] ?? 'OUTROS').toString().toUpperCase();
      if (forma.contains('DINHEIRO')) {
        map['DINHEIRO'] = (map['DINHEIRO'] ?? 0) + 1;
      } else if (forma.contains('PIX')) {
        map['PIX'] = (map['PIX'] ?? 0) + 1;
      } else if (forma.contains('DEBITO') || forma.contains('CREDITO') || forma.contains('CARTAO')) {
        map['DEBITO/CREDITO'] = (map['DEBITO/CREDITO'] ?? 0) + 1;
      } else {
        map['OUTROS'] = (map['OUTROS'] ?? 0) + 1;
      }
    }
    return map;
  }

  // Cancelar uma venda inteira e devolver todos os itens ao estoque
  Future<void> _cancelarVenda(Map<String, dynamic> venda) async {
    final vendaId = venda['id'];
    final valTotal = (venda['valor_total'] as num?)?.toDouble() ?? 0.0;
    final itens = (venda['itens_venda'] as List<dynamic>?) ?? [];

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Cancelar Venda?'),
          ],
        ),
        content: Text(
          'Deseja realmente cancelar esta venda de R\$ ${valTotal.toStringAsFixed(2)}?\n\n'
          'Todos os itens (${itens.length}) serão devolvidos ao estoque e a venda será excluída do histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sim, Cancelar Venda'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Devolve os itens ao estoque
      for (final it in itens) {
        final prodId = it['produto_id'];
        final qtdVendida = (it['quantidade_vendida'] as num?)?.toInt() ?? 0;
        if (prodId != null && qtdVendida > 0) {
          final prodRes = await supabase
              .from('produtos')
              .select('quantidade_estoque')
              .eq('id', prodId)
              .maybeSingle();

          final estoqueAtual = int.tryParse(prodRes?['quantidade_estoque']?.toString() ?? '0') ?? 0;
          await supabase.from('produtos').update({
            'quantidade_estoque': estoqueAtual + qtdVendida,
          }).eq('id', prodId);
        }
      }

      // 2. Remove itens de itens_venda
      await supabase.from('itens_venda').delete().eq('venda_id', vendaId);

      // 3. Remove a venda
      await supabase.from('vendas').delete().eq('id', vendaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venda cancelada com sucesso! O estoque foi restaurado.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _carregarDados();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao cancelar venda. Verifique sua conexão.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // Remover item de uma venda já feita (total ou parcial)
  Future<void> _removerItemVenda(Map<String, dynamic> venda, Map<String, dynamic> item) async {
    final vendaId = venda['id'];
    final itens = (venda['itens_venda'] as List<dynamic>?) ?? [];
    final prod = item['produtos'] as Map<String, dynamic>?;
    final nomeProd = prod?['nome'] ?? 'Produto';
    final qtdVendida = (item['quantidade_vendida'] as num?)?.toInt() ?? 0;
    final subtotalItem = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
    final precoUnit = qtdVendida > 0 ? (subtotalItem / qtdVendida) : 0.0;
    final prodId = item['produto_id'];
    final totalAtual = (venda['valor_total'] as num?)?.toDouble() ?? 0.0;

    int qtdARemover = qtdVendida > 1 ? 1 : qtdVendida;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valorAbater = precoUnit * qtdARemover;
          final novoTotal = (totalAtual - valorAbater).clamp(0.0, double.infinity);
          final restaraNaVenda = qtdVendida - qtdARemover;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.remove_circle_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Remover "$nomeProd"',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Este produto possui $qtdVendida unidades nesta venda.\nQuantas unidades deseja retirar?',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 16),

                // Seletor interativo de quantidade a retirar
                if (qtdVendida > 1) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.remove),
                        onPressed: qtdARemover > 1
                            ? () => setDialogState(() => qtdARemover--)
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          '$qtdARemover',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add),
                        onPressed: qtdARemover < qtdVendida
                            ? () => setDialogState(() => qtdARemover++)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () => setDialogState(() => qtdARemover = qtdVendida),
                      child: Text(
                        'Selecionar todos ($qtdVendida un.)',
                        style: const TextStyle(fontSize: 12, color: Colors.indigo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Resumo do impacto no estoque e na venda
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Devolver ao estoque:', style: TextStyle(fontSize: 12)),
                          Text(
                            '+$qtdARemover un.',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                      if (restaraNaVenda > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Permanecerá na venda:', style: TextStyle(fontSize: 12)),
                            Text(
                              '$restaraNaVenda un.',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Abater da venda:', style: TextStyle(fontSize: 12)),
                          Text(
                            '- R\$ ${valorAbater.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Novo total da venda:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          Text(
                            'R\$ ${novoTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  qtdARemover == qtdVendida && itens.length <= 1
                      ? 'Cancelar Venda'
                      : 'Confirmar Remoção ($qtdARemover un.)',
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmou != true) return;

    // Se vai remover todos os itens e é o único item da venda, cancela a venda inteira
    if (qtdARemover >= qtdVendida && itens.length <= 1) {
      await _cancelarVenda(venda);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Devolve a quantidade escolhida ao estoque do produto
      if (prodId != null && qtdARemover > 0) {
        final prodRes = await supabase
            .from('produtos')
            .select('quantidade_estoque')
            .eq('id', prodId)
            .maybeSingle();

        final estoqueAtual = int.tryParse(prodRes?['quantidade_estoque']?.toString() ?? '0') ?? 0;
        await supabase.from('produtos').update({
          'quantidade_estoque': estoqueAtual + qtdARemover,
        }).eq('id', prodId);
      }

      final valorAbater = precoUnit * qtdARemover;
      final novoTotalVenda = (totalAtual - valorAbater).clamp(0.0, double.infinity);

      // 2. Atualiza ou remove de itens_venda
      if (qtdARemover >= qtdVendida) {
        // Remove todo o item da venda
        await supabase
            .from('itens_venda')
            .delete()
            .eq('venda_id', vendaId)
            .eq('produto_id', prodId);
      } else {
        // Abate parcialmente
        final novaQtdVendida = qtdVendida - qtdARemover;
        final novoSubtotal = (subtotalItem - valorAbater).clamp(0.0, double.infinity);

        await supabase.from('itens_venda').update({
          'quantidade_vendida': novaQtdVendida,
          'subtotal': novoSubtotal,
        }).eq('venda_id', vendaId).eq('produto_id', prodId);
      }

      // 3. Atualiza o valor_total da venda
      await supabase.from('vendas').update({
        'valor_total': novoTotalVenda,
      }).eq('id', vendaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$qtdARemover un. de "$nomeProd" removida(s) e devolvida(s) ao estoque!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _carregarDados();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao atualizar item da venda. Verifique sua conexão.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _formatarDataHora(String? iso) {
    if (iso == null || iso.isEmpty) return 'Data não informada';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final ano = dt.year.toString();
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes/$ano às $hora:$min';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendasFiltradas = _vendasFiltradasPorPeriodo;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Histórico & Lucro', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Vendas'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Por Produto'),
            Tab(icon: Icon(Icons.restart_alt), text: 'Zerar Vendas'),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? _buildErrorView()
                : Column(
                  children: [
                    if (_tabController.index != 2) ...[
                      // Seletor de Período: Hoje | Semana | Mês | Geral
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('Hoje', PeriodoFiltro.hoje),
                              const SizedBox(width: 8),
                              _buildFilterChip('Esta Semana (7d)', PeriodoFiltro.semana),
                              const SizedBox(width: 8),
                              _buildFilterChip('Este Mês (30d)', PeriodoFiltro.mes),
                              const SizedBox(width: 8),
                              _buildFilterChip('Geral (Tudo)', PeriodoFiltro.geral),
                            ],
                          ),
                        ),
                      ),

                      // Cards de Faturamento e Lucro do Período Selecionado
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                titulo: 'Faturamento',
                                valor: 'R\$ ${_faturamentoPeriodo.toStringAsFixed(2)}',
                                subtitulo: '${vendasFiltradas.length} vendas',
                                cor: Colors.blue.shade700,
                                icone: Icons.point_of_sale,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                titulo: 'Lucro Líquido',
                                valor: 'R\$ ${_lucroPeriodo.toStringAsFixed(2)}',
                                subtitulo: _faturamentoPeriodo > 0
                                    ? 'Custo: R\$ ${_custoPeriodo.toStringAsFixed(2)} (${((_lucroPeriodo / _faturamentoPeriodo) * 100).toStringAsFixed(0)}% margem)'
                                    : 'Custo: R\$ 0,00',
                                cor: Colors.green.shade700,
                                icone: Icons.trending_up,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Card de Faturamento por Forma de Pagamento
                      _buildCardFormasPagamento(),
                    ],

                    // Conteúdo das Abas
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAbaVendas(vendasFiltradas),
                          _buildAbaRelatorioProdutos(vendasFiltradas),
                          _buildAbaZerarVendas(),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  // Chip de seleção de período
  Widget _buildFilterChip(String label, PeriodoFiltro filtro) {
    final selecionado = _filtroSelecionado == filtro;
    return ChoiceChip(
      label: Text(label),
      selected: selecionado,
      selectedColor: Colors.indigo,
      labelStyle: TextStyle(
        color: selecionado ? Colors.white : Colors.indigo.shade900,
        fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      backgroundColor: Colors.indigo.shade50,
      onSelected: (val) {
        if (val) {
          setState(() {
            _filtroSelecionado = filtro;
            _limiteVendasExibidas = 5; // Reseta paginação ao mudar filtro
          });
        }
      },
    );
  }

  // ABA 1: LISTA DE VENDAS PAGINADA DE 5 EM 5
  Widget _buildAbaVendas(List<Map<String, dynamic>> vendasFiltradas) {
    if (vendasFiltradas.isEmpty) {
      return RefreshIndicator(
        onRefresh: _carregarDados,
        child: ListView(
          children: const [
            SizedBox(height: 60),
            Center(
              child: Text(
                'Nenhuma venda registrada neste período.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    final vendasExibidas = vendasFiltradas.take(_limiteVendasExibidas).toList();
    final temMais = vendasFiltradas.length > _limiteVendasExibidas;

    return RefreshIndicator(
      onRefresh: _carregarDados,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: vendasExibidas.length + (temMais ? 1 : 0),
        itemBuilder: (context, index) {
          // Botão "Carregar mais 5 vendas" no final
          if (index == vendasExibidas.length) {
            final restantes = vendasFiltradas.length - _limiteVendasExibidas;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.indigo,
                    elevation: 1,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Colors.indigo),
                    ),
                  ),
                  icon: const Icon(Icons.expand_more),
                  label: Text('Carregar mais vendas (+${restantes > 5 ? 5 : restantes})'),
                  onPressed: () {
                    setState(() {
                      _limiteVendasExibidas += 5;
                    });
                  },
                ),
              ),
            );
          }

          final venda = vendasExibidas[index];
          final valTotal = (venda['valor_total'] as num?)?.toDouble() ?? 0.0;
          final dataStr = _formatarDataHora(venda['data_hora']?.toString());
          final itens = (venda['itens_venda'] as List<dynamic>?) ?? [];

          // Calcula lucro da venda específica
          double custoVenda = 0.0;
          for (final it in itens) {
            final q = (it['quantidade_vendida'] as num?)?.toInt() ?? 0;
            final p = it['produtos'] as Map<String, dynamic>?;
            final c = (p?['preco_custo'] as num?)?.toDouble() ?? 0.0;
            custoVenda += (c * q);
          }
          final lucroVenda = valTotal - custoVenda;

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade50,
                child: const Icon(Icons.check, color: Colors.green),
              ),
              title: Row(
                children: [
                  Text(
                    'R\$ ${valTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      'Lucro: R\$ ${lucroVenda.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Text(
                      dataStr,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 8),
                    _buildFormaBadge(venda['forma_pagamento']?.toString() ?? 'OUTROS'),
                  ],
                ),
              ),
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Itens Vendidos:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                      ),
                      const SizedBox(height: 6),
                      ...itens.map((it) {
                        final prod = it['produtos'] as Map<String, dynamic>?;
                        final nomeProd = prod?['nome'] ?? 'Item';
                        final qtd = it['quantidade_vendida'] ?? 1;
                        final subtotal = (it['subtotal'] as num?)?.toDouble() ?? 0.0;
                        final pCusto = (prod?['preco_custo'] as num?)?.toDouble() ?? 0.0;
                        final lucroItem = subtotal - (pCusto * qtd);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: Row(
                            children: [
                              Text(
                                '${qtd}x',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(nomeProd, style: const TextStyle(fontSize: 14)),
                              ),
                              Text(
                                'R\$ ${subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(+R\$ ${lucroItem.toStringAsFixed(2)})',
                                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                tooltip: 'Remover produto da venda',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _removerItemVenda(venda, it),
                              ),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: BorderSide(color: Colors.red.shade300),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: const Text('Cancelar Venda Inteira', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            onPressed: () => _cancelarVenda(venda),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ABA 2: RELATÓRIO CONSOLIDADO POR PRODUTO
  Widget _buildAbaRelatorioProdutos(List<Map<String, dynamic>> vendasFiltradas) {
    // Agrupa as vendas por produto
    final Map<String, Map<String, dynamic>> relatorioPorProduto = {};

    // 1. Inicializa com todos os produtos cadastrados (mostrando estoque)
    for (final p in _todosProdutos) {
      final id = p['id'].toString();
      final isExcluido = (p['codigo_barras'] ?? '').toString().startsWith('__EXCLUIDO__');
      relatorioPorProduto[id] = {
        'nome': p['nome'] ?? 'Sem nome',
        'estoque': int.tryParse(p['quantidade_estoque'].toString()) ?? 0,
        'preco_custo': (p['preco_custo'] as num?)?.toDouble() ?? 0.0,
        'preco_venda': (p['preco_venda'] as num?)?.toDouble() ?? 0.0,
        'qtd_vendida': 0,
        'faturamento': 0.0,
        'lucro': 0.0,
        'is_excluido': isExcluido,
      };
    }

    // 2. Acumula as vendas do período selecionado
    for (final v in vendasFiltradas) {
      final itens = (v['itens_venda'] as List<dynamic>?) ?? [];
      for (final it in itens) {
        final prodId = it['produto_id']?.toString();
        if (prodId == null) continue;

        final qtd = (it['quantidade_vendida'] as num?)?.toInt() ?? 0;
        final subtotal = (it['subtotal'] as num?)?.toDouble() ?? 0.0;

        if (!relatorioPorProduto.containsKey(prodId)) {
          final prod = it['produtos'] as Map<String, dynamic>?;
          final nomeProd = prod?['nome'] ?? 'Produto';
          final precoCusto = (prod?['preco_custo'] as num?)?.toDouble() ?? 0.0;
          final precoVenda = (prod?['preco_venda'] as num?)?.toDouble() ?? 0.0;
          relatorioPorProduto[prodId] = {
            'nome': nomeProd,
            'estoque': 0,
            'preco_custo': precoCusto,
            'preco_venda': precoVenda,
            'qtd_vendida': 0,
            'faturamento': 0.0,
            'lucro': 0.0,
            'is_excluido': true,
          };
        }

        final reg = relatorioPorProduto[prodId]!;
        final custoUnit = reg['preco_custo'] as double;
        final custoItem = custoUnit * qtd;

        reg['qtd_vendida'] = (reg['qtd_vendida'] as int) + qtd;
        reg['faturamento'] = (reg['faturamento'] as double) + subtotal;
        reg['lucro'] = (reg['lucro'] as double) + (subtotal - custoItem);
      }
    }

    // Ordena os produtos: primeiro os mais vendidos, depois por nome (ocultando excluídos com 0 vendas)
    final listaRelatorio = relatorioPorProduto.values
        .where((item) => !(item['is_excluido'] as bool) || (item['qtd_vendida'] as int) > 0)
        .toList()
      ..sort((a, b) {
        final compQtd = (b['qtd_vendida'] as int).compareTo(a['qtd_vendida'] as int);
        if (compQtd != 0) return compQtd;
        return (a['nome'] as String).compareTo(b['nome'] as String);
      });

    return RefreshIndicator(
      onRefresh: _carregarDados,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: listaRelatorio.length,
        itemBuilder: (context, index) {
          final item = listaRelatorio[index];
          final nome = item['nome'] as String;
          final estoque = item['estoque'] as int;
          final qtdVendida = item['qtd_vendida'] as int;
          final faturamento = item['faturamento'] as double;
          final lucro = item['lucro'] as double;
          final isExcluido = item['is_excluido'] == true;

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                nome,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isExcluido) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.orange.shade300),
                                ),
                                child: Text(
                                  'Excluído',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!isExcluido)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: estoque > 0 ? Colors.indigo.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$estoque un. em estoque',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: estoque > 0 ? Colors.indigo : Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Vendas no Período', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            '$qtdVendida un. vendidas',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: qtdVendida > 0 ? Colors.black87 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('Faturamento', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            'R\$ ${faturamento.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Lucro Gerado', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            'R\$ ${lucro.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: lucro > 0 ? Colors.green.shade700 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String titulo,
    required String valor,
    required String subtitulo,
    required Color cor,
    required IconData icone,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: cor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 18),
              const SizedBox(width: 6),
              Text(
                titulo,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cor),
          ),
          const SizedBox(height: 2),
          Text(
            subtitulo,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // Card do faturamento por forma de pagamento
  Widget _buildCardFormasPagamento() {
    final faturamentoFormas = _faturamentoPorFormaPagamento;
    final qtdFormas = _qtdVendasPorFormaPagamento;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline, size: 16, color: Colors.indigo),
              SizedBox(width: 6),
              Text(
                'Faturamento por Forma de Pagamento',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMiniFormaChip(
                'DINHEIRO',
                faturamentoFormas['DINHEIRO'] ?? 0.0,
                qtdFormas['DINHEIRO'] ?? 0,
                Colors.green.shade700,
                Colors.green.shade50,
              ),
              const SizedBox(width: 6),
              _buildMiniFormaChip(
                'PIX',
                faturamentoFormas['PIX'] ?? 0.0,
                qtdFormas['PIX'] ?? 0,
                Colors.teal.shade700,
                Colors.teal.shade50,
              ),
              const SizedBox(width: 6),
              _buildMiniFormaChip(
                'CARTÃO',
                faturamentoFormas['DEBITO/CREDITO'] ?? 0.0,
                qtdFormas['DEBITO/CREDITO'] ?? 0,
                Colors.blue.shade700,
                Colors.blue.shade50,
              ),
              const SizedBox(width: 6),
              _buildMiniFormaChip(
                'OUTROS',
                faturamentoFormas['OUTROS'] ?? 0.0,
                qtdFormas['OUTROS'] ?? 0,
                Colors.purple.shade700,
                Colors.purple.shade50,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFormaChip(String label, double valor, int qtd, Color cor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cor.withAlpha(50)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              'R\$ ${valor.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cor),
            ),
            Text(
              '$qtd vend.',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormaBadge(String forma) {
    final formaUpper = forma.toUpperCase();
    Color cor = Colors.purple;
    String label = forma;
    if (formaUpper.contains('DINHEIRO')) {
      cor = Colors.green.shade700;
      label = 'DINHEIRO';
    } else if (formaUpper.contains('PIX')) {
      cor = Colors.teal.shade700;
      label = 'PIX';
    } else if (formaUpper.contains('DEBITO') || formaUpper.contains('CREDITO') || formaUpper.contains('CARTAO')) {
      cor = Colors.blue.shade700;
      label = 'DÉB/CRÉD';
    } else {
      cor = Colors.purple.shade700;
      label = (formaUpper == 'PADRAO' || formaUpper.isEmpty) ? 'OUTROS' : forma;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: cor.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cor.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cor),
      ),
    );
  }

  Widget _buildErrorView() {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 64, color: Colors.orange.shade700),
                const SizedBox(height: 16),
                Text(
                  _erro!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar Novamente'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _carregarDados,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Executa a reinicialização de todas as vendas no banco Supabase
  Future<void> _executarZerarVendas() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    setState(() => _isZerando = true);
    try {
      final supabase = Supabase.instance.client;
      // 1. Limpa todos os itens de venda
      await supabase.from('itens_venda').delete().gte('quantidade_vendida', 0);
      // 2. Limpa todas as vendas
      await supabase.from('vendas').delete().gte('valor_total', 0);

      // Limpa o campo de texto e trava o botão
      _zerarConfirmacaoController.clear();
      _zerarBotaoHabilitado = false;

      // Recarrega os dados locais
      await _carregarDados();

      // Alterna para a primeira aba (Vendas)
      _tabController.animateTo(0);

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Todas as vendas foram zeradas com sucesso! Seus produtos e estoque continuam intactos.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Erro ao zerar histórico de vendas: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isZerando = false);
      }
    }
  }

  // ABA 3: REINICIAR VENDAS DO ZERO
  Widget _buildAbaZerarVendas() {
    if (_isZerando) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Zerando histórico de vendas...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _carregarDados,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card Principal de Aviso
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: Colors.red.shade200, width: 1.5),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.restart_alt, size: 42, color: Colors.red.shade700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Reiniciar Vendas do Zero',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Zere todo o histórico de vendas para iniciar um novo período ou limpar testes realizados no sistema.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // O QUE É MANTIDO (Verde)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'O QUE CONTINUA 100% INTACTO:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '• Todos os produtos cadastrados e seus nomes\n'
                    '• Preços de custo e preços de venda\n'
                    '• Quantidades em estoque físico atual\n'
                    '• Pastas e categorias organizadas',
                    style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // O QUE É APAGADO (Vermelho)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.red.shade700, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'O QUE SERÁ REINICIADO DO ZERO:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '• Todas as vendas já realizadas e cupons\n'
                    '• Todos os itens vendidos registrados\n'
                    '• Faturamento e lucro líquido (voltarão a R\$ 0,00)',
                    style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // BLOCO DE CONFIRMAÇÃO DE SEGURANÇA
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _zerarBotaoHabilitado ? Colors.green.shade400 : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Confirmação de Segurança',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Para confirmar que não foi um toque acidental, digite a palavra "cancelar" no campo abaixo para habilitar o botão:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _zerarConfirmacaoController,
                    decoration: InputDecoration(
                      hintText: 'Digite cancelar aqui',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      helperText: _zerarBotaoHabilitado
                          ? '✓ Palavra correta! Botão liberado abaixo.'
                          : 'Digite exatamente: cancelar',
                      helperStyle: TextStyle(
                        color: _zerarBotaoHabilitado ? Colors.green.shade800 : Colors.grey,
                        fontWeight: _zerarBotaoHabilitado ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onChanged: (val) {
                      final liberado = val.trim().toLowerCase() == 'cancelar';
                      if (liberado != _zerarBotaoHabilitado) {
                        setState(() => _zerarBotaoHabilitado = liberado);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.grey.shade500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.delete_sweep, size: 20),
                    label: const Text(
                      'Zerar Todas as Vendas Agora',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _zerarBotaoHabilitado ? _executarZerarVendas : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

