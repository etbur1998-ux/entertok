import 'package:flutter/material.dart';
import '../services/wallet_service.dart';
import '../services/boost_service.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final WalletService _ws = WalletService();
  final BoostService _bs = BoostService();

  // Session-based wallet data
  Map<String, dynamic> _wallet = {};
  Map<String, dynamic> _stats = {};
  List<dynamic> _txAll = [];
  List<dynamic> _txSent = [];
  List<dynamic> _txReceived = [];

  // Boost data
  Map<String, dynamic> _boostStats = {};
  List<dynamic> _myCampaigns = [];
  List<dynamic> _boostedUsers = [];
  bool _boostLoading = false;

  bool _isLoading = true;
  bool _balanceVisible = true;
  String _selectedFilter = 'All';

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
      final results = await Future.wait([
        _ws.getWallet(),
        _ws.getStats(),
        _ws.getTransactions(),
      ]);
      final sent = (results[2] as List)
          .where((t) => (t['amount'] as num) < 0)
          .toList();
      final recv = (results[2] as List)
          .where((t) => (t['amount'] as num) > 0)
          .toList();
      if (mounted) {
        setState(() {
          _wallet = results[0] as Map<String, dynamic>;
          _stats = results[1] as Map<String, dynamic>;
          _txAll = results[2] as List;
          _txSent = sent;
          _txReceived = recv;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
    _loadBoost();
  }

  Future<void> _loadBoost() async {
    setState(() => _boostLoading = true);
    try {
      final results = await Future.wait([
        _bs.getBoostStats(),
        _bs.getMyBoosts(),
        _bs.getActiveBoostedUsers(),
      ]);
      if (mounted) {
        setState(() {
          _boostStats = results[0] as Map<String, dynamic>;
          _myCampaigns = results[1] as List;
          _boostedUsers = results[2] as List;
          _boostLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _boostLoading = false);
    }
  }

  double get _balance => (_wallet['balance'] as num?)?.toDouble() ?? 0.0;
  String get _address =>
      _wallet['wallet_address']?.toString() ?? 'ETBP00000000';
  String get _currency => _wallet['currency']?.toString() ?? 'USD';

  String _fmt(double n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : n.toStringAsFixed(2);

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'My Wallet',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showSettings,
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Transactions'),
            Tab(text: 'Analytics'),
            Tab(icon: Icon(Icons.rocket_launch, size: 16), text: 'Boost'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _overviewTab(user),
                _transactionsTab(),
                _analyticsTab(),
                _boostTab(),
              ],
            ),
    );
  }

  // ─── Overview ─────────────────────────────────────────────────────────────

  Widget _overviewTab(Map<String, dynamic>? user) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Main card
            _balanceCard(user),
            const SizedBox(height: 16),
            // Action row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _actionBtn(Icons.add, 'Top Up', Colors.green, _showTopUp),
                  const SizedBox(width: 12),
                  _actionBtn(Icons.send, 'Send', Colors.deepPurple, _showSend),
                  const SizedBox(width: 12),
                  _actionBtn(
                    Icons.download,
                    'Withdraw',
                    Colors.orange,
                    _showWithdraw,
                  ),
                  const SizedBox(width: 12),
                  _actionBtn(
                    Icons.qr_code_scanner,
                    'Scan',
                    Colors.blue,
                    _showReceive,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Stats grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _statsGrid(),
            ),
            const SizedBox(height: 20),
            // Recent transactions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'Recent',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _tabCtrl.animateTo(1),
                    child: const Text('See All'),
                  ),
                ],
              ),
            ),
            if (_txAll.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No transactions yet',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._txAll.take(5).map((t) => _txTile(t)),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(Map<String, dynamic>? user) {
    final pic = user?['profile_image']?.toString() ?? '';
    final name =
        user?['full_name']?.toString() ??
        user?['username']?.toString() ??
        'User';
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFFEC407A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white24,
                backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
                child: pic.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'ETBurPay Wallet',
                    style: TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _balanceVisible = !_balanceVisible),
                child: Icon(
                  _balanceVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white60,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Total Balance',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 6),
          _balanceVisible
              ? Text(
                  '\$$_balance ${_currency}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : const Text(
                  '••••••',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          const SizedBox(height: 18),
          // Wallet address chip
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copied: $_address'),
                duration: const Duration(seconds: 1),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _address,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, color: Colors.white60, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _statsGrid() {
    final recv = (_stats['total_received'] as num?)?.toDouble() ?? 0;
    final sent = (_stats['total_sent'] as num?)?.toDouble() ?? 0;
    final fees = (_stats['total_fees'] as num?)?.toDouble() ?? 0;
    final txCount = _txAll.length;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        _statCard(
          'Total Received',
          '\$${_fmt(recv)}',
          Icons.arrow_downward,
          Colors.green,
        ),
        _statCard(
          'Total Sent',
          '\$${_fmt(sent)}',
          Icons.arrow_upward,
          Colors.orange,
        ),
        _statCard('Fees Paid', '\$${_fmt(fees)}', Icons.toll, Colors.red),
        _statCard('Transactions', '$txCount', Icons.receipt_long, Colors.blue),
      ],
    );
  }

  Widget _statCard(String label, String val, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    val,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ─── Transactions Tab ─────────────────────────────────────────────────────

  Widget _transactionsTab() {
    final filters = ['All', 'Received', 'Sent', 'Pending'];
    List<dynamic> list;
    switch (_selectedFilter) {
      case 'Received':
        list = _txReceived;
        break;
      case 'Sent':
        list = _txSent;
        break;
      case 'Pending':
        list = _txAll.where((t) => t['status'] == 'pending').toList();
        break;
      default:
        list = _txAll;
    }

    return Column(
      children: [
        // Filter chips
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: filters.map((f) {
              final sel = _selectedFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    f,
                    style: TextStyle(
                      fontSize: 12,
                      color: sel ? Colors.white : Colors.black87,
                    ),
                  ),
                  selected: sel,
                  selectedColor: Colors.deepPurple,
                  onSelected: (_) => setState(() => _selectedFilter = f),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No $_selectedFilter transactions',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _txTile(list[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _txTile(dynamic tx) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final isPositive = amount > 0;
    final type = tx['type']?.toString() ?? '';
    final status = tx['status']?.toString() ?? 'completed';
    final desc = tx['description']?.toString() ?? '';
    final ref = tx['reference_id']?.toString() ?? '';
    final isPending = status == 'pending';

    IconData icon;
    Color color;
    String typeLabel;
    switch (type) {
      case 'deposit':
        icon = Icons.add_circle;
        color = Colors.green;
        typeLabel = 'Top-up';
        break;
      case 'withdrawal':
        icon = Icons.download_rounded;
        color = Colors.orange;
        typeLabel = 'Withdraw';
        break;
      case 'tip':
        icon = Icons.favorite;
        color = Colors.pink;
        typeLabel = 'Tip';
        break;
      default:
        icon = isPositive ? Icons.arrow_downward : Icons.arrow_upward;
        color = isPositive ? Colors.green : Colors.deepPurple;
        typeLabel = isPositive ? 'Received' : 'Sent';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  typeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (ref.isNotEmpty)
                  Text(
                    ref,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : ''}\$${amount.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isPositive ? Colors.green : Colors.deepPurple,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isPending
                      ? Colors.amber.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isPending ? Colors.amber[700] : Colors.green,
                  ),
                ),
              ),
              if ((tx['fee'] as num?)?.toDouble() != null &&
                  (tx['fee'] as num).toDouble() > 0)
                Text(
                  'fee: \$${(tx['fee'] as num).toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.grey[400], fontSize: 9),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Analytics Tab ────────────────────────────────────────────────────────

  Widget _analyticsTab() {
    final recv = (_stats['total_received'] as num?)?.toDouble() ?? 0;
    final sent = (_stats['total_sent'] as num?)?.toDouble() ?? 0;
    final total = recv + sent;
    final recvPct = total > 0 ? recv / total : 0.5;
    final sentPct = total > 0 ? sent / total : 0.5;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance overview
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Balance',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$$_balance $_currency',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Flow bars
          const Text(
            'Money Flow',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _flowBar('Received', recv, recvPct.toDouble(), Colors.green),
          const SizedBox(height: 10),
          _flowBar('Sent', sent, sentPct.toDouble(), Colors.deepPurple),
          const SizedBox(height: 20),
          // Monthly breakdown
          const Text(
            'Transaction Types',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ..._buildTypeBreakdown(),
          const SizedBox(height: 20),
          // Quick tips
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.deepPurple.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.deepPurple, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Tips',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...[
                  '💜 Share your wallet address to receive payments',
                  '🔒 Keep your wallet address private',
                  '⚡ Transactions complete instantly',
                  '💰 1% fee on sends, 2% on withdrawals',
                ].map(
                  (t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      t,
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _flowBar(String label, double amount, double pct, Color color) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '\$${_fmt(amount)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      );

  List<Widget> _buildTypeBreakdown() {
    final counts = <String, int>{};
    for (final tx in _txAll) {
      final t = tx['type']?.toString() ?? 'other';
      counts[t] = (counts[t] ?? 0) + 1;
    }
    if (counts.isEmpty)
      return [Text('No data yet', style: TextStyle(color: Colors.grey[600]))];
    return counts.entries.map((e) {
      final colors = {
        'deposit': Colors.green,
        'withdrawal': Colors.orange,
        'transfer': Colors.deepPurple,
        'tip': Colors.pink,
      };
      final color = colors[e.key] ?? Colors.grey;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Text(
              e.key.isNotEmpty
                  ? e.key[0].toUpperCase() + e.key.substring(1)
                  : 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '${e.value} txn${e.value > 1 ? 's' : ''}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      );
    }).toList();
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showTopUp() {
    final amtCtrl = TextEditingController();
    String method = 'card';
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
                'Top Up Wallet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Current balance: \$$_balance $_currency',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 18),
              // Quick amounts
              Wrap(
                spacing: 8,
                children: [10.0, 25.0, 50.0, 100.0, 250.0]
                    .map(
                      (a) => ActionChip(
                        label: Text('\$${a.toInt()}'),
                        onPressed: () =>
                            setLocal(() => amtCtrl.text = a.toStringAsFixed(0)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount (USD)',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Payment Method',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _methodChip(
                    'card',
                    'Credit Card',
                    Icons.credit_card,
                    method,
                    (v) => setLocal(() => method = v),
                  ),
                  const SizedBox(width: 8),
                  _methodChip(
                    'bank',
                    'Bank Transfer',
                    Icons.account_balance,
                    method,
                    (v) => setLocal(() => method = v),
                  ),
                  const SizedBox(width: 8),
                  _methodChip(
                    'crypto',
                    'Crypto',
                    Icons.currency_bitcoin,
                    method,
                    (v) => setLocal(() => method = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final amt = double.tryParse(amtCtrl.text.trim());
                          if (amt == null || amt <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid amount'),
                              ),
                            );
                            return;
                          }
                          setLocal(() => saving = true);
                          try {
                            await _ws.topUp(amount: amt, method: method);
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '\$${amt.toStringAsFixed(2)} added to your wallet!',
                                  ),
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
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: saving
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : const Text(
                          'Add Funds',
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
    );
  }

  void _showSend() {
    final addrCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    final descCtrl = TextEditingController();
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
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Send Money',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _showReceive,
                    tooltip: 'Scan QR',
                  ),
                ],
              ),
              Text(
                'Available: \$$_balance $_currency',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Recipient Wallet Address',
                  hintText: 'ETBPXXXXXXXXXXXXXXXX',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance_wallet),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '1% transaction fee applies',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final addr = addrCtrl.text.trim();
                          final amt = double.tryParse(amtCtrl.text.trim());
                          if (addr.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter wallet address'),
                              ),
                            );
                            return;
                          }
                          if (amt == null || amt <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid amount'),
                              ),
                            );
                            return;
                          }
                          if (amt > _balance) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Insufficient balance'),
                              ),
                            );
                            return;
                          }
                          setLocal(() => saving = true);
                          try {
                            final res = await _ws.sendMoney(
                              recipientAddress: addr,
                              amount: amt,
                              description: descCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Sent \$${amt.toStringAsFixed(2)} to ${res['recipient'] ?? 'recipient'}',
                                  ),
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
                          'Send Now',
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
    );
  }

  void _showWithdraw() {
    final amtCtrl = TextEditingController();
    final destCtrl = TextEditingController();
    String method = 'bank';
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
                'Withdraw Funds',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'Available: \$$_balance $_currency',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Withdrawal Method',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _methodChip(
                    'bank',
                    'Bank',
                    Icons.account_balance,
                    method,
                    (v) => setLocal(() => method = v),
                  ),
                  const SizedBox(width: 8),
                  _methodChip(
                    'paypal',
                    'PayPal',
                    Icons.payment,
                    method,
                    (v) => setLocal(() => method = v),
                  ),
                  const SizedBox(width: 8),
                  _methodChip(
                    'crypto',
                    'Crypto',
                    Icons.currency_bitcoin,
                    method,
                    (v) => setLocal(() => method = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: destCtrl,
                decoration: InputDecoration(
                  labelText: method == 'bank'
                      ? 'Account Number'
                      : method == 'paypal'
                      ? 'PayPal Email'
                      : 'Wallet Address',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.send_to_mobile),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '2% fee • Processed in 1-3 business days',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final amt = double.tryParse(amtCtrl.text.trim());
                          if (amt == null || amt <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Enter a valid amount'),
                              ),
                            );
                            return;
                          }
                          if (amt > _balance) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Insufficient balance'),
                              ),
                            );
                            return;
                          }
                          setLocal(() => saving = true);
                          try {
                            await _ws.withdraw(
                              amount: amt,
                              method: method,
                              destination: destCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Withdrawal request submitted. Processing in 1-3 days.',
                                  ),
                                  backgroundColor: Colors.orange,
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
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: saving
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      : const Text(
                          'Request Withdrawal',
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
    );
  }

  void _showReceive() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Receive Money',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Share your wallet address or QR code',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            // QR placeholder
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_2, size: 100, color: Colors.grey[400]),
                  Text(
                    'QR Code',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.deepPurple.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.deepPurple,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _address,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied: $_address'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.copy,
                      color: Colors.deepPurple,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied: $_address'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Address'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
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
            leading: const Icon(Icons.history),
            title: const Text('Transaction History'),
            onTap: () {
              Navigator.pop(ctx);
              _tabCtrl.animateTo(1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Analytics'),
            onTap: () {
              Navigator.pop(ctx);
              _tabCtrl.animateTo(2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Security Settings'),
            onTap: () => Navigator.pop(ctx),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Support'),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _methodChip(
    String value,
    String label,
    IconData icon,
    String current,
    Function(String) onSelect,
  ) {
    final sel = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? Colors.deepPurple.withValues(alpha: 0.12)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? Colors.deepPurple : Colors.grey[300]!,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: sel ? Colors.deepPurple : Colors.grey,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.deepPurple : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Boost Tab ────────────────────────────────────────────────────────────

  Widget _boostTab() {
    if (_boostLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.deepPurple),
      );
    }

    final earned =
        (_boostStats['total_earned_from_following'] as num?)?.toDouble() ?? 0;
    final rewards = (_boostStats['rewards_received'] as num?)?.toInt() ?? 0;
    final spent =
        (_boostStats['total_spent_on_boost'] as num?)?.toDouble() ?? 0;
    final gained =
        (_boostStats['total_followers_gained'] as num?)?.toInt() ?? 0;
    final activeCampaign = _boostStats['active_campaign'];

    return RefreshIndicator(
      onRefresh: _loadBoost,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── How it works banner ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.rocket_launch, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Paid Follower Boost',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _boostInfoRow('💳 You pay', '2.00 Birr per follower'),
                _boostInfoRow('💰 Follower earns', '1.70 Birr per follow'),
                _boostInfoRow('🏛️ Platform fee', '0.30 Birr per follow'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Boost your profile · Earn by following others',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── My earnings row ──────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _boostStatCard(
                  Icons.savings,
                  'Earned Following',
                  '${earned.toStringAsFixed(2)} Birr',
                  Colors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _boostStatCard(
                  Icons.people,
                  'Rewards Received',
                  '$rewards',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _boostStatCard(
                  Icons.trending_up,
                  'Boost Spent',
                  '${spent.toStringAsFixed(2)}₿',
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Second row — followers gained
          Row(
            children: [
              Expanded(
                child: _boostStatCard(
                  Icons.people_outline,
                  'Followers Gained',
                  '$gained',
                  Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Active campaign ──────────────────────────────────────────
          if (activeCampaign != null) ...[
            _sectionHeader('📢 Active Campaign'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.deepPurple.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: Colors.green),
                            SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(activeCampaign['progress_pct'] as num?)?.toStringAsFixed(1) ?? '0'}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${activeCampaign['followers_gained']} / ${activeCampaign['target_followers']} followers',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${(activeCampaign['total_spent'] as num?)?.toStringAsFixed(2) ?? '0'} / ${(activeCampaign['total_cost'] as num?)?.toStringAsFixed(2) ?? '0'} Birr',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value:
                          ((activeCampaign['progress_pct'] as num?)
                                  ?.toDouble() ??
                              0) /
                          100,
                      minHeight: 10,
                      backgroundColor: Colors.deepPurple.withValues(
                        alpha: 0.12,
                      ),
                      valueColor: const AlwaysStoppedAnimation(
                        Colors.deepPurple,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelBoost(activeCampaign['id']),
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Cancel & Refund'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Create new boost ─────────────────────────────────────────
          if (activeCampaign == null) ...[
            _sectionHeader('🚀 Create Boost Campaign'),
            _CreateBoostCard(
              balance: _balance,
              currency: _currency,
              onCreated: () {
                _load();
                _loadBoost();
              },
            ),
            const SizedBox(height: 16),
          ],

          // ── Discover boosted users ───────────────────────────────────
          _sectionHeader('💎 Follow & Earn — Boosted Users'),
          if (_boostedUsers.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: const Center(
                child: Text(
                  'No boosted users right now.\nCheck back later!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._boostedUsers.map((u) => _BoostedUserCard(user: u)).toList(),

          const SizedBox(height: 16),

          // ── Past campaigns ───────────────────────────────────────────
          if (_myCampaigns.isNotEmpty) ...[
            _sectionHeader('📋 My Campaigns'),
            ..._myCampaigns
                .map((c) => _CampaignHistoryCard(campaign: c))
                .toList(),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _boostInfoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );

  Widget _boostStatCard(
    IconData icon,
    String label,
    String value,
    Color color,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
      ],
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  );

  Future<void> _cancelBoost(dynamic id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Boost'),
        content: const Text(
          'Cancel your boost campaign? Unused balance will be refunded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Cancel & Refund',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final res = await BoostService().cancelBoost(id as int);
        final refund = (res['refund'] as num?)?.toStringAsFixed(2) ?? '0';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cancelled. $refund Birr refunded.'),
              backgroundColor: Colors.green,
            ),
          );
        }
        _load();
        _loadBoost();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
          );
      }
    }
  }
}

// ─── Create Boost Card widget ─────────────────────────────────────────────────

class _CreateBoostCard extends StatefulWidget {
  final double balance;
  final String currency;
  final VoidCallback onCreated;
  const _CreateBoostCard({
    required this.balance,
    required this.currency,
    required this.onCreated,
  });

  @override
  State<_CreateBoostCard> createState() => _CreateBoostCardState();
}

class _CreateBoostCardState extends State<_CreateBoostCard> {
  int _target = 100;
  bool _loading = false;

  double get _totalCost => _target * 2.00;
  bool get _canAfford => widget.balance >= _totalCost;

  Future<void> _create() async {
    setState(() => _loading = true);
    try {
      await BoostService().createBoost(_target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🚀 Boost started! You\'ll gain up to $_target followers for ${_totalCost.toStringAsFixed(2)} Birr.',
            ),
            backgroundColor: Colors.deepPurple,
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = [10, 25, 50, 100, 250, 500, 1000];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose Followers',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((n) {
              final selected = _target == n;
              return GestureDetector(
                onTap: () => setState(() => _target = n),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.deepPurple : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? Colors.deepPurple : Colors.grey[300]!,
                    ),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          // Cost breakdown
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                _costRow('Followers to buy', '$_target'),
                _costRow('Price per follower', '2.00 Birr'),
                _costRow('Follower earns', '1.70 Birr each'),
                _costRow('Platform fee', '0.30 Birr each'),
                const Divider(),
                _costRow(
                  'Total cost',
                  '${_totalCost.toStringAsFixed(2)} Birr',
                  bold: true,
                ),
                _costRow(
                  'Your balance',
                  '${widget.balance.toStringAsFixed(2)} ${widget.currency}',
                  color: _canAfford ? Colors.green : Colors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!_canAfford)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Insufficient balance. Top up at least ${(_totalCost - widget.balance).toStringAsFixed(2)} Birr.',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!_canAfford || _loading) ? null : _create,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.rocket_launch),
              label: Text(
                _loading
                    ? 'Starting...'
                    : 'Start Boost for ${_totalCost.toStringAsFixed(2)} Birr',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _costRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            fontSize: bold ? 15 : 13,
            color: color ?? (bold ? Colors.black : Colors.black87),
          ),
        ),
      ],
    ),
  );
}

// ─── Boosted User Card ────────────────────────────────────────────────────────

class _BoostedUserCard extends StatefulWidget {
  final dynamic user;
  const _BoostedUserCard({required this.user});
  @override
  State<_BoostedUserCard> createState() => _BoostedUserCardState();
}

class _BoostedUserCardState extends State<_BoostedUserCard> {
  bool _following = false;
  bool _loading = false;

  Future<void> _follow() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      await api.post('/users/${widget.user['user_id']}/follow');
      setState(() => _following = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Followed! You earned 1.70 Birr 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final pic = u['profile_image']?.toString() ?? '';
    final name =
        u['full_name']?.toString() ?? u['username']?.toString() ?? 'User';
    final username = u['username']?.toString() ?? '';
    final needed = (u['followers_needed'] as num?)?.toInt() ?? 0;
    final earn = (u['earn_per_follow'] as num?)?.toDouble() ?? 1.70;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.deepPurple,
            backgroundImage: pic.isNotEmpty ? NetworkImage(pic) : null,
            child: pic.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '@$username',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Earn ${earn.toStringAsFixed(2)} Birr · $needed spots left',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: (_following || _loading) ? null : _follow,
            style: ElevatedButton.styleFrom(
              backgroundColor: _following
                  ? Colors.grey[300]
                  : Colors.deepPurple,
              foregroundColor: _following ? Colors.grey[700] : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _following
                        ? 'Following'
                        : 'Follow +${earn.toStringAsFixed(2)}₿',
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Campaign History Card ────────────────────────────────────────────────────

class _CampaignHistoryCard extends StatelessWidget {
  final dynamic campaign;
  const _CampaignHistoryCard({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final gained = (campaign['followers_gained'] as num?)?.toInt() ?? 0;
    final target = (campaign['target_followers'] as num?)?.toInt() ?? 0;
    final spent = (campaign['total_spent'] as num?)?.toDouble() ?? 0;
    final cost = (campaign['total_cost'] as num?)?.toDouble() ?? 0;
    final status = campaign['status']?.toString() ?? '';
    final pct = target > 0 ? gained / target : 0.0;

    final statusColor = status == 'active'
        ? Colors.green
        : status == 'completed'
        ? Colors.blue
        : status == 'cancelled'
        ? Colors.red
        : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
              const Spacer(),
              Text(
                '${spent.toStringAsFixed(2)} / ${cost.toStringAsFixed(2)} Birr',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$gained / $target followers gained',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation(Colors.deepPurple),
            ),
          ),
        ],
      ),
    );
  }
}
