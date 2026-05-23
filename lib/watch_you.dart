import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'notification_service.dart';

class WatchYouPage extends StatelessWidget {
  const WatchYouPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(body: Center(child: Text('not_authenticated'.tr())));
    }

    return Scaffold(
      appBar: AppBar(title: Text('watch_you'.tr()), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("monitoring_relations")
            .where("toUserId", isEqualTo: currentUser.uid)
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'no_users_yet'.tr(),
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }

          final relations = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: relations.length,
            itemBuilder: (context, index) {
              final relationDoc = relations[index];
              final data = relationDoc.data() as Map<String, dynamic>;

              return _UserRelationItem(
                userId: data['fromUserId'],
                createdAt: data['createdAt'] as Timestamp?,
                relationId: relationDoc.id,
                requestId: data['requestId'] ?? '',
              );
            },
          );
        },
      ),
    );
  }
}

class _UserRelationItem extends StatelessWidget {
  final String userId;
  final Timestamp? createdAt;
  final String relationId;
  final String requestId;

  const _UserRelationItem({
    required this.userId,
    required this.relationId,
    required this.requestId,
    this.createdAt,
  });
  Future<void> _sendMonitoringRequest(
    BuildContext context,
    String targetId,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final db = FirebaseFirestore.instance;

    // تحقق من relation موجودة
    final relDoc = await db
        .collection('monitoring_relations')
        .doc('${currentUser.uid}_$targetId')
        .get();
    if (relDoc.exists) {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text('already_monitoring'.tr())));
      return;
    }

    // تحقق من request موجود
    final docId = '${currentUser.uid}_$targetId';
    final docRef = db.collection('monitoring_requests').doc(docId);
    final reqDoc = await docRef.get();

    if (reqDoc.exists) {
      final status = reqDoc.data()?['status'];
      if (status == 'pending') {
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text('request_already_pending'.tr())));
        return;
      }
      if (status == 'accepted') {
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text('request_accepted'.tr())));
        return;
      }
      if (status == 'rejected') {
        final resend = await showDialog<bool>(
          // ignore: use_build_context_synchronously
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('request_rejected_before'.tr()),
            content: Text('resend_request_confirm'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('cancel'.tr()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('resend'.tr()),
              ),
            ],
          ),
        );
        if (resend != true) return;
        await docRef.delete();
      }
    }

    // ابعت الطلب
    await docRef.set({
      'fromUserId': currentUser.uid,
      'toUserId': targetId,
      'status': 'pending',
      'type': 'monitoring',
      'createdAt': FieldValue.serverTimestamp(),
      'seenByTo': false,
      'seenByFrom': true,
    });

    // ابعت notification
    try {
      final myDoc = await db.collection('users').doc(currentUser.uid).get();
      final myName = myDoc.data()?['displayName'] ?? '';

      await NotificationService.sendNotification(
        toUserId: targetId,
        title: {'en': 'New Monitoring Request', 'ar': 'طلب مراقبة جديد'},
        body: {
          'en': '$myName wants to monitor your device',
          'ar': '$myName يريد مراقبة جهازك',
        },
        type: 'incoming_request',
      );
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('request_sent'.tr())));
    }
  }

  Future<void> _deleteRelation(BuildContext context, String displayName) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final isSelf = userId == currentUser.uid;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isSelf ? 'remove_self_watcher'.tr() : 'remove_watcher'.tr(),
        ),
        content: Text(
          isSelf
              ? 'remove_self_watcher_confirm'.tr(
                  namedArgs: {'name': displayName},
                )
              : 'remove_watcher_confirm'.tr(namedArgs: {'name': displayName}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              'remove'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;

      final batch = FirebaseFirestore.instance.batch();

      batch.delete(
        FirebaseFirestore.instance
            .collection("monitoring_relations")
            .doc(relationId),
      );

      if (requestId.isNotEmpty) {
        batch.delete(
          FirebaseFirestore.instance
              .collection("monitoring_requests")
              .doc(requestId),
        );
      }

      await batch.commit();

      // ─── notification للمراقِب ───
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final myName = myDoc.data()?['displayName'] ?? '';

      await NotificationService.sendNotification(
        toUserId: userId,
        title: {'en': 'Removed as Watcher', 'ar': 'تمت إزالتك كمراقب'},
        body: {
          'en': '$myName removed you from their watchers',
          'ar': 'أزالك $myName من قائمة المراقبين',
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${'error_prefix'.tr()}$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection("users").doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final displayName = userData['displayName'] ?? '';

        String formattedDate = '';
        if (createdAt != null) {
          formattedDate = DateFormat.yMMMd(
            context.locale.toString(),
          ).add_Hm().format(createdAt!.toDate());
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: Theme.of(context).colorScheme.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: AssetImage(
                    'assets/images/profile/${userData['avatarIndex'] ?? 2}.jpg',
                  ),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userData['customId'] ?? '',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (formattedDate.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'since'.tr(namedArgs: {'date': formattedDate}),
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.grey),
                  onPressed: () => _deleteRelation(context, displayName),
                ),
                IconButton(
                  icon: Stack(
                    children: [
                      Icon(Icons.remove_red_eye, color: Colors.grey, size: 28),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Icon(Icons.add, color: Colors.green, size: 18),
                      ),
                    ],
                  ),
                  onPressed: () => _sendMonitoringRequest(context, userId),
                  tooltip: 'send_monitoring_request'.tr(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
