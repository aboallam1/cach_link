import 'package:flutter/material.dart';
import '../services/wallet_service.dart';
import 'package:cashlink/l10n/app_localizations.dart';

class WalletBalanceWidget extends StatelessWidget {
  final bool showRechargeButton;
  
  const WalletBalanceWidget({
    Key? key,
    this.showRechargeButton = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final walletService = WalletService();
    final loc = AppLocalizations.of(context)!;

    return StreamBuilder<double>(
      stream: walletService.getWalletBalanceStream(),
      builder: (context, snapshot) {
        final balance = snapshot.data ?? 0.0;
        final hasLowBalance = balance < WalletService.TRANSACTION_FEE;

        return Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: hasLowBalance 
                ? [Colors.red.shade100, Colors.red.shade50]
                : [Colors.green.shade100, Colors.green.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasLowBalance ? Colors.red.shade300 : Colors.green.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loc.walletBalance,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: hasLowBalance ? Colors.red.shade700 : Colors.green.shade700,
                    ),
                  ),
                  Icon(
                    hasLowBalance ? Icons.warning : Icons.account_balance_wallet,
                    color: hasLowBalance ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${balance.toStringAsFixed(3)} EGP',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: hasLowBalance ? Colors.red.shade800 : Colors.green.shade800,
                ),
              ),
              if (hasLowBalance) ...[
                const SizedBox(height: 8),
                Text(
                  loc.lowBalance.replaceAll('{fee}', WalletService.TRANSACTION_FEE.toString()),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (showRechargeButton) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showRechargeDialog(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(loc.rechargeWallet),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showRechargeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const RechargeWalletDialog(),
    );
  }
}

class RechargeWalletDialog extends StatefulWidget {
  const RechargeWalletDialog({Key? key}) : super(key: key);

  @override
  State<RechargeWalletDialog> createState() => _RechargeWalletDialogState();
}

class _RechargeWalletDialogState extends State<RechargeWalletDialog> {
  final _amountController = TextEditingController();
  bool _loading = false;
  
  final List<double> _quickAmounts = [5.0, 10.0, 25.0, 50.0];

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    
    return AlertDialog(
      title: Text(loc.rechargeWallet),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: loc.amountEgp,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.monetization_on),
            ),
          ),
          const SizedBox(height: 16),
          Text(loc.quickAmounts, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _quickAmounts.map((amount) => 
              ActionChip(
                label: Text('${amount.toInt()} EGP'),
                onPressed: () => _amountController.text = amount.toString(),
              ),
            ).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.cancel),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _rechargeWallet,
          child: _loading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(loc.rechargeWallet),
        ),
      ],
    );
  }

  void _rechargeWallet() async {
    final loc = AppLocalizations.of(context)!;
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) return;

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.pleaseEnterValidAmount)),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Simulate payment processing
      await Future.delayed(const Duration(seconds: 2));
      
      // Call the wallet service to process deposit
      final walletService = WalletService();
      final success = await walletService.processDeposit(
        amount: amount,
        paymentReference: 'RECHARGE_${DateTime.now().millisecondsSinceEpoch}',
      );
      
      if (!success) {
        throw Exception(loc.paymentProcessingFailed);
      }
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.successfullyRecharged.replaceAll('{amount}', amount.toStringAsFixed(2)))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.rechargeFailed.replaceAll('{error}', e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
}