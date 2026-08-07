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
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SĐT: ${widget.myPhone}')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          Expanded(child: TextField(controller: searchC, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], maxLength: 10, decoration: const InputDecoration(hintText: 'Nhập SĐT để gửi lời mời...', border: OutlineInputBorder(), counterText: ""))),
          const SizedBox(width: 8), FilledButton(onPressed: _sendRequest, child: const Text('Gửi'))
        ])),
        StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('friend_requests').where('to', isEqualTo: widget.myPhone).where('status', isEqualTo: 'pending').snapshots(), builder: (context, snap){
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
          return ListView.builder(itemCount: friends.length, itemBuilder: (_, i) { final f = friends[i]; return ListTile(leading: CircleAvatar(child: Text(f.substring(f.length-2))), title: Text(f), onTap: ()=>Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(myPhone: widget.myPhone, peerPhone: f)))); });
        }))
      ])),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String myPhone, peerPhone; const ChatScreen({super.key, required this.myPhone, required this.peerPhone}); @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _showEmoji=false; bool _showSticker=false; String? bgBase64;
  final List<String> assetStickers = ['assets/stickers/love.png','assets/stickers/haha.png','assets/stickers/wow.png','assets/stickers/cry.png','assets/stickers/angry.png'];
  final List<String> wallpapers = ['assets/wallpapers/bg1.jpg','assets/wallpapers/bg2.jpg','assets/wallpapers/bg3.jpg','assets/wallpapers/bg4.jpg'];
  String get chatId { final a=[widget.myPhone, widget.peerPhone]..sort(); return '${a[0]}__${a[1]}'; }

  void _scrollToBottom(){
    Future.delayed(const Duration(milliseconds: 100), (){
      if(_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  bool _isOnlyEmoji(String text){
    if(text.trim().isEmpty) return false;
    if(text.length > 10) return false;
    final hasLetter = RegExp(r'[a-zA-Z0-9a-zA-Záàảãạăâđéèẻẽẹêíìỉĩịóòỏõọôơúùủũụưýỳỷỹỵ]').hasMatch(text);
    return!hasLetter;
  }

  @override void initState(){ super.initState(); _loadBg(); }
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
      try{
        final byteData = await rootBundle.load(assetPath);
        finalImg = base64Encode(byteData.buffer.asUint8List());
      }catch(e){ return; }
    }
    final t = _text.text.trim();
    if(t.isEmpty && finalImg==null) return;
    _text.clear();
    await FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').add({'from': widget.myPhone, 'text': finalImg==null? t : '', 'img': finalImg, 'time': FieldValue.serverTimestamp()});
    _scrollToBottom();
  }
  Future<void> _pick() async {
    final x=await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 30);
    if(x==null) return;
    final b=await File(x.path).readAsBytes();
    await _send(imgBase64: base64Encode(b));
  }
  Future<void> _call() async {
    final url=Uri.parse('https://meet.jit.si/$chatId');
    if(await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }
  @override void dispose(){ _scroll.dispose(); _text.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(widget.peerPhone), actions: [IconButton(onPressed: _showWallpaperPicker, icon: const Icon(Icons.wallpaper)), IconButton(onPressed: _call, icon: const Icon(Icons.videocam))]),
      body: Stack(children: [
        if(bgBase64!=null) Positioned.fill(child: Image.memory(base64Decode(bgBase64!), fit: BoxFit.cover)),
        Column(children: [
          Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').orderBy('time').snapshots(), builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
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
                  return Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: Container(margin: const EdgeInsets.symmetric(vertical: 6), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(m['img']), width: 250, height: 250, fit: BoxFit.contain))));
                }
                final onlyEmoji = _isOnlyEmoji(txt);
                return Align(
                  alignment: isMe? Alignment.centerRight:Alignment.centerLeft,
                  child: Container(margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8), child: Text(txt, style: TextStyle(fontSize: onlyEmoji? 28 : 16, color: Colors.black)))
                );
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