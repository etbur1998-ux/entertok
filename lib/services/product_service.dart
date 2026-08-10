import 'package:flutter/foundation.dart';
import 'api_client.dart';

class ProductService {
  final ApiClient _api = ApiClient();

  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  /// Resolve image_url on every product
  static List<dynamic> _resolve(dynamic raw) {
    final list = raw is List ? raw : <dynamic>[];
    return list.map((p) {
      if (p is! Map) return p;
      final m = Map<String, dynamic>.from(p);
      m['image_url'] = ApiClient.resolveUrl(m['image_url']?.toString());
      m['media_url'] = ApiClient.resolveUrl(m['media_url']?.toString());
      if (m['seller'] is Map) {
        final s = Map<String, dynamic>.from(m['seller'] as Map);
        s['profile_image'] = ApiClient.resolveUrl(
          s['profile_image']?.toString(),
        );
        m['seller'] = s;
      }
      return m;
    }).toList();
  }

  Future<Map<String, dynamic>> getProducts({
    String? category,
    String? search,
    int limit = 40,
    int offset = 0,
  }) async {
    final q = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (category != null && category != 'All') q['category'] = category;
    if (search != null && search.isNotEmpty) q['search'] = search;

    final response = await _api.get('/products', queryParams: q);
    final products = _resolve(response['products']);
    return {
      'products': products,
      'total': response['total'] ?? products.length,
    };
  }

  Future<List<dynamic>> getTrendingProducts() async {
    try {
      final response = await _api.get('/products/trending');
      if (response is List) return _resolve(response);
      if (response is Map && response['products'] != null)
        return _resolve(response['products']);
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> getProduct(int id) async {
    final r = await _api.get('/products/$id');
    return Map<String, dynamic>.from(r as Map);
  }

  Future<List<dynamic>> getCategories() async {
    try {
      final response = await _api.get('/products/categories');
      if (response is Map && response['categories'] is List) {
        return (response['categories'] as List).whereType<String>().toList();
      }
    } catch (_) {}
    return ['NFTs', 'Gaming', 'Music', 'Art', 'Virtual', 'Fashion'];
  }

  Future<List<dynamic>> getUserProducts(dynamic userId) async {
    try {
      final response = await _api.get('/products/user/$userId');
      if (response is List) return _resolve(response);
      if (response is Map && response['products'] is List)
        return _resolve(response['products']);
    } catch (e) {
      debugPrint('getUserProducts error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> createProduct({
    required String name,
    String? description,
    required double price,
    String currency = 'USD',
    required String category,
    String? imageUrl,
    String? mediaUrl,
    int stock = 1,
  }) async {
    final result = await _api.post(
      '/products',
      body: {
        'name': name,
        'description': description ?? '',
        'price': price,
        'currency': currency,
        'category': category,
        'image_url': imageUrl ?? '',
        'media_url': mediaUrl ?? '',
        'stock': stock,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateProduct(
    int id,
    Map<String, dynamic> updates,
  ) async {
    return Map<String, dynamic>.from(
      await _api.put('/products/$id', body: updates) as Map,
    );
  }

  Future<void> deleteProduct(int id) async {
    await _api.delete('/products/$id');
  }

  Future<Map<String, dynamic>> likeProduct(int id) async {
    return Map<String, dynamic>.from(
      await _api.post('/products/$id/like') as Map,
    );
  }
}
