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
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:audioplayers/audioplayers.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ChatFreeApp());
}

const zaloBlue = Color(0xFF0068FF);
const zaloBg = Color(0xFFF0F2F5);

// SERVICE ÂM THANH
class SoundService {
  static final AudioPlayer _player = AudioPlayer();
  static Future<void> play() async {
    try {
      // Cố gắng phát file assets/sounds/ting.mp3
      await _player.stop();
      await _player.play(AssetSource('sounds/ting.mp3'));
    } catch (_) {
      // Nếu không có file thì phát âm thanh hệ thống + rung
      try {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.mediumImpact();
      } catch (_) {}
    }
  }
}

class ChatFreeApp extends StatelessWidget {
  const ChatFreeApp({super.key});
  @override Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: const NameGate());
  }
}

class NameGate extends StatefulWidget { const NameGate({super.key}); @override State<NameGate> createState() => _NameGateState(); }
class _NameGateState extends State<NameGate> {
  final c = TextEditingController(); bool loading=true;
  @override void initState(){ super.initState(); _check(); }
  Future<void> _check() async { final p=await SharedPreferences.getInstance(); final s=p.getString('my_phone'); if(s!=null && mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> HomeScreen(myPhone: s))); else setState(()=>loading=false); }
  Future<void> _enter() async {
    final phone=c.text.trim(); if(!RegExp(r'^0\d{9}$').hasMatch(phone)) return;
    final doc=await FirebaseFirestore.instance.collection('users').doc(phone).get();
    if(!doc.exists){ await FirebaseFirestore.instance.collection('users').doc(phone).set({'phone':phone,'friends':[],'lastSeen':FieldValue.serverTimestamp()}); }
    else{ await FirebaseFirestore.instance.collection('users').doc(phone).update({'lastSeen':FieldValue.serverTimestamp()}); }
    final p=await SharedPreferences.getInstance(); await p.setString('my_phone', phone);
    if(!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=> HomeScreen(myPhone: phone)));
  }
  @override Widget build(BuildContext context){
    if(loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(backgroundColor: zaloBlue, body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.chat_bubble, size: 70, color: Colors.white), const Text('Lung Chat', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [
        TextField(controller: c, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)], decoration: InputDecoration(labelText: 'SĐT', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), counterText: "")),
        const SizedBox(height: 10), SizedBox(width: double.infinity, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: zaloBlue), onPressed: _enter, child: const Text('TIẾP TỤC')))
      ]))
    ])))));
  }
}

class HomeScreen extends StatefulWidget { final String myPhone; const HomeScreen({super.key, required this.myPhone}); @override State<HomeScreen> createState()=> _HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final searchC=TextEditingController();
  final Map<String, StreamSubscription> _subs={}; final Map<String, StreamSubscription> _onlineSubs={};
  final Map<String, bool> _hasUnread={}; final Map<String, String> _lastMsg={};
  Map<String, String> _avatars={}; Map<String, String> _nicknames={}; Map<String, Timestamp?> _lastSeens={};
  late TabController _tab; Timer? _timer;

  @override void initState(){ super.initState(); WidgetsBinding.instance.addObserver(this); _tab=TabController(length: 2, vsync: this); _loadCustom(); _startPresence(); }
  void _startPresence(){ _update(); _timer=Timer.periodic(const Duration(seconds: 30), (_)=> _update()); }
  Future<void> _update() async { try{ await FirebaseFirestore.instance.collection('users').doc(widget.myPhone).update({'lastSeen':FieldValue.serverTimestamp()}); }catch(_){} }
  bool _isOnline(Timestamp? t){ if(t==null) return false; return DateTime.now().difference(t.toDate()).inSeconds < 120; }
  String _chatId(String a,String b){ final l=[a,b]..sort(); return '${l[0]}__${l[1]}'; }

  Future<void> _loadCustom() async {
    final p=await SharedPreferences.getInstance(); Map<String,String> av={}, nick={};
    for(final k in p.getKeys()){ if(k.startsWith('avatar_')) av[k.replaceAll('avatar_', '')]=p.getString(k)??''; if(k.startsWith('nickname_')) nick[k.replaceAll('nickname_', '')]=p.getString(k)??''; }
    try{ final doc=await FirebaseFirestore.instance.collection('user_custom').doc(widget.myPhone).get(); if(doc.exists){ final d=doc.data() as Map; if(d['avatars']!=null) av.addAll(Map<String,String>.from(d['avatars'])); if(d['nicknames']!=null) nick.addAll(Map<String,String>.from(d['nicknames'])); } }catch(_){}
    if(mounted) setState((){ _avatars=av; _nicknames=nick; });
  }

  void _setup(List<String> friends) async {
    final p=await SharedPreferences.getInstance();
    for(final f in friends){
      _hasUnread.putIfAbsent(f, ()=>false); _lastMsg.putIfAbsent(f, ()=> '');
      if(!_subs.containsKey(f)){
        final cid=_chatId(widget.myPhone, f);
        _subs[f]=FirebaseFirestore.instance.collection('private_chats').doc(cid).collection('messages').orderBy('time', descending: true).limit(1).snapshots().listen((snap){
          if(snap.docs.isEmpty) return; final data=snap.docs.first.data() as Map; final from=data['from']; final txt=data['text']??''; final time=(data['time'] as Timestamp?)?.millisecondsSinceEpoch??0;
          final lastRead=p.getInt('lastRead_$cid')??0;
          if(mounted){ bool img=data['imgs']!=null && (data['imgs'] as List).isNotEmpty; int cnt=img? (data['imgs'] as List).length:0; setState(()=> _lastMsg[f]= img? (cnt==1? '[Hình ảnh]' : '[$cnt hình ảnh]') : txt.toString()); }
          // SỬA: THÊM ÂM THANH KHI CÓ TIN NHẮN MỚI
          if(from!=widget.myPhone && time>lastRead) {
            if(mounted) setState(()=> _hasUnread[f]=true);
            SoundService.play();
          }
        });
      }
      if(!_onlineSubs.containsKey(f)){
        _onlineSubs[f]=FirebaseFirestore.instance.collection('users').doc(f).snapshots().listen((doc){
          if(!doc.exists) return; final ts=(doc.data() as Map?)?['lastSeen'] as Timestamp?; if(mounted) setState(()=> _lastSeens[f]=ts);
        });
      }
    }
  }

  Future<void> _open(String f) async { final cid=_chatId(widget.myPhone, f); final p=await SharedPreferences.getInstance(); await p.setInt('lastRead_$cid', DateTime.now().millisecondsSinceEpoch); setState(()=> _hasUnread[f]=false); if(!mounted) return; Navigator.push(context, MaterialPageRoute(builder: (_)=> ChatScreen(myPhone: widget.myPhone, peerPhone: f, nickname: _nicknames[f], avatarB64: _avatars[f]))); }

  @override void dispose(){ WidgetsBinding.instance.removeObserver(this); _timer?.cancel(); for(final s in _subs.values){ s.cancel(); } for(final s in _onlineSubs.values){ s.cancel(); } _tab.dispose(); super.dispose(); }

  @override Widget build(BuildContext context){
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: zaloBlue, foregroundColor: Colors.white, title: Row(children: [const Icon(Icons.search), const SizedBox(width: 8), Expanded(child: TextField(controller: searchC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Tìm bạn...', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none)))]), bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'TIN NHẮN'), Tab(text: 'DANH BẠ')])),
      body: Column(children: [
        StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('friend_requests').where('to', isEqualTo: widget.myPhone).where('status', isEqualTo: 'pending').snapshots(), builder: (c,s){ if(s.data==null || s.data!.docs.isEmpty) return const SizedBox(); return Column(children: s.data!.docs.map((d){ final data=d.data() as Map; String from=data['from'].toString().split('_').first; return ListTile(title: Text(from), trailing: FilledButton(onPressed: () async { await FirebaseFirestore.instance.collection('users').doc(widget.myPhone).set({'friends':FieldValue.arrayUnion([from])}, SetOptions(merge: true)); await FirebaseFirestore.instance.collection('users').doc(from).set({'friends':FieldValue.arrayUnion([widget.myPhone])}, SetOptions(merge: true)); await FirebaseFirestore.instance.collection('friend_requests').doc(d.id).update({'status':'accepted'}); }, child: const Text('Đồng ý'))); }).toList()); }),
        Expanded(child: StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('users').doc(widget.myPhone).snapshots(), builder: (c,my){ if(!my.hasData) return const Center(child: CircularProgressIndicator()); final data=my.data!.data() as Map<String,dynamic>?; final friends=List<String>.from(data?['friends']??[]); if(friends.isEmpty) return const Center(child: Text('Chưa có bạn')); _setup(friends); return ListView.separated(separatorBuilder: (_,__ )=> const Divider(height: 1), itemCount: friends.length, itemBuilder: (_,i){ final f=friends[i].split('_').first; final nick=_nicknames[f]??f; final av=_avatars[f]; final online=_isOnline(_lastSeens[f]); final last=_lastMsg[f]??''; return ListTile(leading: Stack(children: [CircleAvatar(radius: 26, backgroundImage: av!=null && av.isNotEmpty? MemoryImage(base64Decode(av)) : null, child: av==null || av.isEmpty? Text(nick[0].toUpperCase()) : null), if(online) Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))]), title: Row(children: [Expanded(child: Text(nick, style: const TextStyle(fontWeight: FontWeight.w600))), if(online) const Text(' • Online', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold))]), subtitle: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: ()=> _open(f)); }); })),
      ]),
    );
  }
}

class ZaloGrid extends StatelessWidget {
  final List<String> imgs; final Function(int) onTap;
  const ZaloGrid({super.key, required this.imgs, required this.onTap});
  @override Widget build(BuildContext context){
    final c=imgs.length; const w=210.0; const r=8.0;
    Widget imgW(int i, {double? h, double? wh}) => ClipRRect(borderRadius: BorderRadius.circular(r), child: Image.memory(base64Decode(imgs[i]), width: wh, height: h, fit: BoxFit.cover));
    if(c==1) return GestureDetector(onTap: ()=> onTap(0), child: imgW(0, wh: w));
    if(c==2) return SizedBox(width: w, child: Row(children: [for(int i=0;i<2;i++) Expanded(child: GestureDetector(onTap: ()=> onTap(i), child: Padding(padding: EdgeInsets.only(left: i==1?2:0, right: i==0?2:0), child: imgW(i, h: 120))))]));
    if(c==3) return SizedBox(width: w, height: 150, child: Row(children: [Expanded(flex: 6, child: GestureDetector(onTap: ()=> onTap(0), child: Padding(padding: const EdgeInsets.only(right: 2), child: imgW(0, h: 150)))), Expanded(flex: 4, child: Column(children: [for(int i=1;i<3;i++) Expanded(child: GestureDetector(onTap: ()=> onTap(i), child: Padding(padding: EdgeInsets.only(top: i==2?2:0, left: 2), child: imgW(i))))]))]));
    if(c==4) return SizedBox(width: w, height: 150, child: Column(children: [Expanded(child: Row(children: [for(int i=0;i<2;i++) Expanded(child: GestureDetector(onTap: ()=> onTap(i), child: Padding(padding: EdgeInsets.only(right: i==0?2:0, left: i==1?2:0, bottom: 2), child: imgW(i))))])), Expanded(child: Row(children: [for(int i=2;i<4;i++) Expanded(child: GestureDetector(onTap: ()=> onTap(i), child: Padding(padding: EdgeInsets.only(right: i==2?2:0, left: i==3?2:0, top: 2), child: imgW(i))))]))]));
    return SizedBox(width: w, child: Wrap(spacing: 2, runSpacing: 2, children: List.generate(c>6?6:c, (i){ bool last=i==5 && c>6; return GestureDetector(onTap: ()=> onTap(i), child: Stack(children: [imgW(i, wh: (w-4)/3, h: (w-4)/3), if(last) Container(width: (w-4)/3, height: (w-4)/3, decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(r)), child: Center(child: Text('+${c-5}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))])); })));
  }
}

class ZaloBubble extends StatelessWidget {
  final bool isMe; final String? text; final List<String>? imgs; final Function(int)? onTapImg;
  const ZaloBubble({super.key, required this.isMe, this.text, this.imgs, this.onTapImg});
  @override Widget build(BuildContext context){
    if(imgs!=null && imgs!.isNotEmpty) return Container(margin: EdgeInsets.only(left: isMe?50:8, right: isMe?8:50, top: 4, bottom: 4), child: Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: ZaloGrid(imgs: imgs!, onTap: (i)=> onTapImg?.call(i))));
    if(text==null || text!.isEmpty) return const SizedBox();
    return Container(margin: EdgeInsets.only(left: isMe?50:12, right: isMe?12:50, top: 4, bottom: 4), child: Align(alignment: isMe? Alignment.centerRight:Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: isMe? zaloBlue:Colors.white, borderRadius: BorderRadius.circular(16)), child: Text(text!, style: TextStyle(color: isMe? Colors.white:Colors.black87)))));
  }
}

class ChatScreen extends StatefulWidget { final String myPhone, peerPhone; final String? nickname, avatarB64; const ChatScreen({super.key, required this.myPhone, required this.peerPhone, this.nickname, this.avatarB64}); @override State<ChatScreen> createState()=> _ChatScreenState(); }
class _ChatScreenState extends State<ChatScreen> {
  final _text=TextEditingController(); final _scroll=ScrollController(); bool _sending=false; bool _emoji=false;
  int _lastCount = 0;
  String get chatId { final a=[widget.myPhone, widget.peerPhone]..sort(); return '${a[0]}__${a[1]}'; }

  Future<void> _send({List<String>? imgs}) async {
    if(_sending) return; final t=_text.text.trim(); if(t.isEmpty && (imgs==null || imgs.isEmpty)) return;
    setState(()=> _sending=true); _text.clear();
    // Không phát tiếng gửi để đỡ ồn, chỉ phát khi nhận. Nếu muốn có tiếng gửi thì mở dòng dưới:
    // SoundService.play();
    await FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').add({'from':widget.myPhone,'text':t,'imgs':imgs,'time':FieldValue.serverTimestamp()});
    setState(()=> _sending=false);
  }

  Future<void> _pick() async {
    if(_sending) return;
    final xs=await ImagePicker().pickMultiImage();
    if(xs.isEmpty) return;
    setState(()=> _sending=true);
    List<String> list=[];
    for(final x in xs.take(9)){
      try{
        var bytes = await FlutterImageCompress.compressWithFile(x.path, quality: 35, minWidth: 1024, minHeight: 1024);
        bytes??= await File(x.path).readAsBytes();
        if(bytes.length > 450*1024){
          bytes = await FlutterImageCompress.compressWithFile(x.path, quality: 15, minWidth: 700, minHeight: 700)?? bytes;
        }
        if(bytes.length < 800*1024){
          list.add(base64Encode(bytes));
        }
      }catch(e){ print(e); }
    }
    setState(()=> _sending=false);
    if(list.isNotEmpty) await _send(imgs: list);
    else if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hình quá nặng, thử chọn hình khác')));
  }

  void _open(List<String> imgs, int idx){ Navigator.push(context, MaterialPageRoute(builder: (_)=> FullImage(imgs: imgs, idx: idx))); }
  Future<void> _call() async { final url=Uri.parse('https://meet.jit.si/$chatId'); if(await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication); }

  @override Widget build(BuildContext context){
    return Scaffold(
      backgroundColor: zaloBg, resizeToAvoidBottomInset: true,
      appBar: AppBar(backgroundColor: Colors.white, foregroundColor: Colors.black, title: Row(children: [
        CircleAvatar(backgroundImage: widget.avatarB64!=null && widget.avatarB64!.isNotEmpty? MemoryImage(base64Decode(widget.avatarB64!)) : null, child: widget.avatarB64==null? Text((widget.nickname??widget.peerPhone)[0].toUpperCase()) : null),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.nickname??widget.peerPhone, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          StreamBuilder<DocumentSnapshot>(stream: FirebaseFirestore.instance.collection('users').doc(widget.peerPhone).snapshots(), builder: (_,s){ final ts=(s.data?.data() as Map?)?['lastSeen'] as Timestamp?; final on=ts!=null && DateTime.now().difference(ts.toDate()).inSeconds<120; return Text(on? 'Đang hoạt động':'Offline', style: TextStyle(fontSize: 11, color: on? Colors.green:Colors.grey)); })
        ]))
      ]), actions: [IconButton(onPressed: _call, icon: const Icon(Icons.call, color: zaloBlue))]),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('private_chats').doc(chatId).collection('messages').orderBy('time').snapshots(), builder: (c,snap){
          if(!snap.hasData) return const Center(child: CircularProgressIndicator());

          // LOGIC PHÁT ÂM THANH KHI CÓ TIN NHẮN MỚI TRONG CHAT
          if(snap.data!.docs.isNotEmpty){
            if(_lastCount!= 0 && snap.data!.docs.length > _lastCount){
              final lastDoc = snap.data!.docs.last.data() as Map;
              if(lastDoc['from']!= widget.myPhone){
                SoundService.play();
              }
            }
            _lastCount = snap.data!.docs.length;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) { if(_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });
          return ListView.builder(controller: _scroll, padding: const EdgeInsets.symmetric(vertical: 10), itemCount: snap.data!.docs.length, itemBuilder: (_,i){
            final m=snap.data!.docs[i].data() as Map; final isMe=m['from']==widget.myPhone;
            List<String>? imgs; if(m['imgs']!=null) imgs=List<String>.from(m['imgs']); if(m['img']!=null) imgs=[m['img'] as String];
            final txt=(m['text']??'').toString();
            if(imgs!=null && imgs.isNotEmpty) return ZaloBubble(isMe: isMe, imgs: imgs, onTapImg: (idx)=> _open(imgs!, idx));
            if(txt.isNotEmpty) return ZaloBubble(isMe: isMe, text: txt);
            return const SizedBox();
          });
        })),
        if(_emoji) SizedBox(height: 250, child: EmojiPicker(textEditingController: _text, config: const Config())),
        SafeArea(child: Container(color: Colors.white, padding: const EdgeInsets.all(4), child: Row(children: [
          IconButton(onPressed: ()=> setState(()=> _emoji=!_emoji), icon: const Icon(Icons.emoji_emotions_outlined)),
          IconButton(onPressed: _sending? null : _pick, icon: _sending? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image)),
          Expanded(child: Container(decoration: BoxDecoration(color: zaloBg, borderRadius: BorderRadius.circular(20)), child: TextField(controller: _text, decoration: const InputDecoration(hintText: 'Tin nhắn', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8))))),
          const SizedBox(width: 4),
          GestureDetector(onTap: _sending? null : ()=> _send(), child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _sending? Colors.grey:zaloBlue, shape: BoxShape.circle), child: const Icon(Icons.send, color: Colors.white, size: 18))),
        ]))),
      ]),
    );
  }
}

class FullImage extends StatefulWidget { final List<String> imgs; final int idx; const FullImage({super.key, required this.imgs, this.idx=0}); @override State<FullImage> createState()=> _FullImageState(); }
class _FullImageState extends State<FullImage> {
  late int cur; late PageController pc;
  @override void initState(){ super.initState(); cur=widget.idx; pc=PageController(initialPage: cur); }
  @override void dispose(){ pc.dispose(); super.dispose(); }
  Future<void> _save() async {
    try{ final b=base64Decode(widget.imgs[cur]); if(Platform.isWindows){ final dir=await getDownloadsDirectory(); final path='${dir!.path}/img_${DateTime.now().millisecondsSinceEpoch}.png'; await File(path).writeAsBytes(b); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu $path'))); } else { await Gal.requestAccess(); final tmp=await getTemporaryDirectory(); final p='${tmp.path}/tmp.png'; await File(p).writeAsBytes(b); await Gal.putImage(p); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu'))); } }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi $e'))); }
  }
  @override Widget build(BuildContext context){
    return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), title: Text('${cur+1}/${widget.imgs.length}', style: const TextStyle(color: Colors.white)), actions: [IconButton(onPressed: _save, icon: const Icon(Icons.download, color: Colors.white))]), body: PageView.builder(controller: pc, itemCount: widget.imgs.length, onPageChanged: (i)=> setState(()=> cur=i), itemBuilder: (_,i)=> Center(child: InteractiveViewer(child: Image.memory(base64Decode(widget.imgs[i]))))));
  }
}
