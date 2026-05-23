import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

class MyMonitoringRequestsPage extends StatefulWidget {
  const MyMonitoringRequestsPage({super.key});

  @override
  State<MyMonitoringRequestsPage> createState() =>
      _MyMonitoringRequestsPageState();
}

class _MyMonitoringRequestsPageState extends State<MyMonitoringRequestsPage> {
  @override
  void initState() {
    super.initState();
    _markSeenByFrom();
  }

  Future<void> _markSeenByFrom() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('monitoring_requests')
        .where('fromUserId', isEqualTo: currentUser.uid)
        .where('seenByFrom', isEqualTo: false)
        .where('status', isEqualTo: 'rejected')
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

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('my_requests'.tr()),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: 'pending'.tr()),
              Tab(text: 'accepted'.tr()),
              Tab(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('monitoring_requests')
                      .where('fromUserId', isEqualTo: currentUser.uid)
                      .where('status', isEqualTo: 'rejected')
                      .where('seenByFrom', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final count = snapshot.data?.docs.length ?? 0;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Text('rejected'.tr()),
                        if (count > 0)
                          Positioned(
                            right: -14,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RequestsList(status: "pending"),
            _RequestsList(status: "accepted"),
            _RequestsList(status: "rejected"),
          ],
        ),
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  final String status;

  const _RequestsList({required this.status});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("monitoring_requests")
          .where("fromUserId", isEqualTo: currentUser.uid)
          .where("status", isEqualTo: status)
          .orderBy("createdAt", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'no_$status'.tr(),
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final requestData = requests[index].data() as Map<String, dynamic>;
            final toUserId = requestData['toUserId'];
            return _UserRequestItem(toUserId: toUserId);
          },
        );
      },
    );
  }
}

class _UserRequestItem extends StatelessWidget {
  final String toUserId;

  const _UserRequestItem({required this.toUserId});

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
                        userData['displayName'] ?? 'No name',
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
              ],
            ),
          ),
        );
      },
    );
  }
}
