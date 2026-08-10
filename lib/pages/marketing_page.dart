import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ad_service.dart';
import '../services/upload_service.dart';

class MarketingPage extends StatefulWidget {
  const MarketingPage({super.key});
  @override
  State<MarketingPage> createState() => _MarketingPageState();
}

class _MarketingPageState extends State<MarketingPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final AdService _adService = AdService();

  List<dynamic> _myAds = [];
  bool _isLoading = true;
  int _totalImpressions = 0;
  int _totalClicks = 0;
  double _totalSpent = 0;
  double _totalBudget = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final ads = await _adService.getMyAds();
      int imp = 0, clk = 0;
      double spent = 0, budget = 0;
      for (final a in ads) {
        imp += (a['impression_count'] as int? ?? 0);
        clk += (a['click_count'] as int? ?? 0);
        spent += (a['spent_amount'] as num? ?? 0).toDouble();
        budget += (a['budget'] as num? ?? 0).toDouble();
      }
      if (mounted)
        setState(() {
          _myAds = ads;
          _totalImpressions = imp;
          _totalClicks = clk;
          _totalSpent = spent;
          _totalBudget = budget;
          _isLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Ad Manager',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          isScrollable: true,
          tabs: const [
            Tab(
              icon: Icon(Icons.dashboard_outlined, size: 18),
              text: 'Dashboard',
            ),
            Tab(icon: Icon(Icons.campaign_outlined, size: 18), text: 'My Ads'),
            Tab(
              icon: Icon(Icons.bar_chart_rounded, size: 18),
              text: 'Analytics',
            ),
            Tab(icon: Icon(Icons.explore_outlined, size: 18), text: 'Explore'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _dashboardTab(),
                _myAdsTab(),
                _analyticsTab(),
                _exploreTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAdWizard,
        backgroundColor: Colors.deepPurple,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Create Ad',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ─── Dashboard ────────────────────────────────────────────────────────────

  Widget _dashboardTab() {
    final activeAds = _myAds.where((a) => a['status'] == 'active').length;
    final pausedAds = _myAds.where((a) => a['status'] == 'paused').length;
    final ctr = _totalImpressions > 0
        ? (_totalClicks / _totalImpressions * 100)
        : 0.0;
    final budgetUsed = _totalBudget > 0 ? (_totalSpent / _totalBudget) : 0.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF4A148C),
                    Color(0xFF7B1FA2),
                    Color(0xFFEC407A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.campaign, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Ad Manager',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _heroStat(
                        _fmt(_totalImpressions),
                        'Impressions',
                        Icons.visibility,
                      ),
                      _vDiv(),
                      _heroStat(_fmt(_totalClicks), 'Clicks', Icons.touch_app),
                      _vDiv(),
                      _heroStat(
                        '\$${_totalSpent.toStringAsFixed(0)}',
                        'Spent',
                        Icons.attach_money,
                      ),
                      _vDiv(),
                      _heroStat(
                        '$activeAds',
                        'Active',
                        Icons.play_circle_outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Budget bar
                  if (_totalBudget > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Budget Used',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          '\$${_totalSpent.toStringAsFixed(2)} / \$${_totalBudget.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: budgetUsed.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(
                          Colors.greenAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    'CTR',
                    '${ctr.toStringAsFixed(2)}%',
                    Icons.percent,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    'Active',
                    '$activeAds',
                    Icons.play_arrow,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    'Paused',
                    '$pausedAds',
                    Icons.pause,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard(
                    'Total',
                    '${_myAds.length}',
                    Icons.campaign,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Quick actions
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _quickAction(
                  Icons.add_circle,
                  'New Ad',
                  Colors.deepPurple,
                  _createAdWizard,
                ),
                const SizedBox(width: 10),
                _quickAction(
                  Icons.bar_chart,
                  'Analytics',
                  Colors.blue,
                  () => _tabCtrl.animateTo(2),
                ),
                const SizedBox(width: 10),
                _quickAction(
                  Icons.list_alt,
                  'My Ads',
                  Colors.green,
                  () => _tabCtrl.animateTo(1),
                ),
                const SizedBox(width: 10),
                _quickAction(
                  Icons.explore,
                  'Explore',
                  Colors.orange,
                  () => _tabCtrl.animateTo(3),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Recent ads preview
            if (_myAds.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Campaigns',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () => _tabCtrl.animateTo(1),
                    child: const Text('See All'),
                  ),
                ],
              ),
              ..._myAds.take(3).map((a) => _adTile(a)),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String val, String label, IconData icon) => Column(
    children: [
      Icon(icon, color: Colors.white70, size: 18),
      const SizedBox(height: 4),
      Text(
        val,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
    ],
  );

  Widget _vDiv() => Container(width: 1, height: 44, color: Colors.white24);

  Widget _statCard(String label, String val, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              val,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 10),
            ),
          ],
        ),
      );

  Widget _quickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ─── My Ads Tab ──────────────────────────────────────────────────────────

  Widget _myAdsTab() {
    if (_myAds.isEmpty)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No campaigns yet',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first ad to start reaching your audience',
              style: TextStyle(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createAdWizard,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Create Campaign'),
            ),
          ],
        ),
      );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _myAds.length,
        itemBuilder: (_, i) => _adCard(_myAds[i]),
      ),
    );
  }

  Widget _adCard(Map<String, dynamic> ad) {
    final status = ad['status']?.toString() ?? 'active';
    final statusColor = status == 'active'
        ? Colors.green
        : status == 'paused'
        ? Colors.orange
        : Colors.grey;
    final imp = ad['impression_count'] as int? ?? 0;
    final clk = ad['click_count'] as int? ?? 0;
    final budget = (ad['budget'] as num?)?.toDouble() ?? 0;
    final spent = (ad['spent_amount'] as num?)?.toDouble() ?? 0;
    final ctr = imp > 0 ? (clk / imp * 100) : 0.0;
    final mediaUrl = ad['media_url']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Media preview
          if (mediaUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: Image.network(
                mediaUrl,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 80,
                  color: Colors.grey[200],
                  child: const Center(
                    child: Icon(Icons.image, color: Colors.grey, size: 40),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ad['title']?.toString() ?? 'Campaign',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((ad['description']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    ad['description'].toString(),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if ((ad['target_url']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.link,
                        size: 13,
                        color: Colors.deepPurple,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ad['target_url'].toString(),
                          style: const TextStyle(
                            color: Colors.deepPurple,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Stats row
                Row(
                  children: [
                    _adStat(Icons.visibility, _fmt(imp), 'Views', Colors.blue),
                    const SizedBox(width: 14),
                    _adStat(Icons.touch_app, _fmt(clk), 'Clicks', Colors.green),
                    const SizedBox(width: 14),
                    _adStat(
                      Icons.percent,
                      '${ctr.toStringAsFixed(1)}%',
                      'CTR',
                      Colors.orange,
                    ),
                    const SizedBox(width: 14),
                    _adStat(
                      Icons.attach_money,
                      '\$${spent.toStringAsFixed(0)}',
                      'Spent',
                      Colors.red,
                    ),
                  ],
                ),
                // Budget bar
                if (budget > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Budget: \$${budget.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                      Text(
                        '${((spent / budget) * 100).clamp(0, 100).toStringAsFixed(0)}% used',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (spent / budget).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(
                        (spent / budget) > 0.8 ? Colors.red : Colors.deepPurple,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _toggleStatus(ad),
                        icon: Icon(
                          status == 'active' ? Icons.pause : Icons.play_arrow,
                          size: 16,
                        ),
                        label: Text(status == 'active' ? 'Pause' : 'Resume'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: status == 'active'
                              ? Colors.orange
                              : Colors.green,
                          side: BorderSide(
                            color: status == 'active'
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editAd(ad),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple,
                          side: const BorderSide(color: Colors.deepPurple),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _confirmDelete(ad['id']),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adTile(Map<String, dynamic> ad) {
    final status = ad['status']?.toString() ?? 'active';
    final statusColor = status == 'active' ? Colors.green : Colors.orange;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.campaign, color: Colors.deepPurple, size: 20),
      ),
      title: Text(
        ad['title']?.toString() ?? '',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${_fmt(ad['impression_count'] as int? ?? 0)} views  •  ${_fmt(ad['click_count'] as int? ?? 0)} clicks',
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          status.toUpperCase(),
          style: TextStyle(
            color: statusColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _adStat(IconData icon, String val, String label, Color color) =>
      Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                val,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 9)),
        ],
      );

  // ─── Analytics Tab ────────────────────────────────────────────────────────

  Widget _analyticsTab() {
    final ctr = _totalImpressions > 0
        ? (_totalClicks / _totalImpressions * 100)
        : 0.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overall Performance',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _perf('Impressions', _fmt(_totalImpressions), Colors.blue),
                    _perf('Clicks', _fmt(_totalClicks), Colors.green),
                    _perf('CTR', '${ctr.toStringAsFixed(2)}%', Colors.amber),
                    _perf(
                      'Spent',
                      '\$${_totalSpent.toStringAsFixed(2)}',
                      Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_myAds.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bar_chart, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'Run your first ad to see analytics',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Per Campaign',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            ..._myAds.map((ad) => _analyticsCard(ad)),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _perf(String label, String val, Color color) => Column(
    children: [
      Text(
        val,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ],
  );

  Widget _analyticsCard(Map<String, dynamic> ad) {
    final imp = ad['impression_count'] as int? ?? 0;
    final clk = ad['click_count'] as int? ?? 0;
    final ctr = imp > 0 ? (clk / imp * 100) : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ad['title']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 10),
            _progressBar('Impressions', imp, 10000, Colors.blue),
            const SizedBox(height: 8),
            _progressBar('Clicks', clk, 1000, Colors.green),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Click-Through Rate',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                Text(
                  '${ctr.toStringAsFixed(2)}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Budget Allocated',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                Text(
                  '\$${(ad['budget'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(String label, int val, int max, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          Text(
            '${_fmt(val)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: (val / max).clamp(0.0, 1.0),
          minHeight: 7,
          backgroundColor: color.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ],
  );

  // ─── Explore Tab ──────────────────────────────────────────────────────────

  Widget _exploreTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Ad formats
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ad Formats',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          ...[
            _AdFormat(
              'Video Ad',
              'Short-form videos that play in the feed',
              Icons.videocam,
              Colors.red,
              'Best for: Brand awareness, product demos',
              '15–60 sec',
            ),
            _AdFormat(
              'Image Ad',
              'Static images shown between posts',
              Icons.image,
              Colors.blue,
              'Best for: Product showcase, promotions',
              '1080×1080 px',
            ),
            _AdFormat(
              'Banner Ad',
              'Horizontal banners across the app',
              Icons.view_carousel,
              Colors.green,
              'Best for: App installs, website traffic',
              '728×90 px',
            ),
            _AdFormat(
              'Story Ad',
              'Full-screen immersive ads',
              Icons.phone_android,
              Colors.purple,
              'Best for: Engagement, app downloads',
              '9:16 ratio',
            ),
          ].map((f) => _adFormatCard(f)),
          const SizedBox(height: 20),
          // Tips
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Advertising Tips',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          ...[
            (
              '🎯',
              'Target your audience',
              'Use interests, age, and gender targeting to reach the right people',
            ),
            (
              '📊',
              'Set a daily budget',
              'Start small with \$5–10/day and scale what works',
            ),
            (
              '🖼️',
              'Use eye-catching visuals',
              'Bright colors and clear CTAs get 40% more clicks',
            ),
            (
              '⏰',
              'Schedule your ads',
              'Run ads when your audience is most active',
            ),
            (
              '🔄',
              'A/B test creatives',
              'Test 2–3 different versions to find the best performer',
            ),
            (
              '📈',
              'Track your CTR',
              'A good CTR is 2–5%. Optimize if below 1%',
            ),
          ].map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(t.$1, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            t.$3,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _adFormatCard(_AdFormat f) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: f.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(f.icon, color: f.color, size: 24),
      ),
      title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.desc, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            f.bestFor,
            style: TextStyle(
              color: f.color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: f.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              f.spec,
              style: TextStyle(
                color: f.color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      onTap: _createAdWizard,
    ),
  );

  // ─── Create Ad Wizard ─────────────────────────────────────────────────────

  void _createAdWizard() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    final ageMinCtrl = TextEditingController(text: '18');
    final ageMaxCtrl = TextEditingController(text: '45');
    File? mediaFile;
    String mediaUrl = '';
    String adType = 'image';
    String genderTarget = 'All';
    List<String> interests = [];
    int currentStep = 0;
    bool isSaving = false;

    final allInterests = [
      'Music',
      'Gaming',
      'Travel',
      'Food',
      'Fitness',
      'Fashion',
      'Tech',
      'Art',
      'Sports',
      'Education',
      'Business',
      'Dating',
    ];

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
          builder: (_, sc) => Column(
            children: [
              // Handle + title + steps
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Create Campaign',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Step ${currentStep + 1} of 4',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Step indicator
                    Row(
                      children: List.generate(
                        4,
                        (i) => Expanded(
                          child: Container(
                            height: 4,
                            margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                            decoration: BoxDecoration(
                              color: i <= currentStep
                                  ? Colors.deepPurple
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              // Step content
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _stepContent(
                    currentStep,
                    titleCtrl,
                    descCtrl,
                    urlCtrl,
                    budgetCtrl,
                    ageMinCtrl,
                    ageMaxCtrl,
                    adType,
                    genderTarget,
                    interests,
                    allInterests,
                    mediaFile,
                    mediaUrl,
                    onTypeChange: (v) => setLocal(() => adType = v),
                    onGenderChange: (v) => setLocal(() => genderTarget = v),
                    onInterestToggle: (v) => setLocal(
                      () => interests.contains(v)
                          ? interests.remove(v)
                          : interests.add(v),
                    ),
                    onMediaPicked: (f, u) => setLocal(() {
                      mediaFile = f;
                      mediaUrl = u;
                    }),
                  ),
                ),
              ),
              // Navigation buttons
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Row(
                  children: [
                    if (currentStep > 0) ...[
                      OutlinedButton(
                        onPressed: () => setLocal(() => currentStep--),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (currentStep < 3) {
                                  // Validate step
                                  if (currentStep == 0 &&
                                      titleCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Enter a campaign title'),
                                      ),
                                    );
                                    return;
                                  }
                                  setLocal(() => currentStep++);
                                } else {
                                  // Submit
                                  if (titleCtrl.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Enter a campaign title'),
                                      ),
                                    );
                                    return;
                                  }
                                  setLocal(() => isSaving = true);
                                  try {
                                    String finalUrl = mediaUrl;
                                    if (mediaFile != null && !kIsWeb) {
                                      final up = await UploadService()
                                          .uploadImage(mediaFile!)
                                          .timeout(
                                            const Duration(seconds: 30),
                                            onTimeout: () => null,
                                          );
                                      if (up != null && up.isNotEmpty)
                                        finalUrl = up;
                                    }
                                    await _adService
                                        .createAd(
                                          title: titleCtrl.text.trim(),
                                          description: descCtrl.text.trim(),
                                          targetUrl: urlCtrl.text.trim(),
                                          budget:
                                              double.tryParse(
                                                budgetCtrl.text,
                                              ) ??
                                              0,
                                          mediaType: adType,
                                          mediaUrl: finalUrl,
                                          targetInterests: interests.join(','),
                                          targetGender: genderTarget,
                                          targetAge:
                                              '${ageMinCtrl.text}-${ageMaxCtrl.text}',
                                        )
                                        .timeout(const Duration(seconds: 15));
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    await _load();
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Campaign launched! 🚀',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                  } catch (e) {
                                    setLocal(() => isSaving = false);
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed: ${e.toString().replaceAll('Exception:', '').trim()}',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentStep == 3
                              ? Colors.green
                              : Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                            : Text(
                                currentStep == 3
                                    ? '🚀 Launch Campaign'
                                    : 'Continue →',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepContent(
    int step,
    TextEditingController title,
    TextEditingController desc,
    TextEditingController url,
    TextEditingController budget,
    TextEditingController ageMin,
    TextEditingController ageMax,
    String adType,
    String gender,
    List<String> interests,
    List<String> allInterests,
    File? mediaFile,
    String mediaUrl, {
    required Function(String) onTypeChange,
    required Function(String) onGenderChange,
    required Function(String) onInterestToggle,
    required Function(File?, String) onMediaPicked,
  }) {
    switch (step) {
      case 0:
        return _step1(title, desc, url, adType, onTypeChange);
      case 1:
        return _step2(mediaFile, mediaUrl, adType, onMediaPicked);
      case 2:
        return _step3(
          gender,
          interests,
          allInterests,
          ageMin,
          ageMax,
          onGenderChange,
          onInterestToggle,
        );
      case 3:
        return _step4(budget, title, desc, adType, mediaUrl, mediaFile);
      default:
        return const SizedBox();
    }
  }

  Widget _step1(
    TextEditingController title,
    TextEditingController desc,
    TextEditingController url,
    String adType,
    Function(String) onTypeChange,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '📋 Campaign Details',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      _field(title, 'Campaign Title *', Icons.title, required: true),
      const SizedBox(height: 12),
      _field(
        desc,
        'Description',
        Icons.description,
        maxLines: 3,
        hint: 'What are you promoting?',
      ),
      const SizedBox(height: 12),
      _field(
        url,
        'Destination URL',
        Icons.link,
        hint: 'https://yourwebsite.com',
      ),
      const SizedBox(height: 16),
      const Text('Ad Format', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            [
              {'type': 'image', 'icon': '🖼️', 'label': 'Image'},
              {'type': 'video', 'icon': '🎬', 'label': 'Video'},
              {'type': 'banner', 'icon': '📣', 'label': 'Banner'},
              {'type': 'story', 'icon': '📱', 'label': 'Story'},
            ].map((t) {
              final sel = adType == t['type'];
              return GestureDetector(
                onTap: () => onTypeChange(t['type'] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: sel
                        ? Colors.deepPurple.withValues(alpha: 0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel ? Colors.deepPurple : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t['icon'] as String,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t['label'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: sel ? Colors.deepPurple : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget _step2(
    File? mediaFile,
    String mediaUrl,
    String adType,
    Function(File?, String) onPicked,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '🎨 Creative Assets',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Text(
        'Upload your ad creative or enter a URL',
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
      const SizedBox(height: 16),
      // Preview
      GestureDetector(
        onTap: () => _pickAdMedia(mediaFile, onPicked),
        child: Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.grey[300]!,
              style: BorderStyle.solid,
            ),
          ),
          child: mediaFile != null && !kIsWeb
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(mediaFile, fit: BoxFit.cover),
                )
              : mediaUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    mediaUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.upload_rounded,
                        size: 36,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Tap to upload creative',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Image, Video, or Banner',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
        ),
      ),
      if (mediaFile != null || mediaUrl.isNotEmpty) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => onPicked(null, ''),
          icon: const Icon(Icons.close, size: 16, color: Colors.red),
          label: const Text(
            'Remove',
            style: TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ],
      const SizedBox(height: 12),
      const Center(
        child: Text('─── or ───', style: TextStyle(color: Colors.grey)),
      ),
      const SizedBox(height: 12),
      _urlField(mediaUrl, onPicked),
      const SizedBox(height: 24),
    ],
  );

  Widget _step3(
    String gender,
    List<String> interests,
    List<String> allInterests,
    TextEditingController ageMin,
    TextEditingController ageMax,
    Function(String) onGender,
    Function(String) onInterest,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '🎯 Target Audience',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Text(
        'Define who sees your ad',
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
      const SizedBox(height: 16),
      const Text('Gender', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(
        children: ['All', 'Male', 'Female', 'Other'].map((g) {
          final sel = gender == g;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onGender(g),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel
                        ? Colors.deepPurple.withValues(alpha: 0.12)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? Colors.deepPurple : Colors.grey[300]!,
                    ),
                  ),
                  child: Text(
                    g,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: sel ? Colors.deepPurple : Colors.black87,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      const Text('Age Range', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _field(
              ageMin,
              'Min Age',
              Icons.person_outline,
              keyboardType: TextInputType.number,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('to'),
          ),
          Expanded(
            child: _field(
              ageMax,
              'Max Age',
              Icons.person_outline,
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Text(
            'Interests',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          if (interests.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${interests.length}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: allInterests.map((i) {
          final sel = interests.contains(i);
          return FilterChip(
            label: Text(
              i,
              style: TextStyle(
                fontSize: 12,
                color: sel ? Colors.white : Colors.black87,
              ),
            ),
            selected: sel,
            onSelected: (_) => onInterest(i),
            selectedColor: Colors.deepPurple,
            backgroundColor: Colors.grey[100],
            checkmarkColor: Colors.white,
          );
        }).toList(),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget _step4(
    TextEditingController budget,
    TextEditingController title,
    TextEditingController desc,
    String adType,
    String mediaUrl,
    File? mediaFile,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '💰 Budget & Review',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      // Budget input
      _field(
        budget,
        'Total Budget (USD) *',
        Icons.attach_money,
        keyboardType: TextInputType.number,
        hint: 'e.g. 50',
      ),
      const SizedBox(height: 8),
      // Quick budget chips
      Wrap(
        spacing: 8,
        children: [5, 10, 25, 50, 100, 250]
            .map(
              (b) => ActionChip(
                label: Text('\$$b'),
                backgroundColor: Colors.deepPurple.withValues(alpha: 0.07),
                onPressed: () => budget.text = '$b',
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 20),
      // Review summary
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              children: const [
                Icon(Icons.preview, color: Colors.deepPurple, size: 18),
                SizedBox(width: 8),
                Text(
                  'Campaign Summary',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 16),
            _summaryRow('Title', title.text.isNotEmpty ? title.text : '—'),
            _summaryRow('Format', adType.toUpperCase()),
            _summaryRow(
              'Creative',
              mediaFile != null
                  ? 'Uploaded'
                  : mediaUrl.isNotEmpty
                  ? 'URL set'
                  : 'None',
            ),
            _summaryRow(
              'Budget',
              budget.text.isNotEmpty ? '\$${budget.text}' : 'Not set',
            ),
            const Divider(height: 16),
            Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.orange, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your ad will be reviewed and go live within 30 minutes',
                    style: TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
  );

  Widget _summaryRow(String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            val,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  void _pickAdMedia(File? current, Function(File?, String) onPicked) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('From Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  if (kIsWeb ||
                      Platform.isWindows ||
                      Platform.isMacOS ||
                      Platform.isLinux) {
                    final r = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                      allowMultiple: false,
                    );
                    if (r != null &&
                        r.files.isNotEmpty &&
                        r.files.first.path != null) {
                      onPicked(File(r.files.first.path!), '');
                    }
                  } else {
                    final x = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 85,
                    );
                    if (x != null) onPicked(File(x.path), '');
                  }
                } catch (_) {}
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.deepPurple),
              title: const Text('Enter URL'),
              onTap: () async {
                Navigator.pop(ctx);
                final ctrl = TextEditingController();
                final url = await showDialog<String>(
                  context: context,
                  builder: (dlg) => AlertDialog(
                    title: const Text('Media URL'),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dlg),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(dlg, ctrl.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Use'),
                      ),
                    ],
                  ),
                );
                if (url != null && url.isNotEmpty) onPicked(null, url);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _urlField(String current, Function(File?, String) onPicked) {
    final ctrl = TextEditingController(text: current);
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: 'Media URL (optional)',
        hintText: 'https://example.com/ad.jpg',
        prefixIcon: const Icon(Icons.link),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.check, color: Colors.green),
          onPressed: () {
            if (ctrl.text.isNotEmpty) onPicked(null, ctrl.text.trim());
          },
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
    bool required = false,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label + (required ? ' *' : ''),
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      alignLabelWithHint: maxLines > 1,
    ),
  );

  // ─── Ad actions ───────────────────────────────────────────────────────────

  Future<void> _toggleStatus(Map<String, dynamic> ad) async {
    final n = ad['status'] == 'active' ? 'paused' : 'active';
    try {
      await _adService.updateAd(ad['id'], status: n);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _editAd(Map<String, dynamic> ad) {
    final titleCtrl = TextEditingController(
      text: ad['title']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: ad['description']?.toString() ?? '',
    );
    final budgetCtrl = TextEditingController(
      text: '${(ad['budget'] as num?)?.toDouble() ?? 0}',
    );
    bool saving = false;
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
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Campaign',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              _field(titleCtrl, 'Title', Icons.title),
              const SizedBox(height: 10),
              _field(descCtrl, 'Description', Icons.description, maxLines: 3),
              const SizedBox(height: 10),
              _field(
                budgetCtrl,
                'Budget (USD)',
                Icons.attach_money,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setLocal(() => saving = true);
                          try {
                            await _adService.updateAd(
                              ad['id'],
                              budget: double.tryParse(budgetCtrl.text),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Campaign updated!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                          } catch (e) {
                            setLocal(() => saving = false);
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
                  child: saving
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int adId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Campaign'),
        content: const Text(
          'This will permanently delete this ad campaign and all its data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _adService.deleteAd(adId);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Campaign deleted'),
            backgroundColor: Colors.orange,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

// ─── Ad Format model ─────────────────────────────────────────────────────────

class _AdFormat {
  final String name, desc, bestFor, spec;
  final IconData icon;
  final Color color;
  const _AdFormat(
    this.name,
    this.desc,
    this.icon,
    this.color,
    this.bestFor,
    this.spec,
  );
}
