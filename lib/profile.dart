import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:strict/monitor_service.dart';
import 'main.dart';
import 'package:flutter/services.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int avatarIndex = 2;

  Future<void> changePassword(BuildContext context) async {
    final currentPassC = TextEditingController();
    final newPassC = TextEditingController();
    final confirmPassC = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'change_password'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: currentPassC,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'current_password'.tr(),
                      ),
                      validator: (v) => v!.isEmpty ? 'required'.tr() : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: newPassC,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'new_password'.tr(),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'required'.tr();
                        final valid =
                            v.length >= 8 &&
                            !v.contains(' ') &&
                            v.contains(RegExp(r'[A-Za-z]')) &&
                            v.contains(RegExp(r'[0-9]')) &&
                            v.contains(RegExp(r'[!@#$]'));
                        if (!valid) return 'password_requirements'.tr();
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: confirmPassC,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'confirm_new_password'.tr(),
                      ),
                      validator: (v) => v != newPassC.text
                          ? 'passwords_dont_match'.tr()
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('cancel'.tr()),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      try {
                        final user = FirebaseAuth.instance.currentUser!;
                        final cred = EmailAuthProvider.credential(
                          email: user.email!,
                          password: currentPassC.text.trim(),
                        );
                        await user.reauthenticateWithCredential(cred);
                        await user.updatePassword(newPassC.text.trim());
                        // ignore: use_build_context_synchronously
                        Navigator.pop(ctx);
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('password_changed'.tr())),
                        );
                      } catch (e) {
                        // ignore: use_build_context_synchronously
                        Navigator.pop(ctx);
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${'error_prefix'.tr()}${e.toString()}',
                            ),
                          ),
                        );
                      }
                    },
                    child: Text('save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> changeDisplayName(BuildContext context) async {
    final nameC = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'change_display_name'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: formKey,
                child: TextFormField(
                  controller: nameC,
                  decoration: InputDecoration(
                    labelText: 'new_display_name'.tr(),
                  ),
                  validator: (v) => v!.trim().isEmpty ? 'required'.tr() : null,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('cancel'.tr()),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      try {
                        final uid = FirebaseAuth.instance.currentUser!.uid;
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .update({'displayName': nameC.text.trim()});
                        setState(() {});
                        // ignore: use_build_context_synchronously
                        Navigator.pop(ctx);
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('display_name_updated'.tr())),
                        );
                      } catch (e) {
                        // ignore: use_build_context_synchronously
                        Navigator.pop(ctx);
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${'error_prefix'.tr()}${e.toString()}',
                            ),
                          ),
                        );
                      }
                    },
                    child: Text('save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    return doc.data();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('profile'.tr()),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: getUserData(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data!;
          avatarIndex = userData['avatarIndex'] ?? avatarIndex;

          return SingleChildScrollView(
            child: Column(
              children: [
                // ─── Avatar Section ───
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  color: Theme.of(context).colorScheme.secondary,
                  child: Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundImage: AssetImage(
                            'assets/images/profile/$avatarIndex.jpg',
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () async {
                              int selectedAvatarIndex = avatarIndex;
                              await showGeneralDialog(
                                context: context,
                                barrierDismissible: true,
                                barrierLabel: "Select Avatar",
                                pageBuilder: (context, anim1, anim2) {
                                  return Align(
                                    alignment: Alignment.center,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Container(
                                        height:
                                            MediaQuery.of(context).size.height *
                                            0.25,
                                        margin: const EdgeInsets.all(16),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: StatefulBuilder(
                                          builder: (context, setStateDialog) {
                                            return Column(
                                              children: [
                                                Expanded(
                                                  flex: 8,
                                                  child: Column(
                                                    children: [
                                                      Expanded(
                                                        child: Row(
                                                          children: List.generate(4, (
                                                            index,
                                                          ) {
                                                            int imgIndex =
                                                                index + 2;
                                                            bool isSelected =
                                                                imgIndex ==
                                                                selectedAvatarIndex;
                                                            return Expanded(
                                                              child: GestureDetector(
                                                                onTap: () =>
                                                                    setStateDialog(
                                                                      () => selectedAvatarIndex =
                                                                          imgIndex,
                                                                    ),
                                                                child: Container(
                                                                  margin:
                                                                      const EdgeInsets.all(
                                                                        4,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    border:
                                                                        isSelected
                                                                        ? Border.all(
                                                                            color:
                                                                                Colors.white70,
                                                                            width:
                                                                                3,
                                                                          )
                                                                        : null,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          8,
                                                                        ),
                                                                  ),
                                                                  child: Image.asset(
                                                                    'assets/images/profile/$imgIndex.jpg',
                                                                    fit: BoxFit
                                                                        .cover,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          }),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Row(
                                                          children: List.generate(4, (
                                                            index,
                                                          ) {
                                                            int imgIndex =
                                                                index + 6;
                                                            bool isSelected =
                                                                imgIndex ==
                                                                selectedAvatarIndex;
                                                            return Expanded(
                                                              child: GestureDetector(
                                                                onTap: () =>
                                                                    setStateDialog(
                                                                      () => selectedAvatarIndex =
                                                                          imgIndex,
                                                                    ),
                                                                child: Container(
                                                                  margin:
                                                                      const EdgeInsets.all(
                                                                        4,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    border:
                                                                        isSelected
                                                                        ? Border.all(
                                                                            color:
                                                                                Colors.white70,
                                                                            width:
                                                                                3,
                                                                          )
                                                                        : null,
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          8,
                                                                        ),
                                                                  ),
                                                                  child: Image.asset(
                                                                    'assets/images/profile/$imgIndex.jpg',
                                                                    fit: BoxFit
                                                                        .cover,
                                                                  ),
                                                                ),
                                                              ),
                                                            );
                                                          }),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                            ),
                                                        child: Text(
                                                          'cancel'.tr(),
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                      TextButton(
                                                        onPressed: () async {
                                                          final uid =
                                                              FirebaseAuth
                                                                  .instance
                                                                  .currentUser!
                                                                  .uid;
                                                          await FirebaseFirestore
                                                              .instance
                                                              .collection(
                                                                'users',
                                                              )
                                                              .doc(uid)
                                                              .update({
                                                                'avatarIndex':
                                                                    selectedAvatarIndex,
                                                              });
                                                          setState(
                                                            () => avatarIndex =
                                                                selectedAvatarIndex,
                                                          );
                                                          Navigator.pop(
                                                            // ignore: use_build_context_synchronously
                                                            context,
                                                          );
                                                        },
                                                        child: Text(
                                                          'apply'.tr(),
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 16),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            child: Container(
                              height: 28,
                              width: 28,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── Info Section ───
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Display Name
                      _infoTile(
                        context,
                        label: 'profile_name'.tr(),
                        value: userData['displayName'] ?? '',
                      ),
                      const SizedBox(height: 16),

                      // Custom ID
                      _infoTileWithCopy(
                        context,
                        label: 'id_label'.tr(),
                        value: userData['customId'] ?? '',
                      ),
                      const SizedBox(height: 16),

                      // Email
                      _infoTile(
                        context,
                        label: 'email_label'.tr(),
                        value: FirebaseAuth.instance.currentUser?.email ?? '',
                      ),
                      const SizedBox(height: 32),

                      // Change Password
                      _actionTile(
                        context,
                        icon: Icons.lock_outline,
                        title: 'change_password'.tr(),
                        onTap: () => changePassword(context),
                      ),
                      const SizedBox(height: 12),

                      // Change Display Name
                      _actionTile(
                        context,
                        icon: Icons.person_outline,
                        title: 'change_display_name'.tr(),
                        onTap: () => changeDisplayName(context),
                      ),
                      const SizedBox(height: 32),

                      // Logout
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            await MonitorService.stopCaptureByLogout();
                            await FirebaseAuth.instance.signOut();
                            Navigator.pushAndRemoveUntil(
                              // ignore: use_build_context_synchronously
                              context,
                              MaterialPageRoute(builder: (_) => WelcomePage()),
                              (_) => false,
                            );
                          },
                          child: Text(
                            'logout'.tr(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            // ignore: deprecated_member_use
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const Divider(),
      ],
    );
  }

  Widget _infoTileWithCopy(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            // ignore: deprecated_member_use
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                if (value.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('id_copied'.tr()),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        const Divider(),
      ],
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
