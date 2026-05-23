import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static const _appId = "###################";
  static const _apiKey =
      "#############################################";

  static Future<void> sendNotification({
    required String toUserId,
    required Map<String, String> title,
    required Map<String, String> body,
    String type = '',
  }) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(toUserId)
        .get();
    final locale = userDoc.data()?['appLocale'] ?? 'en';

    final localizedTitle = title[locale] ?? title['en'] ?? '';
    final localizedBody = body[locale] ?? body['en'] ?? '';

    final Map<String, dynamic> payload = {
      "app_id": _appId,
      "include_aliases": {
        "external_id": [toUserId],
      },
      "target_channel": "push",
      "headings": {"en": localizedTitle},
      "contents": {"en": localizedBody},
      "android_small_icon": "ic_notification",
      if (type.isNotEmpty) "data": {"type": type},
    };

    await http.post(
      Uri.parse("https://onesignal.com/api/v1/notifications"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Basic $_apiKey",
      },
      body: jsonEncode(payload),
    );
  }
}
