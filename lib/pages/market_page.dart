import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/product_service.dart';
import '../services/upload_service.dart';
import '../services/auth_service.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});
  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data
  List<dynamic> _products = [];
  List<dynamic> _myProducts = [];
  List<dynamic> _trendingProducts = [];
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';
  final List<Map<String, dynamic>> _cart = [];
  final Set<int> _likedProducts = {};

  // State
  bool _isLoading = true;
  bool _myShopLoading = false;
  String? _loadError;

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;

  final ProductService _productService = ProductService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 2 && _myProducts.isEmpty) {
        _loadMyProducts();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Data Loading ──────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _productService.getCategories(),
        _productService.getProducts(),
        _productService.getTrendingProducts(),
      ]);

      final cats = (results[0] as List).whereType<String>().toList();
      final productsMap = results[1] as Map<String, dynamic>;
      final products = productsMap['products'] as List? ?? [];
      final trending = results[2] as List;

      if (mounted) {
        setState(() {
          _categories = ['All', ...cats.where((c) => c != 'All')];
          _products = products;
          _trendingProducts = trending;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
        });
    }
  }

  Future<void> _loadMyProducts() async {
    final user = AuthService().currentUser;
    if (user == null) return;
    setState(() => _myShopLoading = true);
    try {
      final products = await _productService.getUserProducts(user['id']);
      if (mounted)
        setState(() {
          _myProducts = products;
          _myShopLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _myShopLoading = false);
    }
  }

  Future<void> _loadByCategory(String cat) async {
    setState(() => _isLoading = true);
    try {
      final resp = await _productService.getProducts(
        category: cat == 'All' ? null : cat,
      );
      final products = (resp['products'] as List?) ?? [];
      if (mounted)
        setState(() {
          _products = products;
          _isLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearch(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() => _isSearching = false);
      _loadData();
      return;
    }
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final resp = await _productService.getProducts(search: query);
        final products = (resp['products'] as List?) ?? [];
        if (mounted)
          setState(() {
            _products = products;
            _isSearching = false;
          });
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  // ─── Cart ──────────────────────────────────────────────────────────────────

  void _addToCart(Map<String, dynamic> product) {
    final alreadyIn = _cart.any((p) => p['id'] == product['id']);
    if (alreadyIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already in cart'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    setState(() => _cart.add(Map<String, dynamic>.from(product)));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['name']} added to cart'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  double get _cartTotal => _cart.fold(
    0.0,
    (sum, p) => sum + ((p['price'] as num?)?.toDouble() ?? 0),
  );

  // ─── Like ──────────────────────────────────────────────────────────────────

  Future<void> _toggleLike(Map<String, dynamic> product) async {
    final id = product['id'] as int;
    final liked = _likedProducts.contains(id);
    setState(() {
      if (liked) {
        _likedProducts.remove(id);
      } else {
        _likedProducts.add(id);
      }
    });
    try {
      await _productService.likeProduct(id);
    } catch (_) {
      setState(() {
        if (liked)
          _likedProducts.add(id);
        else
          _likedProducts.remove(id);
      });
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _fmtPrice(double price, String currency) {
    if (currency == 'ETH') return '${price.toStringAsFixed(3)} ETH';
    if (currency == 'USDT') return '${price.toStringAsFixed(2)} USDT';
    return '\$${price.toStringAsFixed(2)}';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: _buildSearchBar(),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.shopping_cart_outlined,
                  color: Colors.black,
                ),
                onPressed: _showCart,
              ),
              if (_cart.isNotEmpty)
                Positioned(right: 6, top: 6, child: _badge(_cart.length)),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(text: 'Explore'),
            Tab(text: 'Trending'),
            Tab(text: 'My Shop'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _buildError()
          : TabBarView(
              controller: _tabController,
              children: [_buildExplore(), _buildTrending(), _buildMyShop()],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateProduct,
        backgroundColor: Colors.deepPurple,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Sell', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _badge(int count) => Container(
    padding: const EdgeInsets.all(2),
    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
    child: Text(
      '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    ),
  );

  Widget _buildSearchBar() => TextField(
    controller: _searchCtrl,
    decoration: InputDecoration(
      hintText: 'Search products...',
      prefixIcon: _isSearching
          ? const SizedBox(
              width: 20,
              height: 20,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : const Icon(Icons.search, size: 20),
      suffixIcon: _searchCtrl.text.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                _searchCtrl.clear();
                _onSearch('');
                setState(() {});
              },
            )
          : null,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    ),
    onChanged: (v) {
      setState(() {});
      _onSearch(v);
    },
  );

  Widget _buildError() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          'Could not load products',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );

  // ─── Explore Tab ───────────────────────────────────────────────────────────

  Widget _buildExplore() {
    return Column(
      children: [
        // Category chips
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final sel = _selectedCategory == cat;
              return ChoiceChip(
                label: Text(cat),
                selected: sel,
                onSelected: (_) {
                  setState(() => _selectedCategory = cat);
                  _loadByCategory(cat);
                },
                selectedColor: Colors.deepPurple,
                labelStyle: TextStyle(
                  color: sel ? Colors.white : Colors.black87,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        Expanded(child: _buildProductGrid(_products)),
      ],
    );
  }

  // ─── Trending Tab ──────────────────────────────────────────────────────────

  Widget _buildTrending() {
    if (_trendingProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No trending products yet',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _trendingProducts.length,
        itemBuilder: (_, i) => _buildTrendingTile(_trendingProducts[i], i + 1),
      ),
    );
  }

  Widget _buildTrendingTile(dynamic p, int rank) {
    final pic = p['image_url']?.toString() ?? '';
    final liked = _likedProducts.contains(p['id']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: pic.isNotEmpty
                  ? Image.network(
                      pic,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imgPlaceholder(56),
                    )
                  : _imgPlaceholder(56),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: rank <= 3 ? Colors.amber : Colors.grey[400],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        title: Text(
          p['name']?.toString() ?? 'Product',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '@${p['seller']?['username'] ?? 'seller'}  •  ${p['category'] ?? ''}',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _fmtPrice(
                (p['price'] as num?)?.toDouble() ?? 0,
                p['currency']?.toString() ?? 'USD',
              ),
              style: const TextStyle(
                color: Colors.deepPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  size: 14,
                  color: liked ? Colors.red : Colors.grey,
                ),
                Text(
                  ' ${p['like_count'] ?? 0}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _showProductDetail(p),
      ),
    );
  }

  // ─── Product Grid ──────────────────────────────────────────────────────────

  Widget _buildProductGrid(List<dynamic> products) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_mall_directory, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No products found',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.68,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: products.length,
        itemBuilder: (_, i) => _buildProductCard(products[i]),
      ),
    );
  }

  Widget _buildProductCard(dynamic p) {
    final pic = p['image_url']?.toString() ?? '';
    final liked = _likedProducts.contains(p['id']);
    return GestureDetector(
      onTap: () => _showProductDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    child: pic.isNotEmpty
                        ? Image.network(
                            pic,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _imgPlaceholder(double.infinity),
                          )
                        : _imgPlaceholder(double.infinity),
                  ),
                  // Like button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _toggleLike(p as Map<String, dynamic>),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: liked ? Colors.red : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  // Category badge
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p['category']?.toString() ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['name']?.toString() ?? 'Product',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${p['seller']?['username'] ?? 'seller'}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _fmtPrice(
                              (p['price'] as num?)?.toDouble() ?? 0,
                              p['currency']?.toString() ?? 'USD',
                            ),
                            style: const TextStyle(
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 13,
                            ),
                            Text(
                              ' ${(p['rating'] as num?)?.toStringAsFixed(1) ?? '0'}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder(dynamic size) => Container(
    width: size is double ? size : null,
    height: size is double ? size : null,
    color: Colors.grey[200],
    child: const Center(child: Icon(Icons.image, color: Colors.grey, size: 36)),
  );

  // ─── Product Detail ────────────────────────────────────────────────────────

  void _showProductDetail(dynamic product) {
    final p = product as Map<String, dynamic>;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.97,
          minChildSize: 0.5,
          expand: false,
          builder: (_, sc) => SingleChildScrollView(
            controller: sc,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Image
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: (p['image_url']?.toString() ?? '').isNotEmpty
                        ? Image.network(
                            p['image_url'].toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey[200],
                              child: const Icon(
                                Icons.image,
                                size: 80,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.grey[200],
                            child: const Icon(
                              Icons.image,
                              size: 80,
                              color: Colors.grey,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category + rating row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              p['category']?.toString() ?? '',
                              style: const TextStyle(
                                color: Colors.deepPurple,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.star, color: Colors.amber[700], size: 18),
                          Text(
                            ' ${(p['rating'] as num?)?.toStringAsFixed(1) ?? '0'}  ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Icon(
                            Icons.favorite,
                            color: Colors.red[400],
                            size: 16,
                          ),
                          Text(' ${p['like_count'] ?? 0}'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        p['name']?.toString() ?? 'Product',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fmtPrice(
                          (p['price'] as num?)?.toDouble() ?? 0,
                          p['currency']?.toString() ?? 'USD',
                        ),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Seller
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.deepPurple,
                            child: Text(
                              (p['seller']?['username'] ?? 'S')[0]
                                  .toString()
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'by @${p['seller']?['username'] ?? 'seller'}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 12),
                          if ((p['stock'] as num?)?.toInt() != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: (p['stock'] as num).toInt() > 0
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (p['stock'] as num).toInt() > 0
                                    ? 'In Stock (${p['stock']})'
                                    : 'Out of Stock',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: (p['stock'] as num).toInt() > 0
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        p['description']?.toString().isNotEmpty == true
                            ? p['description'].toString()
                            : 'No description available.',
                        style: TextStyle(color: Colors.grey[600], height: 1.6),
                      ),
                      const SizedBox(height: 24),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _addToCart(p);
                              },
                              icon: const Icon(Icons.add_shopping_cart),
                              label: const Text('Add to Cart'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () async {
                              await _toggleLike(p);
                              setLocal(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _likedProducts.contains(p['id'])
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: _likedProducts.contains(p['id'])
                                    ? Colors.red
                                    : Colors.grey,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Share link copied!'),
                                    duration: Duration(seconds: 1),
                                  ),
                                ),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.share,
                                color: Colors.grey,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Cart ──────────────────────────────────────────────────────────────────

  void _showCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          minChildSize: 0.4,
          expand: false,
          builder: (_, sc) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      'Cart (${_cart.length})',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_cart.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          setState(() => _cart.clear());
                          setLocal(() {});
                        },
                        child: const Text(
                          'Clear All',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: _cart.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Your cart is empty',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: sc,
                        itemCount: _cart.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = _cart[i];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child:
                                  (item['image_url']?.toString() ?? '')
                                      .isNotEmpty
                                  ? Image.network(
                                      item['image_url'].toString(),
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 50,
                                        height: 50,
                                        color: Colors.grey[200],
                                      ),
                                    )
                                  : Container(
                                      width: 50,
                                      height: 50,
                                      color: Colors.grey[200],
                                      child: const Icon(Icons.image),
                                    ),
                            ),
                            title: Text(
                              item['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              _fmtPrice(
                                (item['price'] as num?)?.toDouble() ?? 0,
                                item['currency']?.toString() ?? 'USD',
                              ),
                              style: const TextStyle(color: Colors.deepPurple),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                              ),
                              onPressed: () {
                                setState(() => _cart.removeAt(i));
                                setLocal(() {});
                              },
                            ),
                          );
                        },
                      ),
              ),
              if (_cart.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '\$${_cartTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() => _cart.clear());
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Order placed successfully! 🎉'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Checkout',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── My Shop ───────────────────────────────────────────────────────────────

  Widget _buildMyShop() {
    final user = AuthService().currentUser;
    if (user == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.store, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Log in to manage your shop'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Log In'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMyProducts,
      child: CustomScrollView(
        slivers: [
          // Shop stats header
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.deepPurple, Colors.purple],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      (user['username'] ?? 'U')[0].toString().toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['full_name']?.toString() ?? 'Seller',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '@${user['username']}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        '${_myProducts.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Products',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Add product button
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _showCreateProduct,
                icon: const Icon(Icons.add),
                label: const Text('List a New Product'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  side: const BorderSide(color: Colors.deepPurple),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          // My products grid
          if (_myShopLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (_myProducts.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.store_mall_directory_outlined,
                        size: 56,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No products listed yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap "List a New Product" to get started',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildMyProductCard(_myProducts[i]),
                  childCount: _myProducts.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildMyProductCard(dynamic p) {
    final pic = p['image_url']?.toString() ?? '';
    return GestureDetector(
      onTap: () => _showProductDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: pic.isNotEmpty
                    ? Image.network(
                        pic,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _imgPlaceholder(double.infinity),
                      )
                    : _imgPlaceholder(double.infinity),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fmtPrice(
                        (p['price'] as num?)?.toDouble() ?? 0,
                        p['currency']?.toString() ?? 'USD',
                      ),
                      style: const TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility,
                          size: 12,
                          color: Colors.grey,
                        ),
                        Text(
                          ' ${p['view_count'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.favorite,
                          size: 12,
                          color: Colors.grey,
                        ),
                        Text(
                          ' ${p['like_count'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Edit/Delete actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[100]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _showEditProduct(p),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 30),
                      ),
                      child: const Text('Edit', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  Container(width: 1, height: 20, color: Colors.grey[200]),
                  Expanded(
                    child: TextButton(
                      onPressed: () => _confirmDelete(p['id']),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 30),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Create Product ────────────────────────────────────────────────────────

  void _showCreateProduct() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final imageCtrl = TextEditingController();
    File? localImageFile;
    String selCat = _categories.firstWhere(
      (c) => c != 'All',
      orElse: () => 'NFTs',
    );
    String selCurrency = 'USD';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => DraggableScrollableSheet(
          initialChildSize: 0.92,
          maxChildSize: 0.97,
          minChildSize: 0.5,
          expand: false,
          builder: (_, sc) => SingleChildScrollView(
            controller: sc,
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'List a Product',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                // ── Image Picker ──────────────────────────────────────────
                GestureDetector(
                  onTap: () =>
                      _pickImage(ctx, imageCtrl, localImageFile, (file, url) {
                        setLocal(() {
                          localImageFile = file;
                          imageCtrl.text = url;
                        });
                      }),
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey[300]!, width: 1.5),
                    ),
                    child: localImageFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: kIsWeb
                                ? Image.network(
                                    imageCtrl.text,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _imgPlaceholderWidget(),
                                  )
                                : Image.file(
                                    localImageFile!,
                                    fit: BoxFit.cover,
                                  ),
                          )
                        : imageCtrl.text.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              imageCtrl.text,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _imgPlaceholderWidget(),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withValues(
                                    alpha: 0.1,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add_photo_alternate,
                                  size: 36,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Add Product Image',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Gallery • Camera • URL',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                if (imageCtrl.text.isNotEmpty || localImageFile != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => setLocal(() {
                      localImageFile = null;
                      imageCtrl.clear();
                    }),
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    label: const Text(
                      'Remove image',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _field(nameCtrl, 'Product Name *', Icons.label),
                const SizedBox(height: 12),
                _field(descCtrl, 'Description', Icons.description, maxLines: 3),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        priceCtrl,
                        'Price *',
                        Icons.attach_money,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selCurrency,
                          items: ['USD', 'ETH', 'USDT']
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => selCurrency = v!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Category',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories
                      .where((c) => c != 'All')
                      .map(
                        (cat) => ChoiceChip(
                          label: Text(
                            cat,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: selCat == cat,
                          onSelected: (_) => setLocal(() => selCat = cat),
                          selectedColor: Colors.deepPurple,
                          labelStyle: TextStyle(
                            color: selCat == cat
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty ||
                                priceCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Name and price are required'),
                                ),
                              );
                              return;
                            }
                            final price = double.tryParse(
                              priceCtrl.text.trim(),
                            );
                            if (price == null || price <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Enter a valid price'),
                                ),
                              );
                              return;
                            }
                            setLocal(() => isSaving = true);
                            try {
                              // Upload local file if selected, otherwise use URL
                              String finalImageUrl = imageCtrl.text.trim();
                              if (localImageFile != null && !kIsWeb) {
                                final uploaded = await UploadService()
                                    .uploadImage(localImageFile!);
                                if (uploaded != null && uploaded.isNotEmpty) {
                                  finalImageUrl = uploaded;
                                }
                              }
                              if (finalImageUrl.isEmpty) {
                                finalImageUrl =
                                    'https://picsum.photos/400/400?random=${DateTime.now().millisecondsSinceEpoch}';
                              }
                              await _productService.createProduct(
                                name: nameCtrl.text.trim(),
                                description: descCtrl.text.trim(),
                                price: price,
                                currency: selCurrency,
                                category: selCat,
                                imageUrl: finalImageUrl,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _loadData();
                              await _loadMyProducts();
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Product listed! 🎉'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                            } catch (e) {
                              setLocal(() => isSaving = false);
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'List Product',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Image Picker ─────────────────────────────────────────────────────────

  /// Shows a bottom sheet with 3 options: Gallery, Camera, URL
  void _pickImage(
    BuildContext ctx,
    TextEditingController urlCtrl,
    File? currentFile,
    void Function(File? file, String url) onPicked,
  ) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Product Image',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // Gallery
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library, color: Colors.green),
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Pick any image from your device'),
              onTap: () async {
                Navigator.pop(sheet);
                await _pickFromGallery(urlCtrl, onPicked);
              },
            ),
            // Camera / File Browser — adapts per platform
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  (Platform.isAndroid || Platform.isIOS)
                      ? Icons.camera_alt
                      : Icons.folder_open,
                  color: Colors.blue,
                ),
              ),
              title: Text(
                (Platform.isAndroid || Platform.isIOS)
                    ? 'Take a Photo'
                    : 'Browse Files',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                (Platform.isAndroid || Platform.isIOS)
                    ? 'Use your camera to capture'
                    : 'Browse image files on your computer',
              ),
              onTap: () async {
                Navigator.pop(sheet);
                await _pickFromCamera(urlCtrl, onPicked);
              },
            ),
            // Enter URL
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.link, color: Colors.deepPurple),
              ),
              title: const Text(
                'Enter Image URL',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Paste a link to an online image'),
              onTap: () async {
                Navigator.pop(sheet);
                _enterImageUrl(ctx, urlCtrl, onPicked);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromGallery(
    TextEditingController urlCtrl,
    void Function(File? file, String url) onPicked,
  ) async {
    try {
      if (kIsWeb) {
        // Web: use file_picker with bytes
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final f = result.files.first;
          if (f.bytes != null) {
            onPicked(
              null,
              'data:image/${f.extension};base64,${_bytesToBase64(f.bytes!)}',
            );
          }
        }
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop: image_picker doesn't support Windows — use file_picker
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null &&
            result.files.isNotEmpty &&
            result.files.first.path != null) {
          final path = result.files.first.path!;
          onPicked(File(path), path);
        }
      } else {
        // Mobile: image_picker
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1200,
          maxHeight: 1200,
        );
        if (picked != null) onPicked(File(picked.path), picked.path);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gallery error: $e')));
    }
  }

  Future<void> _pickFromCamera(
    TextEditingController urlCtrl,
    void Function(File? file, String url) onPicked,
  ) async {
    try {
      if (Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS ||
          kIsWeb) {
        // Desktop/Web: no camera — open file picker as fallback
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Camera unavailable on desktop — opening gallery instead',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null &&
            result.files.isNotEmpty &&
            result.files.first.path != null) {
          final path = result.files.first.path!;
          onPicked(File(path), path);
        }
      } else {
        // Mobile: image_picker camera
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 1200,
          maxHeight: 1200,
        );
        if (picked != null) onPicked(File(picked.path), picked.path);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera error: $e')));
    }
  }

  void _enterImageUrl(
    BuildContext ctx,
    TextEditingController urlCtrl,
    void Function(File? file, String url) onPicked,
  ) {
    final ctrl = TextEditingController(text: urlCtrl.text);
    showDialog(
      context: ctx,
      builder: (dlg) => AlertDialog(
        title: const Text('Image URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/image.jpg',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final url = ctrl.text.trim();
              if (url.isNotEmpty) onPicked(null, url);
              Navigator.pop(dlg);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Use URL'),
          ),
        ],
      ),
    );
  }

  String _bytesToBase64(List<int> bytes) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      buffer.write(chars[(b0 >> 2) & 0x3F]);
      buffer.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      buffer.write(
        i + 1 < bytes.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=',
      );
      buffer.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
    }
    return buffer.toString();
  }

  Widget _imgPlaceholderWidget() => Container(
    color: Colors.grey[200],
    child: const Center(
      child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
    ),
  );

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );

  // ─── Edit Product ──────────────────────────────────────────────────────────

  void _showEditProduct(dynamic product) {
    final p = product as Map<String, dynamic>;
    final nameCtrl = TextEditingController(text: p['name']?.toString() ?? '');
    final descCtrl = TextEditingController(
      text: p['description']?.toString() ?? '',
    );
    final priceCtrl = TextEditingController(
      text: '${(p['price'] as num?)?.toDouble() ?? 0}',
    );
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Product',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _field(nameCtrl, 'Product Name', Icons.label),
              const SizedBox(height: 12),
              _field(descCtrl, 'Description', Icons.description, maxLines: 3),
              const SizedBox(height: 12),
              _field(
                priceCtrl,
                'Price',
                Icons.attach_money,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setLocal(() => isSaving = true);
                          try {
                            await _productService.updateProduct(p['id'], {
                              'name': nameCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                              'price':
                                  double.tryParse(priceCtrl.text) ?? p['price'],
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _loadMyProducts();
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Product updated!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                          } catch (e) {
                            setLocal(() => isSaving = false);
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Delete Product ────────────────────────────────────────────────────────

  void _confirmDelete(int productId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text(
          'Are you sure you want to remove this product from your shop?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _productService.deleteProduct(productId);
                await _loadMyProducts();
                await _loadData();
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Product deleted'),
                      backgroundColor: Colors.orange,
                    ),
                  );
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
