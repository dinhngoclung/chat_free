import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ChatFreeApp());
}

class ChatFreeApp extends StatelessWidget {
  const ChatFreeApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue), home: const NameGate());
  }
}

class NameGate extends StatefulWidget { const NameGate({super.key}); @override State<NameGate> createState() => _NameGateState(); }
class _NameGateState extends State<NameGate> {
  final c = TextEditingController(); bool loading = true;
  @override void initState() { super.initState(); _check(); }
  Future<void> _check() async {
    final p = await SharedPreferences.getInstance(); final saved = p.getString('my_phone');
    if (saved!=null && mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(myPhone: saved)));
    else setState(()=>loading=false);
  }
  Future<void> _enter() async {
    final phone = c.text.trim();
    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SĐT phải 10 số!'))); return; }
    final p = await SharedPreferences.getInstance();
    await FirebaseFirestore.instance.collection('users').doc(phone).set({'phone': phone, 'friends': [], 'lastSeen': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    await p.setString('my_phone', phone);
    if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(myPhone: phone)));
  }
  @override Widget build(BuildContext context) {
    if(loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_person, size: 80, color: Colors.blue), const SizedBox(height: 16),
      const Text('Đăng nhập SĐT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 24),
      TextField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], maxLength: 10, decoration: const InputDecoration(labelText: 'Nhập SĐT 10 số', border: OutlineInputBorder(), counterText: "")),
      const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton(onPressed: _enter, child: const Text('Vào App'))),
    ])))));
  }
}

class HomeScreen extends StatefulWidget {
  final String myPhone; const HomeScreen({super.key, required this.myPhone}); @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final searchC = TextEditingController();
  final _player = AudioPlayer();
  final Map<String, StreamSubscription> _subs = {};
  final Map<String, bool> _hasUnread = {};
  final Map<String, String> _lastMsg = {};
  Map<String, String> _avatars = {};
  Map<String, String> _nicknames = {};
  int _lastReqCount = 0;

  @override void initState(){ super.initState(); _loadCustom(); }

  Future<void> _loadCustom() async {
    final p = await SharedPreferences.getInstance();
    Map<String,String> av = {}, nick = {};
    for(final k in p.getKeys()){
      if(k.startsWith('avatar_')) av[k.replaceAll('avatar_', '')] = p.getString(k)??'';
      if(k.startsWith('nickname_')) nick[k.replaceAll('nickname_', '')] = p.getString(k)??'';
    }
    setState((){ _avatars = av; _nicknames = nick; });
  }

  Future<void> _pickAvatar(String friendPhone) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 30);
    if(x==null) return;
    final b = await File(x.path).readAsBytes();
    final base64Str = base64Encode(b);
    final p = await SharedPreferences.getInstance();
    await p.setString('avatar_$friendPhone', base64Str);
    setState(()=>_avatars[friendPhone]=base64Str);
  }

  Future<void> _editName(String friendPhone) async {
    final c = TextEditingController(text: _nicknames[friendPhone]?? friendPhone);
    final res = await showDialog<String>(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('Đổi tên gợi nhớ'),
        content: TextField(controller: c, decoration: InputDecoration(hintText: 'Nhập tên mới cho $friendPhone', border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(onPressed: ()=>Navigator.pop(ctx, c.text.trim()), child: const Text('Lưu')),
        ],
      );
    });
    if(res==null || res.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('nickname_$friendPhone', res);
    setState(()=>_nicknames[friendPhone]=res);
  }

  void _showEditOptions(String friendPhone){
    showModalBottomSheet(context: context, builder: (ctx){
      return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.edit), title: const Text('Đổi tên gợi nhớ'), onTap: (){ Navigator.pop(ctx); _editName(friendPhone); }),
        ListTile(leading: const Icon(Icons.image), title: const Text('Đổi icon/avatar'), onTap: (){ Navigator.pop(ctx); _pickAvatar(friendPhone); }),
        ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Xóa tên + icon về mặc định', style: TextStyle(color: Colors.red)), onTap: () async {
          final p = await SharedPreferences.getInstance();
          await p.remove('nickname_$friendPhone');
          await p.remove('avatar_$friendPhone');
          setState((){ _nicknames.remove(friendPhone); _avatars.remove(friendPhone); });
          Navigator.pop(ctx);
        }),
      ]));
    });
  }

  void _playSound() async { try{ await _player.play(AssetSource('sounds/ting.mp3')); } catch(_){} }
  String _chatId(String a, String b){ final l=[a,b]..sort(); return '${l[0]}__${l[1]}'; }

  void _setupListeners(List<String> friends) async {
    final p = await SharedPreferences.getInstance();
    for(final f in friends){
      _hasUnread.putIfAbsent(f, ()=>false);
      _lastMsg.putIfAbsent(f, ()=>'');

      if(_subs.containsKey(f)) continue;
      final cid = _chatId(widget.myPhone, f);
      _subs[f] = FirebaseFirestore.instance.collection('private_chats').doc(cid).collection('messages').orderBy('time', descending: true).limit(1).snapshots().listen((snap){
        if(snap.docs.isEmpty) return;
        final data = snap.docs.first.data() as Map;
        final from = data['from'];
        final text = data['text']??'';
        final time = (data['time'] as Timestamp?)?.millisecondsSinceEpoch?? 0;
        final lastRead = p.getInt('lastRead_$cid')?? 0;
        if(mounted) setState(()=> _lastMsg[f] = data['img']!=null? '[Hình ảnh]' : (text.isEmpty? '[Icon]' : text));
        if(from!= widget.myPhone && time > lastRead){
          _playSound();
          if(mounted) setState(()=>_hasUnread[f]=true);
        }
      });
    }
  }

  Future<void> _openChat(String friend) async {
    final cid = _chatId(widget.myPhone, friend);
    final p = await SharedPreferences.getInstance();
    await p.setInt('lastRead_$cid', DateTime.now().millisecondsSinceEpoch);
    setState(()=>_hasUnread[friend]=false);
    if(!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(myPhone: widget.myPhone, peerPhone: friend, nickname: _nicknames[friend]))).then((_) async {
      final p2 = await SharedPreferences.getInstance();
      await p2.setInt('lastRead_$cid', DateTime.now().millisecondsSinceEpoch);
      setState(()=>_hasUnread[friend]=false);
      _loadCustom();
    });
  }

  Future<void> _sendRequest() async {
    final phone = searchC.text.trim();
    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SĐT 10 số!'))); return; }
    if (phone==widget.myPhone) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(phone).get();
    if (!doc.exists) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SĐT $phone chưa cài app!'))); return; }
    final myDoc = await FirebaseFirestore.instance.collection('users').doc(widget.myPhone).get();
    final friends = List<String>.from((myDoc.data() as Map?)?['friends']??[]);
    if(friends.contains(phone)){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã là bạn bè rồi!'))); return; }
    await FirebaseFirestore.instance.collection('friend_requests').doc('${widget.myPhone}_$phone').set({'from': widget.myPhone, 'to': phone, 'status': 'pending', 'time': FieldValue.serverTimestamp()});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã gửi lời mời tới $phone!')));
    searchC.clear();
  }
  Future<void> _accept(String fromPhone, String docId) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.myPhone).set({'friends': FieldValue.arrayUnion([fromPhone])}, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('users').doc(fromPhone).set({'friends': FieldValue.arrayUnion([widget.myPhone])}, SetOptions(merge: true));
    await FirebaseFirestore.instance.collection('friend_requests').doc(docId).update({'status':'accepted'});
  }

  @override void dispose(){ for(final s in _subs.values){ s.cancel(); } _player.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SĐT: ${widget.myPhone}')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: searchC, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], maxLength: 10, decoration: const InputDecoration(hintText: 'Nhập SĐT để gửi lời mời...', border: OutlineInputBorder(), counterText: ""))),
          const SizedBox(width: 8), FilledButton(onPressed: _sendRequest, child: const Text('Gửi'))
        ])),
        StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('friend_requests').where('to', isEqualTo: widget.myPhone).where('status', isEqualTo: 'pending').snapshots(), builder: (context, snap){
          if(snap.hasData && snap.data!.docs.length > _lastReqCount){
            if(_lastReqCount!=0) _playSound();
            _lastReqCount = snap.data!.docs.length;
          }
          if(snap.data==null || snap.data!.docs.isEmpty) return const SizedBox();
          return Container(color: Colors.orange[50], child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('Lời mời kết bạn:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
  ...snap.data!.docs.map((d){ final data=d.data() as Map; return ListTile(leading: const CircleAvatar(child: Icon(Icons.person_add)), title: Text(data['from']), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(onPressed: ()=>_accept(data['from'], d.id), child: const Text('Đồng ý')),
              IconButton(onPressed: ()=>d.reference.delete(), icon: const Icon(Icons.close))
            ])); }).toList()
          ]));
        }),
        const Divider(height: 1),
        Expanded(child: StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('users').doc(widget.myPhone).snapshots(), builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final data = snap.data!.data() as Map<String, dynamic>?;
          final friends = List<String>.from(data?['friends']??[]);
          if (friends.isEmpty) return const Center(child: Text('Chưa có bạn bè'));
          _setupListeners(friends);
          return ListView.builder(itemCount: friends.length, itemBuilder: (_, i) {
            final f = friends[i];
            final unread = _hasUnread[f]??false;
            final last = _lastMsg[f]??'';
            final avB64 = _avatars[f];
            final nick = _nicknames[f]?? f;
            return Container(
              color: unread? Colors.yellow[100] : Colors.transparent,
              child: ListTile(
                onLongPress: ()=>_showEditOptions(f),
                leading: Stack(children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: avB64!=null && avB64.isNotEmpty? MemoryImage(base64Decode(avB64)) : null,
                    child: avB64==null || avB64.isEmpty? Text(nick.length>=2? nick.substring(0,2).toUpperCase() : nick.substring(0,1)) : null,
                  ),
                  if(unread) Positioned(right: 0, top: 0, child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)))
                ]),
                title: Text(nick, style: TextStyle(fontWeight: unread? FontWeight.bold : FontWeight.normal, color: unread? Colors.blue : Colors.black)),
                subtitle: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: ()=>_showEditOptions(f)),
                onTap: ()=>_openChat(f)
              ),
            );
          });
        }))
      ])),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String myPhone, peerPhone; final String? nickname;
  const ChatScreen({super.key, required this.myPhone, required this.peerPhone, this.nickname}); @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _player = AudioPlayer();
  int _lastCount = 0;
  bool _showEmoji=false; bool _showSticker=false; String? bgBase64;
  final List<String> assetStickers = ['assets/stickers/love.png','assets/stickers/haha.png','assets/stickers/wow.png','assets/stickers/cry.png','assets/stickers/angry.png'];
  final List<String> wallpapers = ['assets/wallpapers/bg1.jpg','assets/wallpapers/bg2.jpg','assets/wallpapers/bg3.jpg','assets/wallpapers/bg4.jpg'];
  String get chatId { final a=[widget.myPhone, widget.peerPhone]..sort(); return '${a[0]}__${a[1]}'; }

  void _scrollToBottom(){ Future.delayed(const Duration(milliseconds: 100), (){ if(_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); }); }
  void _playSound() async { try{ await _player.play(AssetSource('sounds/ting.mp3')); } catch(_){} }
  bool _isOnlyEmoji(String text){ if(text.trim().isEmpty) return false; if(text.length > 10) return false; final hasLetter = RegExp(r'[a-zA-Z0-9áàảãạăâđéèẻẽẹêíìỉĩịóòỏõọôơúùủũụưýỳỷỹỵ]').hasMatch(text); return!hasLetter; }
  @override void initState(){ super.initState(); _loadBg(); _markRead(); }
  Future<void> _markRead() async { final p=await SharedPreferences.getInstance(); await p.setInt('lastRead_$chatId', DateTime.now().millisecondsSinceEpoch); }
  Future<void> _loadBg() async { final p=await SharedPreferences.getInstance(); setState(()=>bgBase64=p.getString('bg_$chatId')); }
  Future<void> _pickBgFromGallery() async {
    final x=await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 50);
    if(x==null) return;
    final b=await File(x.path).readAsBytes();
    final p=await SharedPreferences.getInstance();
    await p.setString('bg_$chatId', base64Encode(b));
    setState(()=>bgBase64=base64Encode(b));
  }
  void _showWallpaperPicker(){
    showModalBottomSheet(context: context, builder: (ctx){
      return SafeArea(child: Column(children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Chọn hình nền', style: TextStyle(fontWeight: FontWeight.bold))),
        Expanded(child: GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: wallpapers.length+2, itemBuilder: (c, i){
          if(i==0){
            return InkWell(onTap: () async {
              final p=await SharedPreferences.getInstance();
              await p.remove('bg_$chatId');
              setState(()=>bgBase64=null);
              Navigator.pop(context);
            }, child: Container(color: Colors.white, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.block), Text('Mặc định')])));
          }
          if(i==1){
            return InkWell(onTap: (){ Navigator.pop(context); _pickBgFromGallery(); }, child: Container(color: Colors.grey[300], child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo), Text('Từ máy')])));
          }
          final path = wallpapers[i-2];
          return InkWell(onTap: () async {
            try{
              final byteData = await rootBundle.load(path);
              final bytes = byteData.buffer.asUint8List();
              final encoded = base64Encode(bytes);
              final p = await SharedPreferences.getInstance();
              await p.setString('bg_$chatId', encoded);
              setState(()=>bgBase64=encoded);
              if(mounted) Navigator.pop(context);
            } catch (e) {}
          }, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(path, fit: BoxFit.cover, errorBuilder: (a,b,c2)=>Container(color: Colors.grey[200]))));
        })),
      ]));
    });
  }
  Future<void> _send({String? imgBase64, String? assetPath}) async {
    String? finalImg = imgBase64;
    if(assetPath!=null){
      try{ final byteData = await rootBundle.load(assetPath); finalImg = base64Encode(byteData.buffer.asUint8List()); }catch(e){ return; }
    }
    final t = _text.text.trim();
    if(t.isEmpty && finalImg==null) return;
    _text.clear();
    await FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').add({'from': widget.myPhone, 'text': finalImg==null? t : '', 'img': finalImg, 'time': FieldValue.serverTimestamp()});
    await _markRead();
    _scrollToBottom();
  }
  Future<void> _pick() async {
    final x=await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 30);
    if(x==null) return;
    final b=await File(x.path).readAsBytes();
    await _send(imgBase64: base64Encode(b));
  }
  void _openFullImage(String base64Img){ Navigator.push(context, MaterialPageRoute(builder: (_) => FullImageScreen(base64Img: base64Img))); }
  Future<void> _call() async { final url=Uri.parse('https://meet.jit.si/$chatId'); if(await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); }
  @override void dispose(){ _scroll.dispose(); _text.dispose(); _player.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(widget.nickname?? widget.peerPhone), actions: [IconButton(onPressed: _showWallpaperPicker, icon: const Icon(Icons.wallpaper)), IconButton(onPressed: _call, icon: const Icon(Icons.videocam))]),
      body: Stack(children: [
        if(bgBase64!=null) Positioned.fill(child: Image.memory(base64Decode(bgBase64!), fit: BoxFit.cover)),
        Column(children: [
          Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').orderBy('time').snapshots(), builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if(snap.data!.docs.length > _lastCount){
              if(_lastCount!=0){
                final last = snap.data!.docs.last.data() as Map;
                if(last['from']!= widget.myPhone){ _playSound(); _markRead(); }
              }
              _lastCount = snap.data!.docs.length;
            }
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: snap.data!.docs.length,
              itemBuilder: (_, i) {
                final m=snap.data!.docs[i].data() as Map;
                final isMe=m['from']==widget.myPhone;
                final hasImg=m['img']!=null;
                final txt = (m['text']??'').toString();
                if(hasImg){
                  return Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: InkWell(onTap: ()=>_openFullImage(m['img']), child: Container(margin: const EdgeInsets.symmetric(vertical: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(m['img']), width: 250, height: 250, fit: BoxFit.cover)))));
                }
                final onlyEmoji = _isOnlyEmoji(txt);
                return Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), child: Text(txt, style: TextStyle(fontSize: onlyEmoji? 28 : 16, color: Colors.black))));
              });
          })),
          if(_showEmoji) SizedBox(height: 250, child: EmojiPicker(textEditingController: _text, config: const Config(emojiViewConfig: EmojiViewConfig(columns: 8)))),
          if(_showSticker) Container(height: 160, color: Colors.white, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: assetStickers.length, itemBuilder: (_, i){
            return InkWell(onTap: ()=>_send(assetPath: assetStickers[i]), child: Padding(padding: const EdgeInsets.all(10), child: Image.asset(assetStickers[i], width: 120, height: 120, fit: BoxFit.contain, errorBuilder: (_,__,___)=>Container(width:120,height:120,color: Colors.grey[200]))));
          })),
        ]),
      ]),
      bottomNavigationBar: SafeArea(child: Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(4, 6, 4, 6), child: Row(children: [
        IconButton(onPressed: ()=>setState((){_showEmoji=!_showEmoji; _showSticker=false;}), icon: const Icon(Icons.emoji_emotions_outlined)),
        IconButton(onPressed: ()=>setState((){_showSticker=!_showSticker; _showEmoji=false;}), icon: const Icon(Icons.gif_box, color: Colors.orange)),
        IconButton(onPressed: _pick, icon: const Icon(Icons.image)),
        Expanded(child: TextField(controller: _text, onTap: ()=>setState((){_showEmoji=false; _showSticker=false;}), decoration: const InputDecoration(hintText: 'Nhắn...', border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))), contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
        IconButton(onPressed: ()=>_send(), icon: const Icon(Icons.send, color: Colors.blue))
      ])))),
    );
  }
}

class FullImageScreen extends StatefulWidget {
  final String base64Img;
  const FullImageScreen({super.key, required this.base64Img});
  @override State<FullImageScreen> createState() => _FullImageScreenState();
}
class _FullImageScreenState extends State<FullImageScreen> {
  Future<void> _save() async {
    try{
      final bytes = base64Decode(widget.base64Img);
      if(Platform.isWindows){
        final dir = await getDownloadsDirectory();
        final path = '${dir!.path}/img_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(path).writeAsBytes(bytes);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu vào $path')));
      } else {
        await Gal.requestAccess();
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/tmp_${DateTime.now().millisecondsSinceEpoch}.png';
        await File(tempPath).writeAsBytes(bytes);
        await Gal.putImage(tempPath);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu vào Thư viện ảnh!')));
      }
    } catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi lưu: $e')));
    }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), title: const Text('Xem ảnh', style: TextStyle(color: Colors.white)), actions: [IconButton(onPressed: _save, icon: const Icon(Icons.download, color: Colors.white))]),
      body: Center(child: InteractiveViewer(child: Image.memory(base64Decode(widget.base64Img)))),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Lưu ảnh này'))))),
    );
  }
}
