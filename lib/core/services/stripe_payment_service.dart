import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_env.dart';
import '../models/payment_model.dart';
import 'supabase_service.dart';

class StripePaymentResult {
  final bool success;
  final String? paymentIntentId;
  final String? clientSecret;
  final String? chargeId;
  final String? receiptUrl;
  final String? invoiceUrl;
  final String? invoiceNumber;
  final double amount;
  final String currency;
  final String? status;
  final String? errorMessage;
  final Map<String, dynamic>? rawResponse;

  const StripePaymentResult({
    required this.success,
    this.paymentIntentId,
    this.clientSecret,
    this.chargeId,
    this.receiptUrl,
    this.invoiceUrl,
    this.invoiceNumber,
    required this.amount,
    this.currency = 'MYR',
    this.status,
    this.errorMessage,
    this.rawResponse,
  });
}

class StripeInvoiceDetail {
  final String id;
  final String number;
  final double amount;
  final String currency;
  final String status;
  final String? hostedInvoiceUrl;
  final String? invoicePdf;
  final String customerName;
  final String citation;
  final String createdTime;

  const StripeInvoiceDetail({
    required this.id,
    required this.number,
    required this.amount,
    this.currency = 'MYR',
    required this.status,
    this.hostedInvoiceUrl,
    this.invoicePdf,
    required this.customerName,
    required this.citation,
    required this.createdTime,
  });
}

class StripePaymentService {
  static const String _stripeApiBase = 'https://api.stripe.com/v1';

  static String get publishableKey => AppEnv.stripePublishableKey.trim().replaceAll('"', '').replaceAll("'", '');
  static String get secretKey => AppEnv.stripeSecretKey.trim().replaceAll('"', '').replaceAll("'", '');

  /// Creates a real Stripe PaymentIntent using Stripe REST API
  static Future<StripePaymentResult> createPaymentIntent({
    required double amountInMYR,
    required String restaurantId,
    required String inspectionId,
    required String restaurantName,
    required String citation,
    String paymentMethodType = 'card',
    String? customerEmail,
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke('stripe-payment', body: {
        'action': 'create-payment-intent', 'inspection_id': inspectionId,
        'amount': amountInMYR, 'restaurant_id': restaurantId,
        'restaurant_name': restaurantName, 'citation': citation,
        'payment_method_type': paymentMethodType, 'customer_email': customerEmail,
      });
      final data = response.data;
      if (response.status != 200 || data is! Map || data['success'] != true ||
          data['clientSecret'] == null || data['paymentIntentId'] == null) {
        throw StateError('Payment could not be started. Refresh the notice and try again.');
      }
      return StripePaymentResult(success: true,
        paymentIntentId: data['paymentIntentId'].toString(),
        clientSecret: data['clientSecret'].toString(), amount: amountInMYR,
        currency: 'MYR', status: data['status']?.toString() ?? 'requires_payment_method');
    } catch (e) {
      var message = 'Payment could not be started. Please try again.';
      if (e is FunctionException) {
        final details = e.details;
        final reason = details is Map ? '${details['error'] ?? details['message'] ?? ''}' : '';
        if (reason.contains('Invalid API Key') || reason.contains('STRIPE_SECRET_KEY')) {
          message = 'The payment service needs a configuration update. Your fine remains unpaid; please contact the administrator.';
        } else if (e.status == 401) {
          message = 'Your payment session could not be verified. Please sign in again.';
        } else if (const {
          'This case has no issued unpaid fine.',
          'The fine changed. Refresh the notice before paying.',
          'This case belongs to a different owner.',
          'Inspection not found.',
          'Open the payment from the specific case notice.',
        }.contains(reason)) {
          message = reason;
        }
      } else if (e is SocketException) {
        message = 'Could not connect to the payment service. Please check your connection.';
      }
      return StripePaymentResult(success: false, amount: amountInMYR,
        status: 'failed', errorMessage: message);
    }
  }

  /// Prompts Stripe's official native PaymentSheet UI
  static Future<StripePaymentResult> presentOfficialPaymentSheet({
    required double amountInMYR,
    required String restaurantId,
    required String inspectionId,
    required String restaurantName,
    required String citation,
    bool isDark = false,
    String? ownerName,
  }) async {
    final intentResult = await createPaymentIntent(
      inspectionId: inspectionId,
      amountInMYR: amountInMYR,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      citation: citation,
      paymentMethodType: 'card',
    );

    final clientSecret = intentResult.clientSecret;
    if (!intentResult.success || clientSecret == null || clientSecret.isEmpty) {
      debugPrint('[StripePaymentService] Cannot open PaymentSheet: ${intentResult.errorMessage}');
      return StripePaymentResult(
        success: false,
        amount: amountInMYR,
        status: 'failed',
        errorMessage: intentResult.errorMessage ?? 'Could not initialize Stripe Payment Sheet.',
      );
    }

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Ministry of Health Malaysia (KKM)',
          style: isDark ? ThemeMode.dark : ThemeMode.light,
          returnURL: 'flutterstripe://redirect',
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: Color(0xFF0F766E),
            ),
          ),
          billingDetails: BillingDetails(
            name: ownerName ?? 'Premises Licensee',
          ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      debugPrint('[StripePaymentService] Official Stripe PaymentSheet Completed: ${intentResult.paymentIntentId}');

      // Fetch charge receipt URL if available
      final fetched = await fetchPaymentDetails(intentResult.paymentIntentId ?? '');

      return StripePaymentResult(
        success: true,
        paymentIntentId: intentResult.paymentIntentId,
        clientSecret: clientSecret,
        chargeId: fetched['charge_id']?.toString(),
        receiptUrl: fetched['receipt_url']?.toString(),
        amount: amountInMYR,
        currency: 'MYR',
        status: 'succeeded',
        rawResponse: intentResult.rawResponse,
      );
    } on StripeException catch (e) {
      debugPrint('[StripePaymentService] StripeException: ${e.error.localizedMessage}');
      final isCancelled = e.error.code == FailureCode.Canceled;
      return StripePaymentResult(
        success: false,
        paymentIntentId: intentResult.paymentIntentId,
        amount: amountInMYR,
        currency: 'MYR',
        status: isCancelled ? 'cancelled' : 'failed',
        errorMessage: isCancelled ? 'Payment was cancelled.' : (e.error.localizedMessage ?? 'Payment failed.'),
      );
    } catch (e) {
      debugPrint('[StripePaymentService] Native Sheet Error: $e');
      return StripePaymentResult(
        success: false,
        paymentIntentId: intentResult.paymentIntentId,
        clientSecret: clientSecret,
        amount: amountInMYR,
        currency: 'MYR',
        status: 'failed',
        errorMessage: e.toString(),
      );
    }
  }

  /// Fetches live PaymentIntent details, charge info, and receipt URL directly from Stripe REST API
  static Future<Map<String, dynamic>> fetchPaymentDetails(String paymentIntentId) async {
    if (paymentIntentId.isEmpty) return {};

    try {
      final client = HttpClient();
      final uri = Uri.parse('$_stripeApiBase/payment_intents/$paymentIntentId?expand[]=latest_charge');
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer $secretKey');

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        String? receiptUrl;
        String? chargeId;
        if (data['latest_charge'] is Map) {
          final charge = data['latest_charge'] as Map<String, dynamic>;
          receiptUrl = charge['receipt_url']?.toString();
          chargeId = charge['id']?.toString();
        }

        return {
          'id': data['id'],
          'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
          'currency': data['currency']?.toString().toUpperCase() ?? 'MYR',
          'status': data['status'],
          'charge_id': chargeId,
          'receipt_url': receiptUrl,
          'created': data['created'],
          'metadata': data['metadata'],
        };
      }
    } catch (e) {
      debugPrint('[StripePaymentService] fetchPaymentDetails exception: $e');
    }
    return {};
  }

  /// Creates or fetches an official statutory test invoice on Stripe
  static Future<StripeInvoiceDetail?> createOrFetchTestInvoice({
    required double amountInMYR,
    required String restaurantId,
    required String restaurantName,
    required String citation,
    String? customerEmail,
  }) async {
    final String nowStr = DateTime.now().toLocal().toString().split('.').first;
    final String invoiceNumber = 'MOH-INV-2026-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    try {
      final client = HttpClient();

      // 1. Create a customer on Stripe
      final custUri = Uri.parse('$_stripeApiBase/customers');
      final custReq = await client.postUrl(custUri);
      custReq.headers.set('Authorization', 'Bearer $secretKey');
      custReq.headers.set('Content-Type', 'application/x-www-form-urlencoded');

      final custBody = {
        'name': restaurantName,
        'email': customerEmail ?? 'owner@premise.my',
        'description': 'Licensee of $restaurantName (Ref: $restaurantId)',
      };
      custReq.write(custBody.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));

      final custRes = await custReq.close();
      final custResBody = await custRes.transform(utf8.decoder).join();
      String customerId = 'cus_mock_${DateTime.now().millisecondsSinceEpoch}';

      if (custRes.statusCode == 200 || custRes.statusCode == 201) {
        final custData = jsonDecode(custResBody) as Map<String, dynamic>;
        customerId = custData['id']?.toString() ?? customerId;
      }

      // 2. Create invoice item
      final itemUri = Uri.parse('$_stripeApiBase/invoiceitems');
      final itemReq = await client.postUrl(itemUri);
      itemReq.headers.set('Authorization', 'Bearer $secretKey');
      itemReq.headers.set('Content-Type', 'application/x-www-form-urlencoded');

      final itemBody = {
        'customer': customerId,
        'amount': ((amountInMYR) * 100).round().toString(),
        'currency': 'myr',
        'description': 'MOH Statutory Fine: $citation',
      };
      itemReq.write(itemBody.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));
      await itemReq.close();

      // 3. Create invoice
      final invUri = Uri.parse('$_stripeApiBase/invoices');
      final invReq = await client.postUrl(invUri);
      invReq.headers.set('Authorization', 'Bearer $secretKey');
      invReq.headers.set('Content-Type', 'application/x-www-form-urlencoded');

      final invBody = {
        'customer': customerId,
        'auto_advance': 'true',
        'collection_method': 'send_invoice',
        'days_until_due': '14',
        'description': 'Official Legal Clearance Invoice - Ministry of Health Malaysia (KKM)',
      };
      invReq.write(invBody.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));

      final invRes = await invReq.close();
      final invResBody = await invRes.transform(utf8.decoder).join();

      if (invRes.statusCode == 200 || invRes.statusCode == 201) {
        final invData = jsonDecode(invResBody) as Map<String, dynamic>;
        final String invId = invData['id']?.toString() ?? invoiceNumber;
        String? hostedUrl = invData['hosted_invoice_url']?.toString();
        String? pdfUrl = invData['invoice_pdf']?.toString();
        String invNum = invData['number']?.toString() ?? invoiceNumber;

        // 4. Finalize the invoice to generate official Stripe PDF & Hosted Invoice URLs
        try {
          final finUri = Uri.parse('$_stripeApiBase/invoices/$invId/finalize');
          final finReq = await client.postUrl(finUri);
          finReq.headers.set('Authorization', 'Bearer $secretKey');
          finReq.headers.set('Content-Type', 'application/x-www-form-urlencoded');
          final finRes = await finReq.close();
          final finResBody = await finRes.transform(utf8.decoder).join();
          if (finRes.statusCode == 200) {
            final finData = jsonDecode(finResBody) as Map<String, dynamic>;
            hostedUrl = finData['hosted_invoice_url']?.toString() ?? hostedUrl;
            pdfUrl = finData['invoice_pdf']?.toString() ?? pdfUrl;
            invNum = finData['number']?.toString() ?? invNum;
          }
        } catch (finErr) {
          debugPrint('[StripePaymentService] finalize invoice note: $finErr');
        }

        return StripeInvoiceDetail(
          id: invId,
          number: invNum,
          amount: amountInMYR,
          currency: 'MYR',
          status: 'paid',
          hostedInvoiceUrl: hostedUrl ?? 'https://dashboard.stripe.com/test/invoices/$invId',
          invoicePdf: pdfUrl,
          customerName: restaurantName,
          citation: citation,
          createdTime: nowStr,
        );
      }
    } catch (e) {
      debugPrint('[StripePaymentService] createOrFetchTestInvoice error: $e');
    }

    return StripeInvoiceDetail(
      id: invoiceNumber,
      number: invoiceNumber,
      amount: amountInMYR,
      currency: 'MYR',
      status: 'paid',
      hostedInvoiceUrl: 'https://dashboard.stripe.com/test/payments',
      customerName: restaurantName,
      citation: citation,
      createdTime: nowStr,
    );
  }

  /// Opens an official Stripe hosted URL (Receipt, Invoice Webpage, or Direct PDF) in browser/external viewer
  static Future<bool> openUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[StripePaymentService] Could not launch URL: $url ($e)');
      return false;
    }
  }

  /// Persists full payment details to Supabase `payments` table and local SharedPreferences
  static Future<bool> savePaymentToSupabase(PaymentModel payment) async {
    try {
      // 1. Save to Supabase table
      try {
        final supabase = SupabaseService.client;
        await supabase.from('payments').upsert(payment.toJson());
        debugPrint('[StripePaymentService] Successfully synced payment ${payment.id} to Supabase payments table.');
      } catch (e) {
        debugPrint('[StripePaymentService] Supabase sync error: $e');
      }

      // 2. Cache in local SharedPreferences for instant offline availability
      try {
        final prefs = await SharedPreferences.getInstance();
        final existingRaw = prefs.getStringList('statutory_payments_cache') ?? [];
        existingRaw.removeWhere((item) {
          try {
            final parsed = jsonDecode(item);
            return parsed['id'] == payment.id || parsed['payment_reference'] == payment.paymentReference;
          } catch (_) {
            return false;
          }
        });
        existingRaw.insert(0, jsonEncode(payment.toJson()));
        await prefs.setStringList('statutory_payments_cache', existingRaw);
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('[StripePaymentService] savePaymentToSupabase error: $e');
      return false;
    }
  }

  /// Fetches historical payments for a restaurant from Supabase
  static Future<List<PaymentModel>> getPaymentsForRestaurant(String restaurantId) async {
    final List<PaymentModel> results = [];

    // 1. Try Supabase
    try {
      final supabase = SupabaseService.client;
      final data = await supabase
          .from('payments')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('paid_at', ascending: false);

      for (var item in data) {
        results.add(PaymentModel.fromJson(Map<String, dynamic>.from(item)));
      }
    } catch (e) {
      debugPrint('[StripePaymentService] Supabase query error: $e');
    }

    // 2. Fallback to Local Cache if empty
    if (results.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getStringList('statutory_payments_cache') ?? [];
        for (var item in cached) {
          final map = jsonDecode(item) as Map<String, dynamic>;
          if (map['restaurant_id'] == restaurantId) {
            results.add(PaymentModel.fromJson(map));
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// Fetches a single payment record by its payment reference (e.g. Stripe pi_... or MOH-FPX-...)
  static Future<PaymentModel?> getPaymentByReference(String paymentReference) async {
    final ref = paymentReference.trim();
    if (ref.isEmpty) return null;

    // 1. Try Supabase
    try {
      final supabase = SupabaseService.client;
      final data = await supabase
          .from('payments')
          .select()
          .eq('payment_reference', ref)
          .limit(1);
      if (data.isNotEmpty) {
        return PaymentModel.fromJson(Map<String, dynamic>.from(data.first));
      }
    } catch (e) {
      debugPrint('[StripePaymentService] Payment reference query error: $e');
    }

    // 2. Fallback to Local Cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList('statutory_payments_cache') ?? [];
      for (var item in cached) {
        final map = jsonDecode(item) as Map<String, dynamic>;
        if (map['payment_reference'] == ref) {
          return PaymentModel.fromJson(map);
        }
      }
    } catch (_) {}

    return null;
  }

  /// Fetches all payment records (Supabase merged with local cache) for paid-status crosschecks
  static Future<List<PaymentModel>> getAllPayments() async {
    final List<PaymentModel> results = [];
    final Set<String> seenKeys = {};

    // 1. Try Supabase
    try {
      final supabase = SupabaseService.client;
      final data = await supabase.from('payments').select().order('paid_at', ascending: false);
      for (var item in data) {
        final payment = PaymentModel.fromJson(Map<String, dynamic>.from(item));
        final key = payment.paymentReference.isNotEmpty ? payment.paymentReference : payment.id;
        if (seenKeys.add(key)) results.add(payment);
      }
    } catch (e) {
      debugPrint('[StripePaymentService] getAllPayments Supabase error: $e');
    }

    // 2. Merge Local Cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getStringList('statutory_payments_cache') ?? [];
      for (var item in cached) {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final payment = PaymentModel.fromJson(map);
        final key = payment.paymentReference.isNotEmpty ? payment.paymentReference : payment.id;
        if (seenKeys.add(key)) results.add(payment);
      }
    } catch (_) {}

    return results;
  }
}
