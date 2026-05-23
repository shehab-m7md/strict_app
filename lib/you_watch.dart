import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'notification_service.dart';

class YouWatchPage extends StatefulWidget {
  const YouWatchPage({super.key});

  @override
  State<YouWatchPage> createState() => _YouWatchPageState();
}

class _YouWatchPageState extends State<YouWatchPage> {
  @override
  void initState() {
    super.initState();
    _markAcceptedSeen();
  }

  Future<void> _markAcceptedSeen() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('monitoring_requests')
        .where('fromUserId', isEqualTo: currentUser.uid)
        .where('seenByFrom', isEqualTo: false)
        .where('status', isEqualTo: 'accepted')
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'seenByFrom': true});
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
      appBar: AppBar(title: Text('you_watch'.tr()), centerTitle: true),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("monitoring_relations")
            .where("fromUserId", isEqualTo: currentUser.uid)
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

              return _WatchedUserItem(
                toUserId: data['toUserId'],
                createdAt: data['createdAt'],
                relationId: relationDoc.id,
                requestId: data['requestId'] ?? '',
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.secondary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchUserPage()),
          );
        },
        child: Stack(
          children: [
            Icon(
              Icons.remove_red_eye,
              color: Theme.of(context).colorScheme.onSurface,
              size: 28,
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Icon(Icons.add, color: Colors.green, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchedUserItem extends StatelessWidget {
  final String toUserId;
  final Timestamp? createdAt;
  final String relationId;
  final String requestId;

  const _WatchedUserItem({
    required this.toUserId,
    required this.createdAt,
    required this.relationId,
    required this.requestId,
  });

  String _formatDate(BuildContext context, Timestamp? timestamp) {
    if (timestamp == null) return "";
    final date = timestamp.toDate();
    return DateFormat.yMMMd(context.locale.toString()).add_Hm().format(date);
  }

  Future<void> _deleteRelation(BuildContext context, String displayName) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final isSelf = toUserId == currentUser.uid;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSelf ? 'remove_self_watched'.tr() : 'stop_watching'.tr()),
        content: Text(
          isSelf
              ? 'remove_self_watched_confirm'.tr()
              : 'stop_watching_confirm'.tr(namedArgs: {'name': displayName}),
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
              'stop'.tr(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.delete(
        FirebaseFirestore.instance
            .collection("monitoring_relations")
            .doc(relationId),
      );

      if (requestId.isNotEmpty && requestId != 'null') {
        try {
          final reqDoc = await FirebaseFirestore.instance
              .collection("monitoring_requests")
              .doc(requestId)
              .get();
          if (reqDoc.exists) {
            batch.delete(reqDoc.reference);
          }
        } catch (_) {}
      }

      await batch.commit();

      try {
        final myDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final myName = myDoc.data()?['displayName'] ?? '';

        await NotificationService.sendNotification(
          toUserId: toUserId,
          title: {'en': 'Monitoring Stopped', 'ar': 'توقفت المراقبة'},
          body: {
            'en': '$myName stopped watching you',
            'ar': 'أوقف $myName مراقبتك',
          },
        );
      } catch (_) {}
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
      future: FirebaseFirestore.instance
          .collection("users")
          .doc(toUserId)
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
                      const SizedBox(height: 4),
                      Text(
                        _formatDate(context, createdAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.grey),
                  onPressed: () => _deleteRelation(context, displayName),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SearchUserPage extends StatefulWidget {
  const SearchUserPage({super.key});

  @override
  State<SearchUserPage> createState() => _SearchUserPageState();
}

class _SearchUserPageState extends State<SearchUserPage> {
  final TextEditingController searchController = TextEditingController();

  bool loading = false;
  Map<String, dynamic>? userData;
  String? searchedCustomId;
  String? error;
  String? statusMessage;
  bool showResendButton = false;
  String? warningMessage;

  Future<void> searchUser() async {
    setState(() {
      loading = true;
      error = null;
      userData = null;
      statusMessage = null;
      showResendButton = false;
    });

    final customId = searchController.text.trim();

    if (customId.isEmpty) {
      setState(() {
        loading = false;
        error = 'enter_custom_id'.tr();
      });
      return;
    }

    try {
      final customIdDoc = await FirebaseFirestore.instance
          .collection('custom_ids')
          .doc(customId)
          .get();

      if (!customIdDoc.exists) {
        setState(() {
          loading = false;
          error = 'user_not_found'.tr();
        });
        return;
      }

      final uid = customIdDoc.data()!['uid'] as String;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        setState(() {
          loading = false;
          error = 'user_data_not_found'.tr();
        });
        return;
      }

      final map = userDoc.data()!;
      map['uid'] = uid;

      setState(() {
        userData = map;
        searchedCustomId = customId;
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = '${'something_went_wrong'.tr()}: $e';
      });
    }
  }

  Future<void> sendRequest({required bool isResend}) async {
    if (userData == null) return;

    setState(() {
      statusMessage = 'sending_request'.tr();
      warningMessage = null;
      showResendButton = false;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final toUserId = userData!['uid'] as String?;

      if (currentUser == null) {
        setState(() => statusMessage = 'not_authenticated'.tr());
        return;
      }

      if (toUserId == null || toUserId.isEmpty) {
        setState(() => statusMessage = 'user_id_not_found'.tr());
        return;
      }

      final bool isOwnDevice = currentUser.uid == toUserId;

      final docId = "${currentUser.uid}_$toUserId";

      final docRef = FirebaseFirestore.instance
          .collection("monitoring_requests")
          .doc(docId);

      final docSnapshot = await docRef.get();

      if (docSnapshot.exists && !isResend) {
        final status = docSnapshot.data()?['status'] ?? 'unknown';

        if (status == 'pending') {
          setState(() {
            statusMessage = 'request_pending'.tr();

            if (isOwnDevice) {
              warningMessage = 'own_device'.tr();
            }
          });
          return;
        } else if (status == 'accepted') {
          setState(() {
            statusMessage = 'request_accepted'.tr();

            if (isOwnDevice) {
              warningMessage = 'own_device'.tr();
            }
          });
          return;
        } else if (status == 'rejected') {
          setState(() {
            statusMessage = 'request_rejected'.tr();

            if (isOwnDevice) {
              warningMessage = 'own_device'.tr();
            }

            showResendButton = true;
          });
          return;
        } else {
          setState(() {
            statusMessage = 'something_went_wrong'.tr();

            if (isOwnDevice) {
              warningMessage = 'own_device'.tr();
            }
          });
          return;
        }
      }

      if (isResend) await docRef.delete();

      await docRef.set({
        "fromUserId": currentUser.uid,
        "toUserId": toUserId,
        "type": "monitor",
        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
        "seenByTo": false,
        "seenByFrom": true,
      });

      try {
        final myDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        final myName = myDoc.data()?['displayName'] ?? '';

        await NotificationService.sendNotification(
          toUserId: toUserId,
          title: {'en': 'New Monitoring Request', 'ar': 'طلب مراقبة جديد'},
          body: {
            'en': '$myName wants to monitor your device',
            'ar': '$myName يريد مراقبة جهازك',
          },
          type: 'incoming_request',
        );
      } catch (_) {}

      if (mounted) {
        setState(() {
          statusMessage = isResend
              ? 'request_resent'.tr()
              : 'request_sent'.tr();

          if (isOwnDevice) {
            warningMessage = 'own_device'.tr();
          }

          showResendButton = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          statusMessage = '${'error_prefix'.tr()}$e';
          warningMessage = null;
          showResendButton = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('search_user'.tr()), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'enter_custom_id'.tr(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: searchUser,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => searchUser(),
            ),
            const SizedBox(height: 24),

            if (loading) const CircularProgressIndicator(),

            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),

            if (userData != null)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage: AssetImage(
                          'assets/images/profile/${userData!['avatarIndex'] ?? 2}.jpg',
                        ),
                      ),
                      title: Text(userData!['displayName'] ?? ''),
                      subtitle: Text(userData!['customId'] ?? ''),
                      trailing: IconButton(
                        icon: Stack(
                          children: [
                            Icon(
                              Icons.remove_red_eye,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 28,
                            ),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Icon(
                                Icons.add,
                                color: Colors.green,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        onPressed: () => sendRequest(isResend: false),
                        tooltip: 'send_monitoring_request'.tr(),
                      ),
                    ),
                    if (statusMessage != null || warningMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (statusMessage != null)
                              Text(
                                statusMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.blue),
                              ),

                            if (warningMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  warningMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                            if (showResendButton)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: ElevatedButton(
                                  onPressed: () => sendRequest(isResend: true),
                                  child: Text('resend_request'.tr()),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
