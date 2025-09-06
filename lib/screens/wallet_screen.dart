import 'package:flutter/material.dart';
import '../services/wallet_service.dart';
import '../widgets/wallet_balance_widget.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({Key? key}) : super(key: key);

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _walletService = WalletService();
  int _selectedIndex = 4; // Assuming wallet is a new tab

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        Navigator.of(context).pushReplacementNamed('/home');
        break;
      case 1:
        Navigator.of(context).pushReplacementNamed('/profile');
        break;
      case 2:
        Navigator.of(context).pushReplacementNamed('/history');
        break;
      case 3:
        Navigator.of(context).pushReplacementNamed('/settings');
        break;
      case 4:
        // Already on wallet screen
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.myWallet),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          const WalletBalanceWidget(showRechargeButton: true),
          const SizedBox(height: 24),
          
          // Fee information card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(
                      loc.transactionFee,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  loc.eachCompletedTransactionCharges,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.card_giftcard, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loc.welcomeBonus,
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Transaction history
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history),
                        const SizedBox(width: 8),
                        Text(
                          loc.walletHistory,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<WalletTransaction>>(
                      stream: _walletService.getWalletTransactionsStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Center(
                            child: Text(
                              loc.noWalletTransactions,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          );
                        }
                        
                        final transactions = snapshot.data!;
                        
                        return ListView.builder(
                          itemCount: transactions.length,
                          itemBuilder: (context, index) {
                            final tx = transactions[index];
                            return _buildTransactionTile(tx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFE53935),
        unselectedItemColor: Colors.grey,
        onTap: _onNavTap,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: loc.home),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: loc.profile),
          BottomNavigationBarItem(icon: const Icon(Icons.history), label: loc.history),
          BottomNavigationBarItem(icon: const Icon(Icons.settings), label: loc.settings),
          BottomNavigationBarItem(icon: const Icon(Icons.account_balance_wallet), label: loc.wallet),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(WalletTransaction tx) {
    final loc = AppLocalizations.of(context)!;
    final isCredit = tx.amount > 0;
    final icon = tx.type == 'deposit' 
        ? Icons.add_circle 
        : tx.type == 'fee_deduction' 
            ? Icons.remove_circle 
            : Icons.refresh;
    
    final color = isCredit ? Colors.green : Colors.red;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(
          tx.description,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatTransactionDate(tx.createdAt),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (tx.relatedTransactionId != null)
              Text(
                'Transaction ID: ${tx.relatedTransactionId!.substring(0, 8)}...',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isCredit ? '+' : ''}${tx.amount.toStringAsFixed(3)} EGP',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
            Text(
              '${loc.walletBalance}: ${tx.balanceAfter.toStringAsFixed(3)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        onTap: () => _showTransactionDetails(tx),
      ),
    );
  }

  void _showTransactionDetails(WalletTransaction tx) {
    final loc = AppLocalizations.of(context)!;
    final isCredit = tx.amount > 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.transactionDetails),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Type', tx.type.toUpperCase()),
            _buildDetailRow('Amount', '${isCredit ? '+' : ''}${tx.amount.toStringAsFixed(3)} EGP'),
            _buildDetailRow('Description', tx.description),
            _buildDetailRow('Date', _formatTransactionDate(tx.createdAt)),
            _buildDetailRow('Balance Before', '${tx.balanceBefore.toStringAsFixed(3)} EGP'),
            _buildDetailRow('Balance After', '${tx.balanceAfter.toStringAsFixed(3)} EGP'),
            if (tx.relatedTransactionId != null)
              _buildDetailRow('Related Transaction', tx.relatedTransactionId!),
            if (tx.paymentReference != null)
              _buildDetailRow('Payment Reference', tx.paymentReference!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.close),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTransactionDate(DateTime date) {
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return '${loc.today} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return loc.yesterday;
    } else if (difference.inDays < 7) {
      return loc.daysAgo.replaceAll('{days}', difference.inDays.toString());
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
