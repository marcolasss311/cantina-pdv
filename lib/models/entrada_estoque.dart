class EntradaEstoque {
  final String? id;
  final String produtoId;
  final int quantidadeComprada;
  final double custoTotalCompra;
  final DateTime? dataEntrada;

  EntradaEstoque({
    this.id,
    required this.produtoId,
    required this.quantidadeComprada,
    required this.custoTotalCompra,
    this.dataEntrada,
  });

  factory EntradaEstoque.fromJson(Map<String, dynamic> json) {
    return EntradaEstoque(
      id: json['id'] as String?,
      produtoId: json['produto_id'] as String,
      quantidadeComprada: json['quantidade_comprada'] as int,
      custoTotalCompra: (json['custo_total_compra'] as num).toDouble(),
      dataEntrada: json['data_entrada'] != null 
          ? DateTime.parse(json['data_entrada']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'produto_id': produtoId,
      'quantidade_comprada': quantidadeComprada,
      'custo_total_compra': custoTotalCompra,
      if (dataEntrada != null) 'data_entrada': dataEntrada!.toIso8601String(),
    };
  }
}
