import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'notification_service.dart';

class MonitoringRequestsPage extends StatefulWidget {
  const MonitoringRequestsPage({super.key});

  @override
  State<MonitoringRequestsPage> createState() => _MonitoringRequestsPageState();
}

class _MonitoringRequestsPageState extends State<MonitoringRequestsPage> {
  @override
  void initState() {
    super.initState();
    _markSeenByTo();
  }

  Future<void> _markSeenByTo() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('monitoring_requests')
        .where('toUserId', isEqualTo: currentUser.uid)
        .where('seenByTo', isEqualTo: false)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'seenByTo': true});
    }
    if (snapshot.docs.isNotEmpty) await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(body: Center(child: Text('not_authenticated'.tr())));
    }

    return Scaffold(
      appBar: AppBar(title: Text('requests'.tr()), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("monitoring_requests")
            .where("toUserId", isEqualTo: currentUser.uid)
            .where("status", isEqualTo: "pending")
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                'no_requests'.tr(),
                style: const TextStyle(color: Colors.grey),
              ),
            );
          }

          final requests = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final requestDoc = requests[index];
              final requestData = requestDoc.data() as Map<String, dynamic>;

              return _RequestItem(
                requestId: requestDoc.id,
                fromUserId: requestData['fromUserId'],
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestItem extends StatefulWidget {
  final String requestId;
  final String fromUserId;

  const _RequestItem({required this.requestId, required this.fromUserId});

  @override
  State<_RequestItem> createState() => _RequestItemState();
}

class _RequestItemState extends State<_RequestItem> {
  bool _loading = false;

  Future<void> _acceptRequest(String displayName) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final relationId = "${widget.fromUserId}_${currentUser.uid}";

    setState(() => _loading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.update(
        FirebaseFirestore.instance
            .collection("monitoring_requests")
            .doc(widget.requestId),
        {
          "status": "accepted",
          "acceptedAt": FieldValue.serverTimestamp(),
          "seenByFrom": false,
        },
      );

      batch.set(
        FirebaseFirestore.instance
            .collection("monitoring_relations")
            .doc(relationId),
        {
          "fromUserId": widget.fromUserId,
          "toUserId": currentUser.uid,
          "requestId": widget.requestId,
          "createdAt": FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();

      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final myName = myDoc.data()?['displayName'] ?? '';

      await NotificationService.sendNotification(
        toUserId: widget.fromUserId,
        title: {'en': 'Request Accepted', 'ar': 'تم قبول الطلب'},
        body: {
          'en': '$myName accepted your monitoring request',
          'ar': 'قبل $myName طلب المراقبة الخاص بك',
        },
        type: 'request_accepted',
      );
    } catch (e) {
      debugPrint("Accept error: $e");
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _rejectRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser!;

    try {
      await FirebaseFirestore.instance
          .collection("monitoring_requests")
          .doc(widget.requestId)
          .update({"status": "rejected", "seenByFrom": false});

      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final myName = myDoc.data()?['displayName'] ?? '';

      await NotificationService.sendNotification(
        toUserId: widget.fromUserId,
        title: {'en': 'Request Rejected', 'ar': 'تم رفض الطلب'},
        body: {
          'en': '$myName rejected your monitoring request',
          'ar': 'رفض $myName طلب المراقبة الخاص بك',
        },
        type: 'request_rejected',
      );
    } catch (e) {
      debugPrint("Reject error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection("users")
          .doc(widget.fromUserId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final displayName = userData['displayName'] ?? '';

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
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: _loading ? null : _rejectRequest,
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: _loading
                          ? null
                          : () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('accept_request'.tr()),
                                  content: Text('accept_confirm'.tr()),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text('cancel'.tr()),
                                    ),
                                    ElevatedButton(
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await _acceptRequest(displayName);
                                      },
                                      child: Text('accept'.tr()),
                                    ),
                                  ],
                                ),
                              );
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
