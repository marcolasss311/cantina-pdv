import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PastasService {
  static const String _keyPastas = 'cantina_pastas_lista';
  static const String _keyProdutoPastaMap = 'cantina_produto_pasta_map';

  // Pastas padrão sugeridas na primeira inicialização
  static const List<String> _pastasPadrao = [
    'Hambúrguer',
    'Prato Executivo',
    'Salgados',
    'Bebidas',
  ];

  /// Obtém a lista de todas as pastas cadastradas
  static Future<List<String>> getPastas() async {
    final prefs = await SharedPreferences.getInstance();
    final salvas = prefs.getStringList(_keyPastas);
    if (salvas == null) {
      // Primeira inicialização: salva e retorna as pastas padrão
      await prefs.setStringList(_keyPastas, _pastasPadrao);
      return List<String>.from(_pastasPadrao);
    }
    return salvas;
  }

  /// Cria uma nova pasta
  static Future<bool> criarPasta(String nome) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final pastas = await getPastas();

    final existe = pastas.any((p) => p.toLowerCase() == nomeLimpo.toLowerCase());
    if (existe) return false;

    pastas.add(nomeLimpo);
    await prefs.setStringList(_keyPastas, pastas);
    return true;
  }

  /// Renomeia uma pasta e atualiza os produtos vinculados a ela
  static Future<void> renomearPasta(String nomeAntigo, String nomeNovo) async {
    final novo = nomeNovo.trim();
    if (novo.isEmpty || nomeAntigo == novo) return;

    final prefs = await SharedPreferences.getInstance();
    final pastas = await getPastas();

    final idx = pastas.indexOf(nomeAntigo);
    if (idx != -1) {
      pastas[idx] = novo;
      await prefs.setStringList(_keyPastas, pastas);
    }

    // Atualiza mapa de produtos
    final map = await getProdutoPastaMap();
    bool mudou = false;
    map.forEach((prodId, pasta) {
      if (pasta == nomeAntigo) {
        map[prodId] = novo;
        mudou = true;
      }
    });

    if (mudou) {
      await prefs.setString(_keyProdutoPastaMap, jsonEncode(map));
    }
  }

  /// Exclui uma pasta e desvincula os produtos pertencentes a ela
  static Future<void> excluirPasta(String nome) async {
    final prefs = await SharedPreferences.getInstance();
    final pastas = await getPastas();

    pastas.remove(nome);
    await prefs.setStringList(_keyPastas, pastas);

    // Remove do mapa de produtos
    final map = await getProdutoPastaMap();
    final chavesRemover = <String>[];
    map.forEach((prodId, pasta) {
      if (pasta == nome) {
        chavesRemover.add(prodId);
      }
    });

    for (final k in chavesRemover) {
      map.remove(k);
    }

    await prefs.setString(_keyProdutoPastaMap, jsonEncode(map));
  }

  /// Obtém o mapa produto_id -> nome_da_pasta
  static Future<Map<String, String>> getProdutoPastaMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyProdutoPastaMap);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Obtém a pasta de um produto específico
  static Future<String?> getPastaDoProduto(String produtoId) async {
    final map = await getProdutoPastaMap();
    return map[produtoId];
  }

  /// Vincula um produto a uma pasta (ou desvincula se pastaNome for nulo/vazio)
  static Future<void> setProdutoPasta(String produtoId, String? pastaNome) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getProdutoPastaMap();

    if (pastaNome == null || pastaNome.trim().isEmpty) {
      map.remove(produtoId);
    } else {
      map[produtoId] = pastaNome.trim();
    }

    await prefs.setString(_keyProdutoPastaMap, jsonEncode(map));
  }

  /// Vincula múltiplos produtos a uma pasta de uma só vez
  static Future<void> setProdutosPasta(List<String> produtoIds, String pastaNome) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getProdutoPastaMap();

    for (final id in produtoIds) {
      map[id] = pastaNome.trim();
    }

    await prefs.setString(_keyProdutoPastaMap, jsonEncode(map));
  }

  /// Remove múltiplos produtos de uma pasta
  static Future<void> removerProdutosDaPasta(List<String> produtoIds) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await getProdutoPastaMap();

    for (final id in produtoIds) {
      map.remove(id);
    }

    await prefs.setString(_keyProdutoPastaMap, jsonEncode(map));
  }
}
