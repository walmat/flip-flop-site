import 'dart:async';

import 'package:angular2/core.dart';
import 'package:firebase/firebase.dart' as fb;

@Injectable()
class FirebaseService {
  fb.Auth _fbAuth;
  fb.GoogleAuthProvider _fbGoogleAuthProvider;
  fb.User user;


  FirebaseService() {
    fb.initializeApp(
        apiKey: "AIzaSyATvGSKHlPferK6JcwRzugNfaR38_xcbpI",
        authDomain: "flip-flop-7c02d.firebaseapp.com",
        databaseURL: "https://flip-flop-7c02d.firebaseio.com",
        storageBucket: "flip-flop-7c02d.appspot.com"
    );
    _fbGoogleAuthProvider = new fb.GoogleAuthProvider();
    _fbAuth = fb.auth();
    _fbAuth.onAuthStateChanged.listen(_authChanged);

  }

  Future signIn() async {
    try {
      await _fbAuth.signInWithPopup(_fbGoogleAuthProvider);
    }
    catch (error) {
      print("$runtimeType::login() -- $error");
    }
  }

  void signOut() {
    _fbAuth.signOut();
  }

  void _authChanged(fb.AuthEvent event) {
    user = event.user;
  }


}