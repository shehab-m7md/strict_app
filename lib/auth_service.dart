import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _db = FirebaseFirestore.instance;




Future<String?> signUp({
  required String email,
  required String password,
  required String displayName,
  required String customId,
}) async {
  try {
    UserCredential userCred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User user = userCred.user!;
    await user.sendEmailVerification();

    await _db.collection("users").doc(user.uid).set({
      "email": email,
      "displayName": displayName,
      "customId": customId,
      "createdAt": FieldValue.serverTimestamp(),
    });

    return "done";
  } catch (e) {
    return e.toString();
  }
}
