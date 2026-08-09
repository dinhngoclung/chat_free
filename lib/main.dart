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

const zaloBlue = Color(0xFF0068FF);
const zaloBg = Color(0xFFF0F2F5);

class ChatFreeApp extends StatelessWidget {
  const ChatFreeApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: zaloBlue,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(backgroundColor: zaloBlue, foregroundColor: Colors.white, elevation: 0),
      ),
      home: const NameGate(),
    );
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
    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SĐT phải 10 số bắt đầu bằng số 0!'))); return; }
    final p = await SharedPreferences.getInstance();
    // FIX: KHÔNG GHI ĐÈ FRIENDS
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(phone).get();
    if (!userDoc.exists) {
      await FirebaseFirestore.instance.collection('users').doc(phone).set({'phone': phone, 'friends': [], 'isOnline': true, 'lastSeen': FieldValue.serverTimestamp()}, SetOptions(merge: false));
    } else {
      await FirebaseFirestore.instance.collection('users').doc(phone).update({'isOnline': true, 'lastSeen': FieldValue.serverTimestamp()});
    }
    await p.setString('my_phone', phone);
    if (!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(myPhone: phone)));
  }
  @override Widget build(BuildContext context) {
    if(loading) return const Scaffold(backgroundColor: zaloBlue, body: Center(child: CircularProgressIndicator(color: Colors.white)));
    return Scaffold(backgroundColor: zaloBlue, body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/icon/chatfree.png', width: 90, height: 90, errorBuilder: (_,__,___)=> const Icon(Icons.chat_bubble, size: 80, color: Colors.white)),
      const SizedBox(height: 12), const Text('Lung Chat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)), const Text('Giao diện Zalo 80%', style: TextStyle(color: Colors.white70)), const SizedBox(height: 32),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [
        const Text('Đăng nhập', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16),
        TextField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], maxLength: 10, decoration: InputDecoration(labelText: 'Số điện thoại của bạn', prefixText: '+84 ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), counterText: "")),
        const SizedBox(height: 12), SizedBox(width: double.infinity, height: 48, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: zaloBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _enter, child: const Text('TIẾP TỤC', style: TextStyle(fontWeight: FontWeight.bold)))),
      ])),
    ])))) );
  }
}

class HomeScreen extends StatefulWidget { final String myPhone; const HomeScreen({super.key, required this.myPhone}); @override State<HomeScreen> createState() => _HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final searchC = TextEditingController(); final _player = AudioPlayer();
  final Map<String, StreamSubscription> _subs = {}; final Map<String, bool> _hasUnread = {}; final Map<String, String> _lastMsg = {};
  Map<String, String> _avatars = {}; Map<String, String> _nicknames = {}; int _lastReqCount = 0; late TabController _tab;

  @override void initState(){ super.initState(); WidgetsBinding.instance.addObserver(this); _tab = TabController(length: 2, vsync: this); _loadCustom(); _setOnline(true); }
  @override void didChangeAppLifecycleState(AppLifecycleState state){ if(state==AppLifecycleState.resumed) _setOnline(true); else if(state==AppLifecycleState.paused) _setOnline(false); }
  Future<void> _setOnline(bool online) async { await FirebaseFirestore.instance.collection('users').doc(widget.myPhone).update({'isOnline': online, 'lastSeen': FieldValue.serverTimestamp()}); }

  Future<void> _loadCustom() async {
    final p = await SharedPreferences.getInstance(); Map<String,String> av = {}, nick = {};
    for(final k in p.getKeys()){ if(k.startsWith('avatar_')) av[k.replaceAll('avatar_', '')] = p.getString(k)??''; if(k.startsWith('nickname_')) nick[k.replaceAll('nickname_', '')] = p.getString(k)??''; }
    try{ final doc = await FirebaseFirestore.instance.collection('user_custom').doc(widget.myPhone).get(); if(doc.exists){ final data = doc.data() as Map; if(data['avatars']!=null) av.addAll(Map<String,String>.from(data['avatars'])); if(data['nicknames']!=null) nick.addAll(Map<String,String>.from(data['nicknames'])); } }catch(_){}
    setState((){ _avatars = av; _nicknames = nick; });
  }
  Future<void> _pickAvatar(String f) async { final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 40); if(x==null) return; final b = await File(x.path).readAsBytes(); final b64 = base64Encode(b); final p = await SharedPreferences.getInstance(); await p.setString('avatar_$f', b64); await FirebaseFirestore.instance.collection('user_custom').doc(widget.myPhone).set({'avatars': {f: b64}}, SetOptions(merge: true)); setState(()=>_avatars[f]=b64); }
  Future<void> _editName(String f) async { final c = TextEditingController(text: _nicknames[f]?? f); final res = await showDialog<String>(context: context, builder: (ctx){ return AlertDialog(title: const Text('Đổi tên gợi nhớ'), content: TextField(controller: c, autofocus: true), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text('Hủy')), FilledButton(onPressed: ()=>Navigator.pop(ctx, c.text.trim()), child: const Text('Lưu'))]); }); if(res==null || res.isEmpty) return; final p = await SharedPreferences.getInstance(); await p.setString('nickname_$f', res); await FirebaseFirestore.instance.collection('user_custom').doc(widget.myPhone).set({'nicknames': {f: res}}, SetOptions(merge: true)); setState(()=>_nicknames[f]=res); }
  void _showEditOptions(String f){ showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx){ return SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [const SizedBox(height: 8), Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))), ListTile(leading: const Icon(Icons.edit, color: zaloBlue), title: const Text('Đổi tên gợi nhớ'), onTap: (){ Navigator.pop(ctx); _editName(f); }), ListTile(leading: const Icon(Icons.image, color: zaloBlue), title: const Text('Đổi avatar'), onTap: (){ Navigator.pop(ctx); _pickAvatar(f); }), ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Xóa về mặc định', style: TextStyle(color: Colors.red)), onTap: () async { final p = await SharedPreferences.getInstance(); await p.remove('nickname_$f'); await p.remove('avatar_$f'); await FirebaseFirestore.instance.collection('user_custom').doc(widget.myPhone).set({'avatars': {f: FieldValue.delete()}, 'nicknames': {f: FieldValue.delete()}}, SetOptions(merge: true)); setState((){ _nicknames.remove(f); _avatars.remove(f); }); Navigator.pop(ctx); }), const SizedBox(height: 12)])); }); }
  void _playSound() async { try{ await _player.play(AssetSource('sounds/ting.mp3')); } catch(_){} }
  String _chatId(String a, String b){ final l=[a,b]..sort(); return '${l[0]}__${l[1]}'; }
  void _setupListeners(List<String> friends) async { final p = await SharedPreferences.getInstance(); for(final f in friends){ _hasUnread.putIfAbsent(f, ()=>false); _lastMsg.putIfAbsent(f, ()=>''); if(_subs.containsKey(f)) continue; final cid = _chatId(widget.myPhone, f); _subs[f] = FirebaseFirestore.instance.collection('private_chats').doc(cid).collection('messages').orderBy('time', descending: true).limit(1).snapshots().listen((snap){ if(snap.docs.isEmpty) return; final data = snap.docs.first.data() as Map; final from = data['from']; final text = data['text']??''; final time = (data['time'] as Timestamp?)?.millisecondsSinceEpoch?? 0; final lastRead = p.getInt('lastRead_$cid')?? 0; if(mounted) setState(()=> _lastMsg[f] = data['imgs']!=null? '[${(data['imgs'] as List).length} hình ảnh]' : (data['img']!=null? '[Hình ảnh]' : (text.isEmpty? '[Sticker]' : text))); if(from!= widget.myPhone && time > lastRead){ _playSound(); if(mounted) setState(()=>_hasUnread[f]=true); } }); } }
  Future<void> _openChat(String friend) async { final cid = _chatId(widget.myPhone, friend); final p = await SharedPreferences.getInstance(); await p.setInt('lastRead_$cid', DateTime.now().millisecondsSinceEpoch); setState(()=>_hasUnread[friend]=false); if(!mounted) return; Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(myPhone: widget.myPhone, peerPhone: friend, nickname: _nicknames[friend], avatarB64: _avatars[friend]))).then((_) async { final p2 = await SharedPreferences.getInstance(); await p2.setInt('lastRead_$cid', DateTime.now().millisecondsSinceEpoch); setState(()=>_hasUnread[friend]=false); _loadCustom(); }); }
  Future<void> _sendRequest() async { final phone = searchC.text.trim(); if (!RegExp(r'^0\d{9}$').hasMatch(phone)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SĐT 10 số!'))); return; } if (phone==widget.myPhone) return; final doc = await FirebaseFirestore.instance.collection('users').doc(phone).get(); if (!doc.exists) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('SĐT $phone chưa cài app!'))); return; } final myDoc = await FirebaseFirestore.instance.collection('users').doc(widget.myPhone).get(); final friends = List<String>.from((myDoc.data() as Map?)?['friends']??[]); if(friends.contains(phone)){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã là bạn bè rồi!'))); return; } await FirebaseFirestore.instance.collection('friend_requests').doc('${widget.myPhone}_$phone').set({'from': widget.myPhone, 'to': phone, 'status': 'pending', 'time': FieldValue.serverTimestamp()}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã gửi lời mời tới $phone!'))); searchC.clear(); }
  Future<void> _accept(String fromPhone, String docId) async { fromPhone = fromPhone.split('_').first; await FirebaseFirestore.instance.collection('users').doc(widget.myPhone).set({'friends': FieldValue.arrayUnion([fromPhone])}, SetOptions(merge: true)); await FirebaseFirestore.instance.collection('users').doc(fromPhone).set({'friends': FieldValue.arrayUnion([widget.myPhone])}, SetOptions(merge: true)); await FirebaseFirestore.instance.collection('friend_requests').doc(docId).update({'status':'accepted'}); }
  @override void dispose(){ WidgetsBinding.instance.removeObserver(this); _setOnline(false); for(final s in _subs.values){ s.cancel(); } _player.dispose(); _tab.dispose(); super.dispose(); }
  String _formatLastSeen(Timestamp? ts, bool isOnline){ if(isOnline) return 'Đang hoạt động'; if(ts==null) return 'Vừa truy cập'; final diff = DateTime.now().difference(ts.toDate()); if(diff.inMinutes<1) return 'Vừa truy cập'; if(diff.inMinutes<60) return '${diff.inMinutes} phút trước'; if(diff.inHours<24) return '${diff.inHours} giờ trước'; return 'Hôm qua'; }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: zaloBlue, title: Row(children: [const Icon(Icons.search, color: Colors.white70), const SizedBox(width: 8), Expanded(child: TextField(controller: searchC, style: const TextStyle(color: Colors.white), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], decoration: const InputDecoration(hintText: 'Tìm bạn bè, tin nhắn...', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none, counterText: ""))) ]), actions: [IconButton(onPressed: _sendRequest, icon: const Icon(Icons.person_add_alt_1)), IconButton(onPressed: () async { await _setOnline(false); final p=await SharedPreferences.getInstance(); await p.remove('my_phone'); if(mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> const NameGate())); }, icon: const Icon(Icons.logout))], bottom: TabBar(controller: _tab, indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70, tabs: const [Tab(text: 'TIN NHẮN'), Tab(text: 'DANH BẠ')])),
      body: Column(children: [
        StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('friend_requests').where('to', isEqualTo: widget.myPhone).where('status', isEqualTo: 'pending').snapshots(), builder: (context, snap){ if(snap.hasData && snap.data!.docs.length > _lastReqCount){ if(_lastReqCount!=0) _playSound(); _lastReqCount = snap.data!.docs.length; } if(snap.data==null || snap.data!.docs.isEmpty) return const SizedBox(); return Container(color: const Color(0xFFFFF3E0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Padding(padding: EdgeInsets.all(10), child: Text('Lời mời kết bạn', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),...snap.data!.docs.map((d){ final data=d.data() as Map; String fromPhone = data['from'].toString().split('_').first; return ListTile(leading: const CircleAvatar(backgroundColor: zaloBlue, child: Icon(Icons.person_add, color: Colors.white)), title: Text(fromPhone, style: const TextStyle(fontWeight: FontWeight.bold)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [FilledButton(style: FilledButton.styleFrom(backgroundColor: zaloBlue), onPressed: ()=>_accept(fromPhone, d.id), child: const Text('Đồng ý')), IconButton(onPressed: ()=>d.reference.delete(), icon: const Icon(Icons.close))])); })])); }),
        Expanded(child: TabBarView(controller: _tab, children: [
          StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('users').doc(widget.myPhone).snapshots(), builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator()); final data = snap.data!.data() as Map<String, dynamic>?; final friends = List<String>.from(data?['friends']??[]); if (friends.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[300]), const SizedBox(height: 8), const Text('Chưa có bạn bè', style: TextStyle(color: Colors.grey))])); _setupListeners(friends);
            return ListView.separated(separatorBuilder: (_,__)=> Divider(height: 1, indent: 76, color: Colors.grey[200]), itemCount: friends.length, itemBuilder: (_, i) {
              final f = friends[i].split('_').first; final unread = _hasUnread[f]??false; final last = _lastMsg[f]??''; final avB64 = _avatars[f]; final nick = _nicknames[f]?? f;
              return StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('users').doc(f).snapshots(), builder: (context, userSnap){
                bool isOnline = false; Timestamp? lastSeen;
                if(userSnap.hasData && userSnap.data!.exists){ final ud = userSnap.data!.data() as Map<String,dynamic>?; isOnline = ud?['isOnline']??false; lastSeen = ud?['lastSeen'] as Timestamp?; }
                return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), onLongPress: ()=>_showEditOptions(f),
                  leading: Stack(children: [CircleAvatar(radius: 28, backgroundColor: Colors.grey[200], backgroundImage: avB64!=null && avB64.isNotEmpty? MemoryImage(base64Decode(avB64)) : null, child: avB64==null || avB64.isEmpty? Text(nick.length>=2? nick.substring(0,2).toUpperCase() : nick.substring(0,1), style: const TextStyle(fontWeight: FontWeight.bold, color: zaloBlue)) : null), if(isOnline) Positioned(right: 2, bottom: 2, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))), if(unread) Positioned(right: 0, top: 0, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))]),
                  title: Text(nick, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread? FontWeight.bold : FontWeight.w600, fontSize: 16, color: unread? Colors.black : Colors.black87)),
                  subtitle: Text(last.isEmpty? (isOnline? 'Đang hoạt động' : _formatLastSeen(lastSeen, false)) : last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread? Colors.black87 : Colors.grey[600], fontWeight: unread? FontWeight.w500: FontWeight.normal)),
                  trailing: unread? Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)), child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 10))) : null,
                  onTap: ()=>_openChat(f));
              });
            });
          }),
          const Center(child: Text('Danh bạ - đang phát triển'))
        ]))
      ]),
    );
  }
}

class ZaloBubble extends StatelessWidget {
  final bool isMe; final String? text; final List<String>? imgList; final String? imgB64; final bool isEmojiOnly; final DateTime? time; final void Function(String)? onTapImg;
  const ZaloBubble({super.key, required this.isMe, this.text, this.imgList, this.imgB64, this.isEmojiOnly = false, this.time, this.onTapImg});
  Widget _buildImages(BuildContext context){
    List<String> list = [];
    if(imgList!=null && imgList!.isNotEmpty) list = imgList!;
    else if(imgB64!=null) list = [imgB64!];
    if(list.isEmpty) return const SizedBox();
    // GIỐNG ZALO: 1 ảnh to, 2 ảnh xếp ngang, 3+ ảnh dạng lưới
    if(list.length==1){
      return GestureDetector(onTap: ()=>onTapImg?.call(list[0]), child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.memory(base64Decode(list[0]), width: 200, fit: BoxFit.cover)));
    }
    return SizedBox(width: 220, child: Wrap(spacing: 4, runSpacing: 4, children: list.map((b64){
      return GestureDetector(onTap: ()=>onTapImg?.call(b64), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(base64Decode(b64), width: list.length==2? 108 : 70, height: list.length==2? 108 : 70, fit: BoxFit.cover)));
    }).toList()));
  }
  @override Widget build(BuildContext context) {
    final bg = isMe? zaloBlue : Colors.white; final txtColor = isMe? Colors.white : Colors.black87;
    if (imgList!=null || imgB64!= null) {
      return Container(margin: EdgeInsets.only(left: isMe? 60: 8, right: isMe? 8:60, top: 4, bottom: 4), child: Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: Column(crossAxisAlignment: isMe? CrossAxisAlignment.end:CrossAxisAlignment.start, children: [_buildImages(context), if(time!=null) Padding(padding: const EdgeInsets.only(top: 2), child: Text('${time!.hour.toString().padLeft(2,'0')}:${time!.minute.toString().padLeft(2,'0')}', style: TextStyle(fontSize: 11, color: Colors.grey[500])))])));
    }
    if (isEmojiOnly) { return Container(margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), child: Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: Text(text??'', style: const TextStyle(fontSize: 36)))); }
    return Container(margin: EdgeInsets.only(left: isMe? 60: 12, right: isMe? 12:60, top: 3, bottom: 3), child: Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: Column(crossAxisAlignment: isMe? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(isMe? 18:4), bottomRight: Radius.circular(isMe? 4:18)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)]), child: Text(text??'', style: TextStyle(fontSize: 15.5, height: 1.3, color: txtColor))), if(time!=null) Padding(padding: const EdgeInsets.only(top: 2, left: 4, right: 4), child: Text('${time!.hour.toString().padLeft(2,'0')}:${time!.minute.toString().padLeft(2,'0')} ${isMe? "• Đã xem" : ""}', style: TextStyle(fontSize: 11, color: Colors.grey[500]))),])));
  }
}

class ChatScreen extends StatefulWidget { final String myPhone, peerPhone; final String? nickname; final String? avatarB64; const ChatScreen({super.key, required this.myPhone, required this.peerPhone, this.nickname, this.avatarB64}); @override State<ChatScreen> createState() => _ChatScreenState(); }
class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController(); final _scroll = ScrollController(); final _player = AudioPlayer();
  int _lastCount = 0; bool _showEmoji=false; bool _showSticker=false; String? bgBase64;
  final List<String> assetStickers = ['assets/stickers/love.png','assets/stickers/haha.png','assets/stickers/wow.png','assets/stickers/cry.png','assets/stickers/angry.png'];
  String get chatId { final a=[widget.myPhone, widget.peerPhone]..sort(); return '${a[0]}__${a[1]}'; }
  void _scrollToBottom(){ Future.delayed(const Duration(milliseconds: 100), (){ if(_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); }); }
  void _playSound() async { try{ await _player.play(AssetSource('sounds/ting.mp3')); } catch(_){} }
  bool _isOnlyEmoji(String text){ if(text.trim().isEmpty) return false; if(text.length > 10) return false; final hasLetter = RegExp(r'[a-zA-Z0-9áàảãạăâđéèẻẽẹêíìỉĩịóòỏõọôơúùủũụưýỳỷỹỵ]').hasMatch(text); return!hasLetter; }
  @override void initState(){ super.initState(); _loadBg(); _markRead(); }
  Future<void> _markRead() async { final p=await SharedPreferences.getInstance(); await p.setInt('lastRead_$chatId', DateTime.now().millisecondsSinceEpoch); }
  Future<void> _loadBg() async { final p=await SharedPreferences.getInstance(); setState(()=>bgBase64=p.getString('bg_$chatId')); }
  Future<void> _pickBgFromGallery() async { final x=await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 50); if(x==null) return; final b=await File(x.path).readAsBytes(); final p=await SharedPreferences.getInstance(); await p.setString('bg_$chatId', base64Encode(b)); setState(()=>bgBase64=base64Encode(b)); }
  Future<void> _send({List<String>? imgList, String? assetPath}) async {
    String? finalImg; List<String>? finalList = imgList;
    if(assetPath!=null){ try{ final byteData = await rootBundle.load(assetPath); finalImg = base64Encode(byteData.buffer.asUint8List()); finalList = [finalImg]; }catch(e){ return; } }
    final t = _text.text.trim(); if(t.isEmpty && (finalList==null || finalList.isEmpty)) return; _text.clear();
    if(finalList!=null && finalList.isNotEmpty){
      await FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').add({'from': widget.myPhone, 'text': t, 'imgs': finalList, 'time': FieldValue.serverTimestamp()});
    } else {
      await FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').add({'from': widget.myPhone, 'text': finalList==null? t : '', 'img': finalImg, 'time': FieldValue.serverTimestamp()});
    }
    await _markRead(); _scrollToBottom();
  }
  // FIX: CHỌN NHIỀU ẢNH
  Future<void> _pickMulti() async { final List<XFile> xs = await ImagePicker().pickMultiImage(imageQuality: 30); if(xs.isEmpty) return; List<String> b64s = []; for(final x in xs){ final b = await File(x.path).readAsBytes(); b64s.add(base64Encode(b)); if(b64s.length>=9) break; } await _send(imgList: b64s); }
  void _openFullImage(String b64){ Navigator.push(context, MaterialPageRoute(builder: (_) => FullImageScreen(base64Img: b64))); }
  Future<void> _call() async { final url=Uri.parse('https://meet.jit.si/$chatId'); if(await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); }
  @override void dispose(){ _scroll.dispose(); _text.dispose(); _player.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: zaloBg, resizeToAvoidBottomInset: true,
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 1, titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(radius: 20, backgroundColor: Colors.grey[200], backgroundImage: widget.avatarB64!=null && widget.avatarB64!.isNotEmpty? MemoryImage(base64Decode(widget.avatarB64!)) : null, child: widget.avatarB64==null? Text((widget.nickname?? widget.peerPhone).substring(0,1).toUpperCase()) : null),
          const SizedBox(width: 10),
          Expanded(child: StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('users').doc(widget.peerPhone).snapshots(), builder: (context, snap){
            bool isOnline = false; Timestamp? lastSeen;
            if(snap.hasData && snap.data!.exists){ final d = snap.data!.data() as Map<String,dynamic>?; isOnline = d?['isOnline']??false; lastSeen = d?['lastSeen'] as Timestamp?; }
            String status = isOnline? 'Đang hoạt động' : (lastSeen==null? 'Vừa truy cập' : 'Hoạt động ${DateTime.now().difference(lastSeen.toDate()).inMinutes} phút trước');
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.nickname?? widget.peerPhone, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text(status, style: TextStyle(fontSize: 12, color: isOnline? Colors.green : Colors.grey))]);
          })),
        ]),
        actions: [IconButton(onPressed: _call, icon: const Icon(Icons.call, color: zaloBlue)), IconButton(onPressed: _call, icon: const Icon(Icons.videocam, color: zaloBlue)), IconButton(onPressed: ()=>showModalBottomSheet(context: context, builder: (_)=> SafeArea(child: ListTile(leading: const Icon(Icons.wallpaper), title: const Text('Đổi hình nền'), onTap: (){ Navigator.pop(context); _pickBgFromGallery(); }))), icon: const Icon(Icons.more_vert))],
      ),
      body: Stack(children: [
        if(bgBase64!=null) Positioned.fill(child: Image.memory(base64Decode(bgBase64!), fit: BoxFit.cover)),
        Column(children: [
          Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').orderBy('time').snapshots(), builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if(snap.data!.docs.length > _lastCount){ if(_lastCount!=0){ final last = snap.data!.docs.last.data() as Map; if(last['from']!= widget.myPhone){ _playSound(); _markRead(); } } _lastCount = snap.data!.docs.length; }
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
            return ListView.builder(controller: _scroll, padding: const EdgeInsets.symmetric(vertical: 12), itemCount: snap.data!.docs.length, itemBuilder: (_, i) {
              final m=snap.data!.docs[i].data() as Map; final isMe=m['from']==widget.myPhone; final hasImg=m['img']!=null || m['imgs']!=null; final txt = (m['text']??'').toString(); final time = (m['time'] as Timestamp?)?.toDate();
              if(hasImg){
                List<String> list = []; if(m['imgs']!=null) list = List<String>.from(m['imgs']); else if(m['img']!=null) list = [m['img']];
                return ZaloBubble(isMe: isMe, imgList: list, time: time, onTapImg: _openFullImage);
              }
              return ZaloBubble(isMe: isMe, text: txt, isEmojiOnly: _isOnlyEmoji(txt), time: time);
            });
          })),
          if(_showEmoji) SizedBox(height: 260, child: EmojiPicker(textEditingController: _text, config: const Config(emojiViewConfig: EmojiViewConfig(columns: 8, backgroundColor: Colors.white), bottomActionBarConfig: BottomActionBarConfig(backgroundColor: Colors.white)))),
          if(_showSticker) Container(height: 100, color: Colors.white, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: assetStickers.length, itemBuilder: (_, i){ return InkWell(onTap: ()=>_send(assetPath: assetStickers[i]), child: Padding(padding: const EdgeInsets.all(10), child: Image.asset(assetStickers[i], width: 70, height: 70, errorBuilder: (_,__,___)=>Container(width:70,height:70,color: Colors.grey[200], child: const Icon(Icons.emoji_emotions))))); })),
        ]),
      ]),
      bottomNavigationBar: Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: SafeArea(child: Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), child: Row(children: [
        IconButton(onPressed: ()=>setState((){_showEmoji=!_showEmoji; _showSticker=false; if(_showEmoji) FocusScope.of(context).unfocus(); else FocusScope.of(context).requestFocus();}), icon: Icon(_showEmoji? Icons.keyboard : Icons.emoji_emotions_outlined, color: Colors.grey[600])),
        IconButton(onPressed: ()=>setState((){_showSticker=!_showSticker; _showEmoji=false; if(_showSticker) FocusScope.of(context).unfocus();}), icon: Icon(Icons.gif_box, color: _showSticker? zaloBlue : Colors.grey[600])),
        IconButton(onPressed: _pickMulti, icon: Icon(Icons.image, color: Colors.grey[600])),
        Expanded(child: Container(decoration: BoxDecoration(color: zaloBg, borderRadius: BorderRadius.circular(20)), child: TextField(controller: _text, minLines: 1, maxLines: 4, onTap: ()=>setState((){_showEmoji=false; _showSticker=false;}), decoration: const InputDecoration(hintText: 'Tin nhắn', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10))))),
        const SizedBox(width: 4), GestureDetector(onTap: ()=>_send(), child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: zaloBlue, shape: BoxShape.circle), child: const Icon(Icons.send, color: Colors.white, size: 20))),
      ])))),
    );
  }
}

class FullImageScreen extends StatefulWidget { final String base64Img; const FullImageScreen({super.key, required this.base64Img}); @override State<FullImageScreen> createState() => _FullImageScreenState(); }
class _FullImageScreenState extends State<FullImageScreen> {
  Future<void> _save() async { try{ final bytes = base64Decode(widget.base64Img); if(Platform.isWindows){ final dir = await getDownloadsDirectory(); final path = '${dir!.path}/img_${DateTime.now().millisecondsSinceEpoch}.png'; await File(path).writeAsBytes(bytes); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu vào $path'))); } else { await Gal.requestAccess(); final tempDir = await getTemporaryDirectory(); final tempPath = '${tempDir.path}/tmp_${DateTime.now().millisecondsSinceEpoch}.png'; await File(tempPath).writeAsBytes(bytes); await Gal.putImage(tempPath); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu vào Thư viện ảnh!'))); } } catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi lưu: $e'))); } }
  @override Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), title: const Text('Xem ảnh', style: TextStyle(color: Colors.white)), actions: [IconButton(onPressed: _save, icon: const Icon(Icons.download, color: Colors.white))]), body: Center(child: InteractiveViewer(child: Image.memory(base64Decode(widget.base64Img)))), bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: zaloBlue), onPressed: _save, icon: const Icon(Icons.save), label: const Text('Lưu ảnh này')))))); }
}
