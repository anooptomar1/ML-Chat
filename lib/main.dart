import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';

final ThemeData kIOSTheme = new ThemeData(
  primarySwatch: Colors.lightBlue,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.lightBlue,
  accentColor: Colors.greenAccent[400],
);

final _googleSignIn = new GoogleSignIn();
final _auth = FirebaseAuth.instance;
final _analytics = new FirebaseAnalytics();
final _dataReference = FirebaseDatabase.instance.reference().child('messages');

Future<bool> _ensureLoggedIn() async {
  GoogleSignInAccount user = _googleSignIn.currentUser;
  if (user == null) user = await _googleSignIn.signInSilently();
  if (user == null) await _googleSignIn.signIn();

  if (await _auth.currentUser() == null) {
    GoogleSignInAuthentication credentials =
        await _googleSignIn.currentUser.authentication;
    await _auth.signInWithGoogle(
      idToken: credentials.idToken,
      accessToken: credentials.accessToken,
    );
  }
  return user != null;
}

void main() {
  runApp(new ChatApp());
}

class ChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
        title: "ML Chat",
        theme: defaultTargetPlatform == TargetPlatform.iOS
            ? kIOSTheme
            : kDefaultTheme,
        home: new ChatScreen(),
        routes: <String, WidgetBuilder>{
          'chat': (BuildContext context) => new ChatScreen(),
        });
  }
}

class ChatScreen extends StatefulWidget {
  @override
  State createState() => new ChatState();
}

class ChatState extends State<ChatScreen> {
  Text input = new Text('');
  bool _isComposing = false;

  @override
  Widget build(BuildContext context) {
    return new FutureBuilder(
        future: _ensureLoggedIn(),
        builder: (context, snapshot) {
          return new Scaffold(
              appBar: new AppBar(
                title: new Text("ML Chat"),
                elevation: Theme.of(context).platform == TargetPlatform.iOS
                    ? 0.0
                    : 4.0,
              ),
              body: new Column(children: <Widget>[
                snapshot.hasData
                    ? new Flexible(
                        child: new FirebaseAnimatedList(
                        query: _dataReference,
                        sort: (a, b) => b.key.compareTo(a.key),
                        padding: new EdgeInsets.all(8.0),
                        reverse: true,
                        itemBuilder: (_, DataSnapshot snapshot,
                            Animation<double> animation, someInt) {
                          return new Message(
                              snapshot: snapshot, animation: animation);
                        },
                      ))
                    : new Expanded(child: new Text('loading messages')),
                new Divider(height: 1.0),
                new Container(
                  decoration:
                      new BoxDecoration(color: Theme.of(context).cardColor),
                  child: _buildTextEntry(),
                ),
                new Divider(height: 1.0),
                new Container(
                  height: 200.0, // TODO: put ml picker here
                  decoration:
                      new BoxDecoration(color: Theme.of(context).cardColor),
                  child: new Center(
                      child: new RaisedButton(
                          child: new Text('\$'),
                          onPressed: (() {
                            setState(() {
                              input = new Text('${input.data}\$');
                              _isComposing =
                                  true; // TODO: remove this default behaviour
                            });
                            _analytics.logEvent(
                                name: 'placeholder_button_push');
                          }))),
                )
              ]));
        });
  }

  Widget _buildTextEntry() {
    return new IconTheme(
      data: new IconThemeData(color: Theme.of(context).accentColor),
      child: new Container(
          margin: const EdgeInsets.symmetric(horizontal: 8.0),
          child: new Row(children: <Widget>[
            new Expanded(
              child: input,
            ),
            new Container(
                margin: new EdgeInsets.symmetric(horizontal: 4.0),
                child: Theme.of(context).platform == TargetPlatform.iOS
                    ? new CupertinoButton(
                        child: new Text("Send"),
                        onPressed: _isComposing
                            ? () => _handleSubmitted(input.data)
                            : null,
                      )
                    : new IconButton(
                        icon: new Icon(Icons.send),
                        onPressed: _isComposing
                            ? () => _handleSubmitted(input.data)
                            : null,
                      )),
          ]),
          decoration: Theme.of(context).platform == TargetPlatform.iOS
              ? new BoxDecoration(
                  border:
                      new Border(top: new BorderSide(color: Colors.grey[200])))
              : null),
    );
  }

  void _handleSubmitted(String messageText) async {
    setState(() {
      input = new Text('');
      _isComposing = false;
    });
    await _ensureLoggedIn();
    _sendMessage(messageText);
  }

  void _sendMessage(String messageText) {
    _dataReference.push().set({
      'text': messageText,
      'senderName': _googleSignIn.currentUser.displayName,
      'senderPhotoUrl': _googleSignIn.currentUser.photoUrl,
    });
    _analytics.logEvent(name: 'message_send');
  }
}

class Message extends StatelessWidget {
  Message({this.snapshot, this.animation});
  final DataSnapshot snapshot;
  final Animation animation;

  Widget build(BuildContext context) {
    return new SizeTransition(
      sizeFactor: new CurvedAnimation(parent: animation, curve: Curves.easeOut),
      axisAlignment: 0.0,
      child: new Container(
        decoration: new BoxDecoration(
          color: _sentByThis()
              ? Theme.of(context).primaryColor
              : Colors.grey,
          borderRadius: new BorderRadius.circular(10.0)
        ),
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: new Padding(
            padding: EdgeInsets.all(5.0),
            child: new Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection:
                    _sentByThis() ? TextDirection.ltr : TextDirection.rtl,
                children: <Widget>[
                  new Container(
                    margin: _sentByThis()
                        ? const EdgeInsets.only(right: 16.0)
                        : const EdgeInsets.only(left: 16.0),
                    child: new CircleAvatar(
                        backgroundImage:
                            new NetworkImage(snapshot.value['senderPhotoUrl'])),
                    decoration: new BoxDecoration(
                      shape: BoxShape.circle,
                      border: new Border.all(color: Colors.grey),
                    ),
                  ),
                  new Expanded(
                    child: new Column(
                      crossAxisAlignment: _sentByThis()
                          ? CrossAxisAlignment.start
                          : CrossAxisAlignment.end,
                      children: <Widget>[
                        new Text(snapshot.value['senderName'],
                            style: Theme.of(context).textTheme.title),
                        new Container(
                          margin: const EdgeInsets.only(top: 5.0),
                          child: new Text(snapshot.value['text']),
                        ),
                      ],
                    ),
                  ),
                ])),
      ),
    );
  }

  bool _sentByThis() {
    GoogleSignInAccount user = _googleSignIn.currentUser;
    if (user == null) return false;
    return snapshot.value['senderName'] ==
        _googleSignIn.currentUser.displayName;
  }
}
