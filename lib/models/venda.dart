class Venda {
  final String? id;
  final DateTime? dataHora;
  final double valorTotal;
  final String formaPagamento;

  Venda({
    this.id,
    this.dataHora,
    required this.valorTotal,
    required this.formaPagamento,
  });

  factory Venda.fromJson(Map<String, dynamic> json) {
    return Venda(
      id: json['id'] as String?,
      dataHora: json['data_hora'] != null ? DateTime.parse(json['data_hora']) : null,
      valorTotal: (json['valor_total'] as num).toDouble(),
      formaPagamento: json['forma_pagamento'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (dataHora != null) 'data_hora': dataHora!.toIso8601String(),
      'valor_total': valorTotal,
      'forma_pagamento': formaPagamento,
    };
  }
}
