class Produto {
  final String? id;
  final String codigoBarras;
  final String nome;
  final double precoVenda;
  final double precoCusto;
  final int quantidadeEstoque;

  Produto({
    this.id,
    required this.codigoBarras,
    required this.nome,
    required this.precoVenda,
    required this.precoCusto,
    this.quantidadeEstoque = 0,
  });

  factory Produto.fromJson(Map<String, dynamic> json) {
    return Produto(
      id: json['id'] as String?,
      codigoBarras: json['codigo_barras'] as String,
      nome: json['nome'] as String,
      precoVenda: (json['preco_venda'] as num).toDouble(),
      precoCusto: (json['preco_custo'] as num).toDouble(),
      quantidadeEstoque: json['quantidade_estoque'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'codigo_barras': codigoBarras,
      'nome': nome,
      'preco_venda': precoVenda,
      'preco_custo': precoCusto,
      'quantidade_estoque': quantidadeEstoque,
    };
  }
}
