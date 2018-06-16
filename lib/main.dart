import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:mlkit/mlkit.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

final ThemeData kIOSTheme = new ThemeData(
  primarySwatch: Colors.lightBlue,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.lightBlue,
  accentColor: Colors.greenAccent[400],
);

List<CameraDescription> cameras;

final _googleSignIn = new GoogleSignIn();
final _auth = FirebaseAuth.instance;
final _analytics = new FirebaseAnalytics();
final _usersRef = FirebaseDatabase.instance.reference().child('users');

User _currentUser;

Future<bool> _checkSignIn() async {
  String name, email, photoUrl, userKey;

  // CHECK SIGN_IN

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // backup
    // TODO: test on actual device and add actual email auth
    if (await _auth.currentUser() == null) {
      await _auth.signInWithEmailAndPassword(
          email: 'rwnlnsy@gmail.com', password: 'hughmungus');
    }

    name = 'Dumb iOS user';
    email = 'rwnlnsy@gmail.com';
    photoUrl = null;
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
    name = _googleSignIn.currentUser.displayName;
    email = _googleSignIn.currentUser.email;
    photoUrl = _googleSignIn.currentUser.photoUrl;
  }

  // UPDATE USERS DATABASE

  DataSnapshot snapshot =
      await _usersRef.orderByChild('email').equalTo(email).once();
  if (snapshot.value == null) {
    var newRef = _usersRef.push();
    newRef.set({
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'godMode': false,
    });
    userKey = newRef.key;
  } else {
    Map children = snapshot.value;
    for (var key in children.keys) {
      userKey = key; // assumes that there is one item matching email
    }
  }

  DataSnapshot userSnapshot = await FirebaseDatabase.instance
      .reference()
      .child('users/$userKey')
      .once();
  Map userData = userSnapshot.value;

  // SET CURRENT USER

  if (_currentUser == null) {
    _currentUser = new User(
        name: name,
        email: email,
        photoUrl: photoUrl,
        userKey: userKey,
        godMode: userData['godMode']);
  }

  return _auth.currentUser() != null;
}

Future<Null> main() async {
  cameras = await availableCameras();
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
      home: new ConversationScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  ChatScreen({this.conversation}) : super();

  @override
  State createState() => new ChatState();
}

class ChatState extends State<ChatScreen> {
  Input input; //bottom entity including keyboard and field

  ChatState() : super() {
    input = new Input(chatState: this);
  }

  @override
  Widget build(BuildContext context) {
    return new FutureBuilder(
        future: _checkSignIn(),
        builder: (context, snapshot) {
          return new Scaffold(
              appBar: new AppBar(
                title: new Text(widget.conversation.name),
                elevation: Theme.of(context).platform == TargetPlatform.iOS
                    ? 0.0
                    : 4.0,
              ),
              body: new Column(children: <Widget>[
                new Text(snapshot.hasData
                    ? 'user: ${_currentUser.userKey}'
                    : 'user not signed in'),
                snapshot.hasData
                    ? new Flexible(
                        child: new FirebaseAnimatedList(
                        query: FirebaseDatabase.instance.reference().child(
                            'groups/${widget.conversation.groupID}/messages'),
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
                            ? new LoadingScreen(
                                message: 'error signing in: ${snapshot.error}')
                            : new LoadingScreen(message: 'loading messages')),
                input,
              ]));
        });
  }
}

class Input extends StatefulWidget {
  ChatState chatState;

  Input({this.chatState}) : super();

  @override
  State<StatefulWidget> createState() => new InputState();
}

enum KeyboardState { chooser, words}

class InputState extends State<Input> {
  final TextEditingController _textController = new TextEditingController();
  List<String> words;

  Text inputText = new Text('');
  bool _isComposing = false;

  @override
  Widget build(BuildContext context) {
    return new Container(
        child: new Column(
      children: <Widget>[
        new Divider(height: 1.0),
        new Container(
          decoration: new BoxDecoration(color: Theme.of(context).cardColor),
          child: buildEntryRow(context),
        ),
        new Divider(height: 1.0),
        buildKeyboard(context),
      ],
    ));
  }

  Widget buildEntryRow(BuildContext context) {
    return new IconTheme(
      data: new IconThemeData(color: Theme.of(context).accentColor),
      child: new Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        child: new Row(children: <Widget>[
          buildTextField(context),
          new Container(
              margin: new EdgeInsets.symmetric(horizontal: 4.0),
              child: Theme.of(context).platform == TargetPlatform.iOS
                  ? new CupertinoButton(
                      child: new Text("Send"),
                      onPressed: _isComposing ? () => _handleSubmitted() : null,
                    )
                  : new IconButton(
                      icon: new Icon(Icons.send),
                      onPressed: _isComposing ? () => _handleSubmitted() : null,
                    )),
        ]),
      ),
    );
  }

  Widget buildTextField(BuildContext context) {
    if (_currentUser.godModeOn) {
      return new Flexible(
          child: new TextField(
        controller: _textController,
        onChanged: ((text) {
          setState(() {
            _isComposing = text.length > 0;
          });
        }),
        onSubmitted: (text) => _handleSubmitted,
        decoration: new InputDecoration.collapsed(hintText: "Send a message"),
      ));
    }

    return new Expanded(
      child: _isComposing
          ? inputText
          : new Text(
              'Send a message',
              style: new TextStyle(color: Colors.grey),
            ),
    );
  }

  void enterText(String text) {
    setState(() {
      inputText = new Text('${inputText.data} $text'); //includes a space
      _isComposing = inputText.data.length > 0;
    });
  }

  _handleSubmitted() async {
    String toSend = getDataToSend();
    _textController.clear();
    setState(() {
      inputText = new Text('');
      _isComposing = false;
    });
    await _checkSignIn();
    _sendMessage(toSend);
  }

  void _sendMessage(String messageText) {
    FirebaseDatabase.instance
        .reference()
        .child(
            'groups/${widget.chatState.widget.conversation.groupID}/messages')
        .push()
        .set({
      'text': messageText,
      'senderName': _currentUser.name,
      'senderPhotoUrl': _currentUser.photoUrl,
      'senderID': _currentUser.userKey,
    });
    _analytics.logEvent(name: 'message_send');
  }

  String getDataToSend() {
    if (_currentUser.godModeOn) {
      return _textController.text;
    } else {
      return inputText.data;
    }
  }

  // KEYBOARD

  KeyboardState state = KeyboardState.chooser;

  @override
  Widget buildKeyboard(BuildContext context) {
    if (!_currentUser.godModeOn) {
      switch (state) {
        case KeyboardState.chooser:
          return new DefaultTabController(
              length: 2,
              child: new Container(
                  height: 200.0,
                  decoration:
                      new BoxDecoration(color: Theme.of(context).cardColor),
                  child: new Column(
                    children: <Widget>[
                      new Expanded(
                          child: new TabBarView(children: [
                        _buildMLButton(
                            type: visionProcessMode.object,
                            platform: Theme.of(context).platform),
                        _buildMLButton(
                            type: visionProcessMode.text, platform: Theme.of(context).platform)
                      ]))
                    ],
                  )));
          break;
        case KeyboardState.words:
          return new Container(
              height: 200.0,
              child: new Column(
                children: <Widget>[
                  new Align(
                      alignment: Alignment.centerRight,
                      child: new IconButton(
                          icon: new Icon(Icons.close),
                          onPressed: (() {
                            setState(() {
                              state = KeyboardState.chooser;
                            });
                          }))),
                  new Expanded(child: (words != null) ?
                  new Text(words.toString()) : new Container())
                ],
              ));
          break;
      }
    }
    return new Container();
  }

  Widget _buildMLButton({type, platform}) {
    Icon icon =
        type == visionProcessMode.object ? new Icon(Icons.image) : new Icon(Icons.title);
    Text label = type == visionProcessMode.object
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

      _analytics.logEvent(name: 'ml_getter_button_push');

      mode = type; //mode setter

      showDialog(context: context,
          builder: ((context) => new VisionView())).then((wordsData) { setState(() {
            words = wordsData;
            state = KeyboardState.words;
          });});

    });

    return platform == TargetPlatform.iOS
        ? new CupertinoButton(child: buttonBody, onPressed: onPress)
        : new RaisedButton(child: buttonBody, onPressed: onPress);
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
                  ),
                  new Expanded(
                    child: new Container(
                        decoration: new BoxDecoration(
                            color: _sentByThis()
                                ? Theme.of(context).primaryColor
                                : Theme.of(context).platform ==
                                        TargetPlatform.iOS
                                    ? Theme.of(context).accentColor
                                    : Colors.grey[100],
                            borderRadius: new BorderRadius.circular(14.0)),
                        child: new Padding(
                            padding: new EdgeInsets.all(8.0),
                            child: new Column(
                              crossAxisAlignment: _sentByThis()
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.end,
                              children: <Widget>[
                                new Text(
                                  snapshot.value['text'],
                                  style: _getMessageStyle(context),
                                ),
                              ],
                            ))),
                  ),
                ])),
      ),
    );
  }

  bool _sentByThis() {
    if (_currentUser == null) return false;
    return snapshot.value['senderID'] == _currentUser.userKey;
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
  final String name, email, photoUrl, userKey;
  final bool godMode;
  bool godModeOn;

  User({this.name, this.email, this.photoUrl, this.userKey, this.godMode}) {
    godModeOn = godMode;
  }

  toggleGodMode() {
    if (godMode) {
      godModeOn = !godModeOn;
    }
  }
}

class ConversationScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => new ConversationsState();
}

class ConversationsState extends State<ConversationScreen> {
  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('ML Chat'),
        actions: <Widget>[
          new IconButton(
            icon: new Icon(Icons.settings),
            tooltip: 'toggle God mode',
            onPressed: (() {
              Navigator.of(context).push(new MaterialPageRoute(
                    builder: (context) => new SettingsScreen(),
                  ));
            }),
          )
        ],
      ),
      body: new FutureBuilder(
          future: _checkSignIn(),
          builder: (context, snapshot) {
            return snapshot.hasData
                ? new FutureBuilder(
                    future: getGroups(),
                    builder: (context, snapshot) {
                      return snapshot.hasData
                          ? new ListView.builder(
                              itemCount: snapshot.data.length,
                              itemBuilder: (context, index) {
                                return snapshot.data[index];
                              })
                          : snapshot.hasError
                              ? new LoadingScreen(
                                  message:
                                      'error loading conversations: ${snapshot.error}')
                              : new LoadingScreen(
                                  message: 'loading conversations');
                    })
                : snapshot.hasError
                    ? new LoadingScreen(
                        message: 'error signing in: ${snapshot.error}')
                    : new LoadingScreen(message: 'logging in');
          }),
    );
  }
}

Future<List<Conversation>> getGroups() async {
  List<Conversation> conversations = new List();

  DataSnapshot snapshot =
      await FirebaseDatabase.instance.reference().child('groups').once();

  Map data = snapshot.value;

  for (var key in data.keys) {
    Map group = snapshot.value[key];

    DataSnapshot memberGroups = await FirebaseDatabase.instance
        .reference()
        .child('users/${_currentUser.userKey}/groups/$key')
        .once();

    if (memberGroups.value != null) {
      //current user belongs to this group

      List<User> groupMembers = new List();

      Map members = group['members'];

      for (var userKey in members.keys) {
        DataSnapshot userSnapshot =
            await FirebaseDatabase.instance.reference().child('users').once();
        Map users = userSnapshot.value;
        Map user = users[userKey];

        groupMembers.add(new User(
          name: user['name'],
          email: user['email'],
          photoUrl: user['photoUrl'],
        ));
      }

      conversations.add(new Conversation(
        name: group['name'],
        groupID: key,
        members: groupMembers,
      ));
    }
  }

  return conversations;
}

class Conversation extends StatelessWidget {
  String name;
  String groupID;
  List<User> members; //note: these user objects may not have all data

  Conversation({this.name, this.groupID, this.members});

  @override
  Widget build(BuildContext context) {
    return new ListTile(
      leading: new Icon(Icons.perm_identity),
      title: new Text(name),
      subtitle: new Text(_buildMemberShortList()),
      onTap: (() {
        Navigator.of(context).push(new MaterialPageRoute(builder: (context) {
          return new ChatScreen(conversation: this);
        }));
      }),
    );
  }

  String _buildMemberShortList({int index = 0}) {
    if (index < members.length) {
      return '${members[index].name}${index + 1 == members.length
      ? '' : ', '}${_buildMemberShortList(index: index + 1)}';
    } else {
      return '';
    }
  }
}

class LoadingScreen extends StatelessWidget {
  String message;

  LoadingScreen({this.message = 'Loading...'}) : super();

  @override
  Widget build(BuildContext context) {
    return new Center(child: new Text(message));
  }
}

class SettingsScreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => new SettingsState();
}

class SettingsState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: new AppBar(
          title: const Text('Settings'),
        ),
        body: new Center(
            child: new Column(
          children: <Widget>[
            new FutureBuilder(
                future: _checkSignIn(),
                builder: (context, snapshot) {
                  return snapshot.hasData
                      ? _currentUser.godMode
                          ? new Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                new Checkbox(
                                    value: _currentUser.godModeOn,
                                    onChanged: ((val) {
                                      setState(() {
                                        _currentUser.toggleGodMode();
                                      });
                                    })),
                                new Text('godMode'),
                              ],
                            )
                          : new Container()
                      : new Container();
                })
          ],
        )));
  }
}

// Vision Processing Mode: set by Virutal Keyboard. Used by ml_kit processor
enum visionProcessMode {object, text}
visionProcessMode mode;

final FirebaseVisionTextDetector _detector =
    FirebaseVisionTextDetector.instance;

class VisionView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => new VisionViewState();
}

class VisionViewState extends State<VisionView> {
  CameraController controller;

  @override
  void initState() {
    super.initState();
    controller = new CameraController(cameras[0], ResolutionPreset.medium);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return new Container();
    }

    return new GestureDetector(
        child: new AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: new CameraPreview(controller)),
        onTap: (() {
          takePicture().then((String filePath) {
            if (mounted && (filePath != null)) print('Picture saved to $filePath');
            Navigator.pop(context,processWords(filePath));
          });
        }));
  }

  // Code taken from camera example on pub
  Future<String> takePicture() async {
    if (!controller.value.isInitialized) {
      return null;
    }
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures/flutter_test';
    await new Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';

    if (controller.value.isTakingPicture) {
      return null;
    }

    try {
      await controller.takePicture(filePath);
    } on CameraException catch (e) {
      return null;
    }
    return filePath;
  }

  String timestamp() => new DateTime.now().millisecondsSinceEpoch.toString();

  List<String> processWords(String imagePath) {
    // TODO: implement image processing
    switch (mode) {
      case visionProcessMode.object:
        var sampleList = new List<String>();
        sampleList.add('a word from an object');
        return sampleList;
        break;
      case visionProcessMode.text:
        var sampleList = new List<String>();
        sampleList.add('a word from text');
        sampleList.add('another word from text');
        return sampleList;
        break;
    }
  }
}
