import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:strict/log_file_page.dart';

class ReportsPage extends StatefulWidget {
  final String toUserId;
  final String displayName;
  final int avatarIndex;
  final String customId;

  final String relationDate;

  // أضف في constructor
  const ReportsPage({
    super.key,
    required this.toUserId,
    required this.displayName,
    required this.avatarIndex,
    required this.customId,
    required this.relationDate,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final ScrollController _scrollController = ScrollController();
  List<DocumentSnapshot> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection("users")
        .doc(currentUid)
        .collection("reports")
        .where("targetCustomId", isEqualTo: widget.customId)
        .where("reportDate", isGreaterThanOrEqualTo: widget.relationDate)
        .orderBy("reportDate", descending: false)
        .get();

    if (!mounted) return;
    setState(() {
      _reports = snap.docs;
      _loading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _reports.isEmpty
                ? Center(
                    child: Text(
                      'no_reports_yet'.tr(),
                      style: TextStyle(
                        // ignore: deprecated_member_use
                        color: Theme.of(
                          context,
                          // ignore: deprecated_member_use
                        ).colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) =>
                        _ReportBubble(doc: _reports[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          CircleAvatar(
            radius: 40,
            backgroundImage: AssetImage(
              'assets/images/profile/${widget.avatarIndex}.jpg',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            widget.customId,
            style: TextStyle(
              fontSize: 13,
              // ignore: deprecated_member_use
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 12),
          // ignore: deprecated_member_use
          Divider(
            height: 1,
            // ignore: deprecated_member_use
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          ),
        ],
      ),
    );
  }
}

class _ReportBubble extends StatefulWidget {
  final DocumentSnapshot doc;
  const _ReportBubble({required this.doc});

  @override
  State<_ReportBubble> createState() => _ReportBubbleState();
}

class _ReportBubbleState extends State<_ReportBubble> {
  bool _expanded = false;
  static const int _collapsedLines = 8;

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final reportText = data['reportText'] as String? ?? '';
    final logFileId = data['logFileId'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;

    final lines = reportText.split('\n');
    final isLong = lines.length > _collapsedLines;
    final displayedText = _expanded || !isLong
        ? reportText
        : lines.take(_collapsedLines).join('\n');

    String timeStr = '';
    if (createdAt != null) {
      timeStr = DateFormat('hh:mm a').format(createdAt.toDate());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayedText,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              fontFamily: 'monospace',
            ),
          ),

          if (isLong)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _expanded ? 'read_less'.tr() : 'read_more'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),

          if (logFileId.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ai_tip'.tr(),
                  style: TextStyle(
                    fontSize: 12,
                    // ignore: deprecated_member_use
                    color: Theme.of(
                      context,
                      // ignore: deprecated_member_use
                    ).colorScheme.primary.withOpacity(0.5),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LogFilePage(logFileId: logFileId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: Text('view_log_file'.tr()),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 8),

          if (timeStr.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  // ignore: deprecated_member_use
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
