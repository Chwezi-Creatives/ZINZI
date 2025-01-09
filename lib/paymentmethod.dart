import 'package:flutter/material.dart';
import 'package:zinzi2/paypp1webviewstatic.dart';
import 'package:zinzi2/paystrpworkingbutlimited.dart';
import 'package:zinzi2/paystrpfaulty.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final apibaseurl = dotenv.env['API_BASE_URL'] ?? 'https://default.url';

class PaymentMethodSelectionPage extends StatelessWidget {
  const PaymentMethodSelectionPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Payment Method'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentScreenpp(),
                  ),
                );
              },
              child: const Text('Pay with PayPal'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentScreenstrp(),
                  ),
                );
              },
              child: const Text('Pay with Stripe (new)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => PaymentScreennowebview()));
              },
              child: const Text('Pay with stripe (Outdated)'),
            ),
          ],
        ),
      ),
    );
  }
}
