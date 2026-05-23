import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'reports_page.dart';

class WatchedUsersPage extends StatelessWidget {
  const WatchedUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("monitoring_relations")
          .where("fromUserId", isEqualTo: currentUser.uid)
          .orderBy("createdAt", descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'when_you_watch'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                // ignore: deprecated_member_use
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                fontSize: 16,
              ),
            ),
          );
        }

        final relations = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: relations.length,
          itemBuilder: (context, index) {
            final data = relations[index].data() as Map<String, dynamic>;
            final toUserId = data['toUserId'] as String;
            final relationCreatedAt = data['createdAt'] as Timestamp?;

            return _WatchedUserCard(
              toUserId: toUserId,
              relationCreatedAt: relationCreatedAt,
            );
          },
        );
      },
    );
  }
}

class _WatchedUserCard extends StatefulWidget {
  final String toUserId;
  final Timestamp? relationCreatedAt;

  const _WatchedUserCard({
    required this.toUserId,
    required this.relationCreatedAt,
  });

  @override
  State<_WatchedUserCard> createState() => _WatchedUserCardState();
}

class _WatchedUserCardState extends State<_WatchedUserCard> {
  String _displayName = '';
  int _avatarIndex = 2;
  String _customId = '';
  String _previewText = '';
  int _badgeCount = 0;
  bool _loading = true;
  List<QueryDocumentSnapshot> _reportDocs = [];

  String get _relationDate {
    if (widget.relationCreatedAt == null) return '2000-01-01';
    final d = widget.relationCreatedAt!.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    final userSnap = await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.toUserId)
        .get();

    if (!userSnap.exists) return;
    final userData = userSnap.data() as Map<String, dynamic>;
    _displayName = userData['displayName'] ?? '';
    _avatarIndex = userData['avatarIndex'] ?? 2;
    _customId = userData['customId'] ?? '';

    final reportsSnap = await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUid)
        .collection("reports")
        .where("targetCustomId", isEqualTo: _customId)
        .where("reportDate", isGreaterThanOrEqualTo: _relationDate)
        .orderBy("reportDate", descending: true)
        .get();

    _reportDocs = reportsSnap.docs;

    if (_reportDocs.isNotEmpty) {
      _previewText = (_reportDocs.first.get('reportText') as String? ?? '')
          .split('\n')
          .first
          .trim();
    }

    final prefs = await SharedPreferences.getInstance();
    final lastSeen =
        prefs.getString('last_seen_${widget.toUserId}') ?? '2000-01-01';
    final effectiveDate = lastSeen.compareTo(_relationDate) > 0
        ? lastSeen
        : _relationDate;

    _badgeCount = _reportDocs
        .where(
          (d) =>
              (d.get('reportDate') as String? ?? '').compareTo(effectiveDate) >
              0,
        )
        .length;

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _updateLastSeen() async {
    if (_reportDocs.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final latestDate = _reportDocs.first.get('reportDate') as String? ?? '';
    if (latestDate.isNotEmpty) {
      await prefs.setString('last_seen_${widget.toUserId}', latestDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 72);

    return GestureDetector(
      onTap: () async {
        await _updateLastSeen();
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReportsPage(
                toUserId: widget.toUserId,
                displayName: _displayName,
                avatarIndex: _avatarIndex,
                customId: _customId,
                relationDate: _relationDate,
              ),
            ),
          );
        }
      },
      onLongPress: () => _showDeleteDialog(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: AssetImage(
                    'assets/images/profile/$_avatarIndex.jpg',
                  ),
                ),
                if (_badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        '$_badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  if (_previewText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _previewText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(
                          context,
                        // ignore: deprecated_member_use
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete_chat'.tr()),
        content: Text(
          'delete_chat_confirm'.tr(namedArgs: {'name': _displayName}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final docs = await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUid)
        .collection("reports")
        .where("targetCustomId", isEqualTo: _customId)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
