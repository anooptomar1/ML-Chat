import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

// TODO: firebase for messages

final ThemeData kIOSTheme = new ThemeData(
  primarySwatch: Colors.lightBlue,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.lightBlue,
  accentColor: Colors.greenAccent[400],
);


final FirebaseAuth _auth = FirebaseAuth.instance;
final GoogleSignIn _googleSignIn = new GoogleSignIn();

Future<Null> _ensureLoggedIn() async {
  GoogleSignInAccount user = _googleSignIn.currentUser;
  if (user == null)
    user = await _googleSignIn.signInSilently();
  if (user == null)
    await _googleSignIn.signIn();
}

const String _name = "Rowan";

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
      home: new LoginScreen(),
      routes: <String, WidgetBuilder> {
        'login': (BuildContext context) => new LoginScreen(),
        'chat': (BuildContext context) => new ChatScreen(),
      }
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  State createState() => new LoginState();
}

class LoginState extends State<LoginScreen> {

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      body: new Center(
        child: new RaisedButton(onPressed: (() {
          Navigator.of(context).pushNamed('chat');
        }))
      )
    );
  }
}

class ChatScreen extends StatefulWidget {

  @override
  State createState() => new ChatState();
}

class ChatState extends State<ChatScreen> with TickerProviderStateMixin {

  final List<Message> _messages = <Message>[];

  Text input = new Text('');
  bool _isComposing = false;

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: new AppBar(
          title: new Text("ML Chat"),
          elevation: Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
        ),
        body: new Column(children: <Widget>[
          new Flexible(
              child: new ListView.builder(
                padding: new EdgeInsets.all(8.0),
                reverse: true,
                itemBuilder: (context , int index) => _messages[index],
                itemCount: _messages.length,
              )),
          new Divider(height: 1.0),
          new Container(
            decoration:
            new BoxDecoration(color: Theme.of(context).cardColor),
            child: _buildTextEntry(),
          ),
          new Divider(height: 1.0),
          new Container(
            height: 200.0, // TODO: put ml picker here
            decoration: new BoxDecoration(color: Theme.of(context).cardColor),
            child: new Center(
                child: new RaisedButton(
                    onPressed: ((){
                      setState(() {
                        input = new Text('${input.data}\$');
                        _isComposing = true; // TODO: remove this default behaviour
                      });
                    }))
            ),
          )
        ]));
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
    Message message = new Message(
      text: messageText,
      animationController: new AnimationController(
        duration: new Duration(milliseconds: 400),
        vsync: this,
      ),
    );
    setState(() {
      _messages.insert(0, message);
    });
    message.animationController.forward();
  }

  @override
  void dispose() {
    for (Message message in _messages)
      message.animationController.dispose();
    super.dispose();
  }
}

class Message extends StatelessWidget {
  Message({this.text, this.animationController});
  final String text;
  final AnimationController animationController;

  Widget build(BuildContext context) {
    return new SizeTransition(
      sizeFactor: new CurvedAnimation(
          parent: animationController, curve: Curves.easeOut),
      axisAlignment: 0.0,
      child: new Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            new Container(
              margin: const EdgeInsets.only(right: 16.0),
              child: new CircleAvatar(child: new Text(_name[0])),
            ),
            new Expanded(
              child: new Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  new Text(_name, style: Theme.of(context).textTheme.subhead),
                  new Container(
                    margin: const EdgeInsets.only(top: 5.0),
                    child: new Text(text),
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

