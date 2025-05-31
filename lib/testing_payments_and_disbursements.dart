import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const PaymentTesterApp());
}

class PaymentTesterApp extends StatelessWidget {
  const PaymentTesterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoMo Payment Tester',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MoMo API Tester'),
        centerTitle: true,
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
                    builder: (context) => const TestCollectionsScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('Test Collections (Payments)'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TestDisbursementsScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: const Text('Test Disbursements'),
            ),
          ],
        ),
      ),
    );
  }
}

class TestCollectionsScreen extends StatefulWidget {
  const TestCollectionsScreen({super.key});

  @override
  State<TestCollectionsScreen> createState() => _TestCollectionsScreenState();
}

class _TestCollectionsScreenState extends State<TestCollectionsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '1000');
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String _response = '';

  @override
  void dispose() {
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Handle different formats
    if (digits.startsWith('0')) {
      // Convert 07... to 2567...
      return '256${digits.substring(1)}';
    } else if (digits.startsWith('256')) {
      // Already in 256 format
      return digits;
    } else if (digits.startsWith('+256')) {
      // Remove the +
      return digits.substring(1);
    } else if (digits.length == 9) {
      // Assume it's a 9-digit number without prefix
      return '256$digits';
    }
    
    // Return as is if we can't determine the format
    return digits;
  }

  Future<void> _requestPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _response = 'Processing...';
    });

    try {
      final baseUrl = dotenv.get('API_BASE_URL');
      final endpoint = '/api/v1/momo/request-payment';
      final url = Uri.parse('$baseUrl$endpoint');
      final formattedPhone = _formatPhoneNumber(_phoneController.text);
      
      setState(() {
        _response = 'Sending request to: $url\nPhone: $formattedPhone\n\n';
      });
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'amount': double.parse(_amountController.text),
          'payer_number': formattedPhone,
          // Other parameters will use their default values
        }),
      );

      final responseData = jsonDecode(response.body);
      
      setState(() {
        _response = 'Response: ${response.statusCode}\n\n${jsonEncode(responseData, toEncodable: (e) => e.toString())}';
      });

      if (response.statusCode == 200) {
        // Show success message
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment request sent successfully!')),
        );
      } else {
        // Show error message
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${responseData['detail'] ?? 'Unknown error'}')),
        );
      }
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Collections (Payments)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: 'UGX ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'e.g., 0700000000 or 256700000000',
                  border: OutlineInputBorder(),
                  prefixText: '+',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a phone number';
                  }
                  // Basic validation - should have at least 9 digits (for 07... numbers)
                  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length < 9 || digits.length > 12) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _requestPayment,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Request Payment'),
              ),
              const SizedBox(height: 24),
              if (_response.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SelectableText(
                      _response,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TestDisbursementsScreen extends StatefulWidget {
  const TestDisbursementsScreen({super.key});

  @override
  State<TestDisbursementsScreen> createState() => _TestDisbursementsScreenState();
}

class _TestDisbursementsScreenState extends State<TestDisbursementsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '1000');
  final _payeeIdController = TextEditingController();
  bool _isLoading = false;
  String _response = '';

  @override
  void dispose() {
    _amountController.dispose();
    _payeeIdController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Handle different formats
    if (digits.startsWith('0')) {
      // Convert 07... to 2567...
      return '256${digits.substring(1)}';
    } else if (digits.startsWith('256')) {
      // Already in 256 format
      return digits;
    } else if (digits.startsWith('+256')) {
      // Remove the +
      return digits.substring(1);
    } else if (digits.length == 9) {
      // Assume it's a 9-digit number without prefix
      return '256$digits';
    }
    
    // Return as is if we can't determine the format
    return digits;
  }

  Future<void> _disburseFunds() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _response = 'Processing...';
    });

    try {
      final baseUrl = dotenv.get('API_BASE_URL');
      final endpoint = '/api/v1/momo/disburse';
      final url = Uri.parse('$baseUrl$endpoint');
      final formattedPayeeId = _formatPhoneNumber(_payeeIdController.text);
      
      setState(() {
        _response = 'Sending request to: $url\nPayee ID: $formattedPayeeId\n\n';
      });
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'amount': double.parse(_amountController.text),
          'payee_id': formattedPayeeId,
          // Other parameters will use their default values
        }),
      );

      final responseData = jsonDecode(response.body);
      
      setState(() {
        _response = 'Response: ${response.statusCode}\n\n${jsonEncode(responseData, toEncodable: (e) => e.toString())}';
      });

      if (response.statusCode == 200) {
        // Show success message
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disbursement request sent successfully!')),
        );
      } else {
        // Show error message
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${responseData['detail'] ?? 'Unknown error'}')),
        );
      }
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Disbursements'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: 'UGX ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _payeeIdController,
                decoration: const InputDecoration(
                  labelText: 'Payee Phone Number',
                  hintText: 'e.g., 0700000000 or 256700000000',
                  border: OutlineInputBorder(),
                  prefixText: '+',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a phone number';
                  }
                  // Basic validation - should have at least 9 digits (for 07... numbers)
                  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
                  if (digits.length < 9 || digits.length > 12) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _disburseFunds,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Disburse Funds'),
              ),
              const SizedBox(height: 24),
              if (_response.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SelectableText(
                      _response,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
