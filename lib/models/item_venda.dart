class ItemVenda {
  final String vendaId;
  final String produtoId;
  final int quantidadeVendida;
  final double subtotal;

  ItemVenda({
    required this.vendaId,
    required this.produtoId,
    required this.quantidadeVendida,
    required this.subtotal,
  });

  factory ItemVenda.fromJson(Map<String, dynamic> json) {
    return ItemVenda(
      vendaId: json['venda_id'] as String,
      produtoId: json['produto_id'] as String,
      quantidadeVendida: json['quantidade_vendida'] as int,
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'venda_id': vendaId,
      'produto_id': produtoId,
      'quantidade_vendida': quantidadeVendida,
      'subtotal': subtotal,
    };
  }
}
