import 'api_client.dart';

class WalletService {
  final ApiClient _api = ApiClient();

  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();

  Future<Map<String, dynamic>> getWallet() async {
    try {
      final r = await _api.get('/wallet');
      return Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return {
        'balance': 0.0,
        'wallet_address': 'ETBP00000000',
        'currency': 'USD',
      };
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final r = await _api.get('/wallet/stats');
      return Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return {
        'balance': 0.0,
        'total_received': 0.0,
        'total_sent': 0.0,
        'total_fees': 0.0,
      };
    }
  }

  Future<List<dynamic>> getTransactions({int page = 1, String? type}) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'page_size': '30',
      };
      if (type != null) params['type'] = type;
      final r = await _api.get('/wallet/transactions', queryParams: params);
      return (r['transactions'] as List?) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> topUp({
    required double amount,
    String method = 'card',
    String description = '',
  }) async {
    return Map<String, dynamic>.from(
      await _api.post(
            '/wallet/topup',
            body: {
              'amount': amount,
              'method': method,
              'description': description,
            },
          )
          as Map,
    );
  }

  Future<Map<String, dynamic>> sendMoney({
    required String recipientAddress,
    required double amount,
    String description = '',
  }) async {
    return Map<String, dynamic>.from(
      await _api.post(
            '/wallet/send',
            body: {
              'recipient_address': recipientAddress,
              'amount': amount,
              'description': description,
            },
          )
          as Map,
    );
  }

  Future<Map<String, dynamic>> withdraw({
    required double amount,
    String method = 'bank',
    String destination = '',
  }) async {
    return Map<String, dynamic>.from(
      await _api.post(
            '/wallet/withdraw',
            body: {
              'amount': amount,
              'method': method,
              'destination': destination,
            },
          )
          as Map,
    );
  }
}
