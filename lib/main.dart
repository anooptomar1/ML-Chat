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

User _currentUser;

Future<bool> _checkSignIn() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // backup
    // TODO: test on actual device and add actual email auth
    if (await _auth.currentUser() == null) {
      await _auth.signInWithEmailAndPassword(
          email: 'rwnlnsy@gmail.com', password: 'hughmungus');
    }
    if (_currentUser == null) {
      _currentUser = new User(name: 'Dumb iOS user');
    }
  } else {
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
    if (_currentUser == null) {
      _currentUser = new User(
          name: _googleSignIn.currentUser.displayName,
          photoUrl: _googleSignIn.currentUser.photoUrl);
    }
  }
  return true;
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
        future: _checkSignIn(),
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
                    : new Expanded(
                        child: snapshot.hasError
                            ? new Text('error signing in: ${snapshot.error}')
                            : new Text('loading messages')),
                new Divider(height: 1.0),
                new Container(
                  decoration:
                      new BoxDecoration(color: Theme.of(context).cardColor),
                  child: _buildTextEntry(),
                ),
                new Divider(height: 1.0),
                new DefaultTabController(
                    length: 2,
                    child: new Container(
                        height: 200.0,
                        decoration: new BoxDecoration(
                            color: Theme.of(context).cardColor),
                        child: new Column(
                          children: <Widget>[
                            new Expanded(
                                child: new TabBarView(children: [
                              _buildMLButton(
                                  type: 'object',
                                  platform: Theme.of(context).platform),
                              _buildMLButton(
                                  type: 'text',
                                  platform: Theme.of(context).platform)
                            ]))
                          ],
                        ))),
              ]));
        });
  }

  Widget _buildMLButton({type, platform}) {
    Icon icon =
        type == 'object' ? new Icon(Icons.image) : new Icon(Icons.title);
    Text label = type == 'object'
        ? new Text('Find an Object')
        : new Text('Find Some Text');
    Widget buttonBody = new Center(
        child: new Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        new Padding(padding: new EdgeInsets.all(10.0), child: icon),
        label
      ],
    ));
    var onPress = (() {
      setState(() {
        input = new Text('${input.data}\$');
        _isComposing = true; // TODO: remove this default behaviour
      });
      _analytics.logEvent(name: 'placeholder_button_push');
    });

    return platform == TargetPlatform.iOS
        ? new CupertinoButton(child: buttonBody, onPressed: onPress)
        : new RaisedButton(child: buttonBody, onPressed: onPress);
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
    await _checkSignIn();
    _sendMessage(messageText);
  }

  void _sendMessage(String messageText) {
    _dataReference.push().set({
      'text': messageText,
      'senderName': _currentUser.name,
      'senderPhotoUrl': _currentUser.photoUrl,
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
                      backgroundImage: snapshot.value['senderPhotoUrl'] != null
                          ? new NetworkImage(snapshot.value['senderPhotoUrl'])
                          : null,
                      child: snapshot.value['senderPhotoUrl'] == null
                          ? new Text((snapshot.value['senderName'])[0])
                          : null,
                    ),
                    decoration: new BoxDecoration(
                      shape: BoxShape.circle,
                      border: new Border.all(color: Colors.grey),
                    ),
                  ),
                  new Expanded(
                    child: new Container(
                        decoration: new BoxDecoration(
                            color: _sentByThis()
                                ? Theme.of(context).primaryColor
                                : Theme.of(context).accentColor,
                            borderRadius: new BorderRadius.circular(10.0)),
                        child: new Padding(
                            padding: new EdgeInsets.all(5.0),
                            child: new Column(
                              crossAxisAlignment: _sentByThis()
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.end,
                              children: <Widget>[
                                new Text(
                                  snapshot.value['text'],
                                  style: _getMessageStyle(context),
                                ),
                                /* Sender Name Label
                                new Container(
                                  margin: const EdgeInsets.only(top: 5.0),
                                  child: new Text(
                                    snapshot.value['senderName'],
                                    style: _getMessageStyle(context),
                                  ),
                                )
                                */
                              ],
                            ))),
                  ),
                ])),
      ),
    );
  }

  bool _sentByThis() {
    if (_currentUser == null) return false;
    return snapshot.value['senderName'] == _currentUser.name;
  }

  TextStyle _getMessageStyle(BuildContext context) {
    //white on dark or black on light
    if (((Theme.of(context).platform == TargetPlatform.android) &&
            _sentByThis()) ||
        ((Theme.of(context).platform == TargetPlatform.iOS) &&
            !_sentByThis())) {
      return new TextStyle(color: Colors.white);
    }
    return null;
  }
}

class User {
  final String name;
  final String photoUrl;

  User({this.name, this.photoUrl});
}
