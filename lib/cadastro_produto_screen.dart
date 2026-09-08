import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/pastas_service.dart';

class CadastroProdutoScreen extends StatefulWidget {
  final String? initialBarcode;

  const CadastroProdutoScreen({super.key, this.initialBarcode});

  @override
  State<CadastroProdutoScreen> createState() => _CadastroProdutoScreenState();
}

class _CadastroProdutoScreenState extends State<CadastroProdutoScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto para o formulário
  late final TextEditingController _codigoBarrasController;
  final _nomeController = TextEditingController();
  final _precoCustoController = TextEditingController();
  final _precoVendaController = TextEditingController();
  final _estoqueController = TextEditingController(text: '0');

  // Controladores de estado
  bool _isScanning = false;
  bool _isManualBarcode = false;
  bool _isLoading = false;
  bool _semCodigoBarras = false;
  List<String> _pastasDisponiveis = [];
  String? _pastaSelecionada;
  final MobileScannerController _cameraController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _codigoBarrasController = TextEditingController(text: widget.initialBarcode ?? '');
    if (widget.initialBarcode == null || widget.initialBarcode!.isEmpty) {
      _isManualBarcode = false;
    }
    _carregarPastas();
  }

  Future<void> _carregarPastas() async {
    final p = await PastasService.getPastas();
    if (mounted) {
      setState(() {
        _pastasDisponiveis = p;
      });
    }
  }

  Future<void> _dialogoNovaPasta() async {
    final controller = TextEditingController();
    final criada = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_outlined, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Criar Nova Pasta'),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ex: Hambúrguer, Prato Executivo...',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
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
            onPressed: () {
              final nome = controller.text.trim();
              if (nome.isNotEmpty) {
                Navigator.pop(ctx, nome);
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (criada != null && criada.isNotEmpty) {
      await PastasService.criarPasta(criada);
      await _carregarPastas();
      setState(() {
        _pastaSelecionada = criada;
      });
    }
  }

  @override
  void dispose() {
    _codigoBarrasController.dispose();
    _nomeController.dispose();
    _precoCustoController.dispose();
    _precoVendaController.dispose();
    _estoqueController.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  void _abrirScanner() {
    setState(() {
      _isScanning = true;
    });
  }

  void _fecharScanner() {
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _salvarProduto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final String codigoFinal;
    if (_semCodigoBarras) {
      // Gera código interno único para satisfazer constraint NOT NULL e UNIQUE
      codigoFinal = 'SB-${DateTime.now().millisecondsSinceEpoch}';
    } else {
      codigoFinal = _codigoBarrasController.text.trim();
    }

    final nome = _nomeController.text.trim();
    final precoCusto = double.parse(_precoCustoController.text.replaceAll(',', '.').trim());
    final precoVenda = double.parse(_precoVendaController.text.replaceAll(',', '.').trim());
    final estoque = int.tryParse(_estoqueController.text.trim()) ?? 0;

    try {
      final supabase = Supabase.instance.client;

      // 1. Verifica se já existe um produto com o mesmo código de barras (se não for sem barras)
      if (!_semCodigoBarras) {
        final existente = await supabase
            .from('produtos')
            .select('id, nome')
            .eq('codigo_barras', codigoFinal)
            .maybeSingle();

        if (existente != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Já existe um produto com este código: ${existente['nome']}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      // 2. Insere o novo produto
      final novoProduto = {
        'codigo_barras': codigoFinal,
        'nome': nome,
        'preco_custo': precoCusto,
        'preco_venda': precoVenda,
        'quantidade_estoque': estoque,
      };

      final res = await supabase.from('produtos').insert(novoProduto).select('id').single();

      // 3. Vincula à pasta selecionada, se houver
      if (_pastaSelecionada != null && _pastaSelecionada!.isNotEmpty) {
        final idCriado = res['id']?.toString();
        if (idCriado != null) {
          await PastasService.setProdutoPasta(idCriado, _pastaSelecionada);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Produto "$nome" cadastrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Volta para a tela inicial atualizando a lista
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Não foi possível conectar ao servidor. Verifique sua internet.';
        final erro = e.toString().toLowerCase();
        if (erro.contains('duplicate') || erro.contains('unique')) {
          msg = 'Este código de barras já está cadastrado para outro produto.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastrar Novo Produto'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        bottom: true,
        child: _isScanning ? _buildScanner() : _buildForm(),
      ),
    );
  }

  // WIDGET DO SCANNER DE CÓDIGO DE BARRAS
  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _cameraController,
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              final String? code = barcodes.first.rawValue;
              if (code != null && code.isNotEmpty) {
                setState(() {
                  _codigoBarrasController.text = code;
                  _isScanning = false;
                });
              }
            }
          },
        ),
        Positioned(
          bottom: 50 + MediaQuery.of(context).viewPadding.bottom,
          left: 0,
          right: 0,
          child: Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Cancelar Leitura'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _fecharScanner,
            ),
          ),
        )
      ],
    );
  }

  // WIDGET DO FORMULÁRIO DE CADASTRO
  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            // Opção: Produto sem código de barras (lanches, refeições, salgados)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _semCodigoBarras ? Colors.indigo.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _semCodigoBarras ? Colors.indigo.shade200 : Colors.grey.shade300,
                ),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                title: const Text(
                  'Produto sem código de barras',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Para salgados, lanches, pratos executivos, etc.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _semCodigoBarras,
                activeThumbColor: Colors.indigo,
                onChanged: (val) {
                  setState(() {
                    _semCodigoBarras = val;
                    if (val) {
                      _codigoBarrasController.text = 'Sem código de barras';
                    } else {
                      _codigoBarrasController.clear();
                    }
                  });
                },
              ),
            ),

            if (!_semCodigoBarras) ...[
              // Linha com Código de Barras e Botão do Scanner
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codigoBarrasController,
                      readOnly: !_isManualBarcode,
                      decoration: InputDecoration(
                        labelText: 'Código de Barras',
                        hintText: 'Escaneie ou digite',
                        border: const OutlineInputBorder(),
                        filled: !_isManualBarcode,
                        fillColor: _isManualBarcode ? Colors.white : Colors.grey.shade200,
                        prefixIcon: const Icon(Icons.qr_code),
                      ),
                      validator: (value) {
                        if (_semCodigoBarras) return null;
                        if (value == null || value.trim().isEmpty) {
                          return 'Escaneie ou digite o código.';
                        }
                        return null;
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
                    tooltip: 'Abrir Scanner',
                    onPressed: _abrirScanner,
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isManualBarcode = !_isManualBarcode;
                    });
                  },
                  icon: Icon(_isManualBarcode ? Icons.lock : Icons.edit, size: 16),
                  label: Text(
                    _isManualBarcode
                        ? 'Bloquear edição manual'
                        : 'Digitar código manualmente',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),

            // Nome do Produto
            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome do Produto',
                hintText: 'Ex: X-Salada, Strogonoff...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.fastfood),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Informe o nome do produto' : null,
            ),
            const SizedBox(height: 16),

            // Seleção de Pasta / Categoria na Venda
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _pastaSelecionada,
                    decoration: const InputDecoration(
                      labelText: 'Pasta / Categoria na Venda',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder_open, color: Colors.indigo),
                      helperText: 'Ex: Hambúrguer, Prato Executivo...',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'Nenhuma pasta (Sem categoria)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ..._pastasDisponiveis.map(
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
                      setState(() => _pastaSelecionada = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.create_new_folder),
                  tooltip: 'Nova Pasta',
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                  ),
                  onPressed: _dialogoNovaPasta,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Preço de Custo e Preço de Venda
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _precoCustoController,
                    decoration: const InputDecoration(
                      labelText: 'Custo (R\$)',
                      hintText: '0,00',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.monetization_on_outlined),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Informe o custo';
                      if (double.tryParse(value.replaceAll(',', '.')) == null) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _precoVendaController,
                    decoration: const InputDecoration(
                      labelText: 'Venda (R\$)',
                      hintText: '0,00',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Informe o preço';
                      if (double.tryParse(value.replaceAll(',', '.')) == null) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quantidade inicial em estoque
            TextFormField(
              controller: _estoqueController,
              decoration: const InputDecoration(
                labelText: 'Estoque Inicial (quantidade)',
                hintText: '0',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory_2_outlined),
                helperText: 'Quantas unidades você já possui hoje',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Informe o estoque inicial';
                if (int.tryParse(value.trim()) == null) return 'Digite um número inteiro';
                return null;
              },
            ),
            const SizedBox(height: 32),

            // Botão Salvar
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _salvarProduto,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isLoading ? 'Salvando...' : 'Salvar Produto',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
