import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const Color kGreen = Color(0xFF078B50);
const Color kDarkGreen = Color(0xFF056B3D);
const Color kMint = Color(0xFFE9F6EE);
const Color kPage = Color(0xFFF6FAF7);
const String kDeveloperPhone = '782375646';
const String kDeveloperFullPhone = '+967782375646';
const String kBucket = 'chat-media';

SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await LiveKitClient.initialize();

  final config = await AppConfig.load();
  var configured = false;
  if (config.url.isNotEmpty && config.key.isNotEmpty) {
    try {
      await Supabase.initialize(url: config.url, anonKey: config.key);
      configured = true;
    } catch (_) {
      configured = false;
    }
  }
  runApp(AliChatApp(configured: configured));
}

class AppConfig {
  const AppConfig(this.url, this.key);
  final String url;
  final String key;

  static Future<AppConfig> load() async {
    // The config is stored by the in-app setup screen using Supabase-independent storage.
    final prefs = await _Prefs.instance;
    return AppConfig(prefs.getString('supabase_url') ?? '',
        prefs.getString('supabase_key') ?? '');
  }
}

// Tiny wrapper avoids adding another dependency just for two configuration strings.
class _Prefs {
  static dynamic _instance;
  static Future<dynamic> get instance async {
    if (_instance != null) return _instance;
    // SharedPreferences is intentionally loaded lazily through its package.
    final prefs = await _loadPrefs();
    _instance = prefs;
    return prefs;
  }

  static Future<dynamic> _loadPrefs() async {
    // See pubspec: shared_preferences is not required; persist config in a local file instead.
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/ali_config.txt');
    if (!await file.exists()) return _SimplePrefs({});
    final lines = await file.readAsLines();
    return _SimplePrefs({
      'supabase_url': lines.isNotEmpty ? lines[0] : '',
      'supabase_key': lines.length > 1 ? lines[1] : '',
    }, file: file);
  }
}

class _SimplePrefs {
  _SimplePrefs(this.values, {this.file});
  final Map<String, String> values;
  final File? file;
  String? getString(String key) => values[key];
  Future<void> setPair(String url, String key) async {
    values['supabase_url'] = url;
    values['supabase_key'] = key;
    final dir = await getApplicationSupportDirectory();
    final target = file ?? File('${dir.path}/ali_config.txt');
    await target.writeAsString('$url\n$key');
  }
}

class AliChatApp extends StatelessWidget {
  const AliChatApp({super.key, required this.configured});
  final bool configured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'شات Ali',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
        scaffoldBackgroundColor: kPage,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: kDarkGreen,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: material.TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: configured ? const AuthGate() : const SetupPage(),
    );
  }
}

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    final url = _url.text.trim();
    final key = _key.text.trim();
    if (!url.startsWith('https://') || key.isEmpty) {
      setState(() => _error = 'أدخل رابط مشروع Supabase ومفتاح Publishable/anon الصحيح.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.initialize(url: url, anonKey: key);
      final prefs = await _Prefs.instance as _SimplePrefs;
      await prefs.setPair(url, key);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      );
    } catch (e) {
      setState(() => _error = 'تعذر الاتصال. راجع الرابط والمفتاح.\n$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const AliLogo(size: 92),
                const SizedBox(height: 18),
                const Text('إعداد شات Ali', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('اربط التطبيق بمشروع Supabase مرة واحدة لتفعيل الحسابات والمحادثات الحقيقية.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'رابط Supabase URL', hintText: 'https://xxxx.supabase.co')),
                const SizedBox(height: 12),
                TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'Publishable key أو anon key')),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _connect, child: Text(_busy ? 'جارٍ الربط...' : 'ربط التطبيق'))),
                const SizedBox(height: 12),
                const Text('ستجد خطوات إنشاء المشروع وتشغيل ملف SQL داخل README_AR.txt.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = db.auth.currentSession;
        if (session != null) return const HomePage();
        return const LoginPage();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController(text: '+967');
  final _otp = TextEditingController();
  final _name = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (!phone.startsWith('+') || phone.length < 9) {
      setState(() => _error = 'اكتب رقمك مع رمز الدولة، مثال: +9677xxxxxxx');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await db.auth.signInWithOtp(phone: phone, data: {'display_name': _name.text.trim()});
      setState(() => _sent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'فشل إرسال رمز التحقق: $e');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _verify() async {
    final phone = _phone.text.trim();
    final token = _otp.text.trim();
    if (token.length < 4) { setState(() => _error = 'أدخل رمز التحقق الذي وصلك.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await db.auth.verifyOTP(phone: phone, token: token, type: OtpType.sms);
      final user = db.auth.currentUser;
      if (user != null && _name.text.trim().isNotEmpty) {
        await db.from('profiles').upsert({'id': user.id, 'phone': phone, 'display_name': _name.text.trim()});
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'تعذر التحقق: $e');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  void dispose() { _phone.dispose(); _otp.dispose(); _name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(children: [
        const AliLogo(size: 100), const SizedBox(height: 18),
        const Text('مرحباً بك في شات Ali', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('تواصل، شارك، واستمتع', style: TextStyle(color: kDarkGreen)),
        const SizedBox(height: 28),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسمك الظاهر (عند التسجيل)')),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف الدولي')),
        if (_sent) ...[
          const SizedBox(height: 12),
          TextField(controller: _otp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رمز التحقق SMS')),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: _busy ? null : (_sent ? _verify : _sendOtp),
          child: Text(_busy ? 'يرجى الانتظار...' : (_sent ? 'تأكيد الرمز والدخول' : 'إرسال رمز التحقق')),
        )),
        if (_sent) TextButton(onPressed: _busy ? null : _sendOtp, child: const Text('إعادة إرسال الرمز')),
        const SizedBox(height: 18), const Text('يتطلب التسجيل تفعيل Phone Auth وضبط مزود رسائل SMS في Supabase.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    )))),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      ChatsTab(onOpen: _openChat),
      DiscoverTab(onOpen: _openChat),
      const SettingsTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [const AliLogo(size: 35), const SizedBox(width: 10), const Text('شات Ali', style: TextStyle(fontWeight: FontWeight.bold))]),
        actions: [IconButton(tooltip: 'المطور', icon: const Icon(Icons.workspace_premium_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DeveloperPage())))],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'المحادثات'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'الأشخاص'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }

  StreamSubscription<List<Map<String, dynamic>>>? _incomingCalls;
  final Set<String> _seenCalls = <String>{};

  @override
  void initState() {
    super.initState();
    final uid = db.auth.currentUser!.id;
    _incomingCalls = db.from('call_signals').stream(primaryKey: ['id']).eq('callee_id', uid).listen((rows) {
      for (final row in rows) {
        final id = row['id'].toString();
        if (row['status'] == 'ringing' && !_seenCalls.contains(id)) {
          _seenCalls.add(id);
          WidgetsBinding.instance.addPostFrameCallback((_) => _showIncomingCall(row));
        }
      }
    });
  }

  Future<void> _showIncomingCall(Map<String, dynamic> row) async {
    if (!mounted) return;
    final caller = await db.from('profiles').select('display_name').eq('id', row['caller_id']).maybeSingle();
    if (!mounted) return;
    final callerName = caller?['display_name']?.toString() ?? 'مستخدم شات Ali';
    final isVideo = row['call_type'] == 'video';
    final answer = await showDialog<bool>(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: Text(isVideo ? 'مكالمة فيديو واردة' : 'مكالمة صوتية واردة'),
      content: Text('المتصل: $callerName'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رفض')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('قبول')),
      ],
    ));
    try {
      await db.from('call_signals').update({'status': answer == true ? 'accepted' : 'rejected'}).eq('id', row['id']);
      if (answer == true && mounted) {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CallPage(chatId: row['chat_id'].toString(), title: callerName, video: isVideo, signalId: row['id'].toString())));
      }
    } catch (_) {}
  }

  @override
  void dispose() { _incomingCalls?.cancel(); super.dispose(); }

  Future<void> _openChat(String chatId, String title, {String? otherUserId}) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChatPage(chatId: chatId, title: title, otherUserId: otherUserId)));
  }
}

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key, required this.onOpen});
  final Future<void> Function(String, String, {String? otherUserId}) onOpen;
  @override
  Widget build(BuildContext context) {
    final uid = db.auth.currentUser!.id;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.from('chats').stream(primaryKey: ['id']).order('updated_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorPanel(message: 'تعذر تحميل المحادثات: ${snapshot.error}');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final chats = snapshot.data!;
        if (chats.isEmpty) return const EmptyPanel(icon: Icons.forum_outlined, title: 'لا توجد محادثات بعد', subtitle: 'افتح تبويب الأشخاص وابدأ محادثة جديدة.');
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: chats.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, index) {
            final chat = chats[index];
            return ChatListTile(chat: chat, uid: uid, onTap: (title, peer) => onOpen(chat['id'].toString(), title, otherUserId: peer));
          },
        );
      },
    );
  }
}

class ChatListTile extends StatelessWidget {
  const ChatListTile({super.key, required this.chat, required this.uid, required this.onTap});
  final Map<String, dynamic> chat;
  final String uid;
  final void Function(String, String?) onTap;

  Future<Map<String, dynamic>> _details() async {
    if (chat['is_group'] == true) return {'title': chat['title'] ?? 'مجموعة', 'peer': null};
    final rows = await db.from('chat_members').select('user_id').eq('chat_id', chat['id']);
    final peer = rows.cast<Map<String, dynamic>>().map((e) => e['user_id'].toString()).firstWhere((id) => id != uid, orElse: () => '');
    if (peer.isEmpty) return {'title': 'محادثة', 'peer': null};
    final profile = await db.from('profiles').select('display_name').eq('id', peer).maybeSingle();
    return {'title': profile?['display_name'] ?? 'مستخدم شات Ali', 'peer': peer};
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _details(),
    builder: (context, snapshot) {
      final title = snapshot.data?['title']?.toString() ?? (chat['is_group'] == true ? chat['title']?.toString() ?? 'مجموعة' : 'محادثة جديدة');
      final last = chat['last_message']?.toString() ?? 'ابدأ المحادثة الآن';
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        leading: CircleAvatar(backgroundColor: kMint, child: Icon(chat['is_group'] == true ? Icons.groups_rounded : Icons.person_rounded, color: kGreen)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_left, color: kGreen),
        onTap: () => onTap(title, snapshot.data?['peer'] as String?),
      );
    },
  );
}

class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key, required this.onOpen});
  final Future<void> Function(String, String, {String? otherUserId}) onOpen;
  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await db.from('profiles').select('id, phone, display_name').neq('id', db.auth.currentUser!.id).order('display_name').limit(150);
      _users = result.cast<Map<String, dynamic>>();
    } catch (e) { _error = e.toString(); }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) => '${u['display_name'] ?? ''} ${u['phone'] ?? ''}'.toLowerCase().contains(q)).toList();
  }

  Future<void> _start(Map<String, dynamic> user) async {
    try {
      final result = await db.rpc('create_direct_chat', params: {'p_other_user_id': user['id']});
      await widget.onOpen(result.toString(), user['display_name']?.toString() ?? 'محادثة', otherUserId: user['id'].toString());
    } catch (e) { _show('تعذر إنشاء المحادثة: $e'); }
  }

  Future<void> _createGroup() async {
    final title = TextEditingController();
    final phones = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إنشاء مجموعة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم المجموعة')),
        const SizedBox(height: 10),
        TextField(controller: phones, maxLines: 3, decoration: const InputDecoration(labelText: 'أرقام الأعضاء مفصولة بفاصلة', hintText: '+9677xxxxxxx, +9677yyyyyyy')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء'))],
    ));
    if (result != true) { title.dispose(); phones.dispose(); return; }
    try {
      final list = phones.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
      final members = <String>[];
      if (list.isNotEmpty) {
        final found = await db.from('profiles').select('id').inFilter('phone', list);
        members.addAll(found.map((e) => e['id'].toString()));
      }
      final chatId = await db.rpc('create_group_chat', params: {'p_title': title.text.trim().isEmpty ? 'مجموعة جديدة' : title.text.trim(), 'p_member_ids': members});
      await _load();
      if (mounted) await widget.onOpen(chatId.toString(), title.text.trim().isEmpty ? 'مجموعة جديدة' : title.text.trim());
    } catch (e) { _show('تعذر إنشاء المجموعة: $e'); }
    title.dispose(); phones.dispose();
  }

  void _show(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 8), child: Row(children: [
      Expanded(child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث بالاسم أو رقم الهاتف'))),
      const SizedBox(width: 8), IconButton.filledTonal(onPressed: _createGroup, icon: const Icon(Icons.group_add), tooltip: 'إنشاء مجموعة'),
    ])),
    if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
    else if (_error != null) Expanded(child: ErrorPanel(message: _error!))
    else if (_filtered.isEmpty) const Expanded(child: EmptyPanel(icon: Icons.person_search, title: 'لم نعثر على مستخدمين', subtitle: 'اطلب من صديقك إنشاء حساب في شات Ali.'))
    else Expanded(child: RefreshIndicator(onRefresh: _load, child: ListView.separated(
      padding: const EdgeInsets.all(12), itemCount: _filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final user = _filtered[i];
        return ListTile(
          leading: const CircleAvatar(backgroundColor: kMint, child: Icon(Icons.person, color: kGreen)),
          title: Text(user['display_name']?.toString().isNotEmpty == true ? user['display_name'].toString() : 'مستخدم شات Ali'),
          subtitle: Text(user['phone']?.toString() ?? ''),
          trailing: const Icon(Icons.chat, color: kGreen),
          onTap: () => _start(user),
        );
      },
    ))),
  ]);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.chatId, required this.title, this.otherUserId});
  final String chatId;
  final String title;
  final String? otherUserId;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  bool _sending = false;
  bool _recording = false;
  String? _recordPath;
  Timer? _readTimer;
  Stream<List<Map<String, dynamic>>> get _messages => db.from('messages').stream(primaryKey: ['id']).eq('chat_id', widget.chatId).order('created_at');

  @override
  void initState() {
    super.initState();
    _markRead();
    _readTimer = Timer.periodic(const Duration(seconds: 8), (_) => _markRead());
  }

  @override
  void dispose() {
    _text.dispose(); _scroll.dispose(); _recorder.dispose(); _readTimer?.cancel(); super.dispose();
  }

  Future<void> _markRead() async {
    try { await db.rpc('mark_chat_read', params: {'p_chat_id': widget.chatId}); } catch (_) {}
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    _text.clear();
    await _insertMessage(type: 'text', content: text);
  }

  Future<void> _insertMessage({required String type, String? content, String? path, String? name, String? mime}) async {
    try {
      await db.from('messages').insert({
        'chat_id': widget.chatId,
        'sender_id': db.auth.currentUser!.id,
        'message_type': type,
        'content': content,
        'attachment_path': path,
        'attachment_name': name,
        'mime_type': mime,
      });
      _markRead();
    } catch (e) { _snack('لم تُرسل الرسالة: $e'); }
  }

  Future<void> _uploadBytes(Uint8List bytes, String fileName, String mime, String type) async {
    if (_sending || bytes.isEmpty) return;
    setState(() => _sending = true);
    try {
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = '${widget.chatId}/${db.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await db.storage.from(kBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
      await _insertMessage(type: type, path: path, name: fileName, mime: mime);
    } catch (e) { _snack('تعذر رفع الملف: $e'); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (x == null) return;
    await _uploadBytes(await x.readAsBytes(), x.name, _mime(x.name.split('.').last) == 'application/octet-stream' ? 'image/jpeg' : _mime(x.name.split('.').last), 'image');
  }

  Future<void> _pickVideo() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    await _uploadBytes(await x.readAsBytes(), x.name, 'video/${x.name.split('.').last.toLowerCase()}', 'video');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) { _snack('تعذر قراءة الملف المختار.'); return; }
    await _uploadBytes(bytes, file.name, _mime(file.extension), 'file');
  }

  String _mime(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'pdf': return 'application/pdf';
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      case 'm4a': return 'audio/mp4';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) { _snack('اسمح للتطبيق باستخدام الميكروفون.'); return; }
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _recordPath!);
      if (mounted) setState(() => _recording = true);
    } catch (e) { _snack('تعذر بدء التسجيل: $e'); }
  }

  Future<void> _stopRecordingAndSend() async {
    try {
      final path = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      final actual = path ?? _recordPath;
      if (actual == null) return;
      final file = File(actual);
      if (!await file.exists()) return;
      await _uploadBytes(await file.readAsBytes(), 'رسالة صوتية.m4a', 'audio/mp4', 'audio');
      try { await file.delete(); } catch (_) {}
    } catch (e) { _snack('تعذر إرسال التسجيل: $e'); }
  }

  void _attachmentMenu() {
    showModalBottomSheet<void>(context: context, builder: (ctx) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo, color: kGreen), title: const Text('صورة'), onTap: () { Navigator.pop(ctx); _pickImage(); }),
      ListTile(leading: const Icon(Icons.video_library, color: kGreen), title: const Text('فيديو'), onTap: () { Navigator.pop(ctx); _pickVideo(); }),
      ListTile(leading: const Icon(Icons.attach_file, color: kGreen), title: const Text('ملف أو مستند'), onTap: () { Navigator.pop(ctx); _pickFile(); }),
    ])));
  }

  Future<void> _startCall({required bool video}) async {
    try {
      final members = await db.from('chat_members').select('user_id').eq('chat_id', widget.chatId);
      final me = db.auth.currentUser!.id;
      final peers = members.map((m) => m['user_id'].toString()).where((id) => id != me).toList();
      if (peers.isEmpty) { _snack('لا يوجد أعضاء آخرون في هذه المحادثة.'); return; }
      for (final peer in peers) {
        await db.from('call_signals').insert({
          'chat_id': widget.chatId, 'caller_id': me, 'callee_id': peer,
          'call_type': video ? 'video' : 'audio', 'status': 'ringing',
        });
      }
      if (mounted) {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CallPage(chatId: widget.chatId, title: widget.title, video: video)));
      }
    } catch (e) { _snack('تعذر بدء المكالمة: $e'); }
  }

  Future<void> _blockUser() async {
    final peer = widget.otherUserId;
    if (peer == null) { _snack('الحظر متاح في المحادثات الفردية فقط.'); return; }
    try {
      await db.from('user_blocks').upsert({'blocker_id': db.auth.currentUser!.id, 'blocked_id': peer});
      _snack('تم حظر المستخدم.');
    } catch (e) { _snack('تعذر الحظر: $e'); }
  }

  void _snack(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [const CircleAvatar(backgroundColor: kMint, child: Icon(Icons.person, color: kGreen)), const SizedBox(width: 9), Expanded(child: Text(widget.title, overflow: TextOverflow.ellipsis))]),
      actions: [
        IconButton(tooltip: 'مكالمة صوتية', onPressed: () => _startCall(video: false), icon: const Icon(Icons.call)),
        IconButton(tooltip: 'مكالمة فيديو', onPressed: () => _startCall(video: true), icon: const Icon(Icons.videocam)),
        PopupMenuButton<String>(onSelected: (v) { if (v == 'block') _blockUser(); if (v == 'share') Share.share('انضم إلى شات Ali'); }, itemBuilder: (_) => const [PopupMenuItem(value: 'block', child: Text('حظر المستخدم')), PopupMenuItem(value: 'share', child: Text('مشاركة التطبيق'))]),
      ],
    ),
    body: Column(children: [
      Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _messages,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorPanel(message: 'تعذر تحميل الرسائل: ${snapshot.error}');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final messages = snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });
          if (messages.isEmpty) return const EmptyPanel(icon: Icons.waving_hand, title: 'ابدأ الحديث', subtitle: 'أرسل أول رسالة إلى صديقك.');
          return ListView.builder(controller: _scroll, padding: const EdgeInsets.all(12), itemCount: messages.length, itemBuilder: (context, i) => MessageBubble(message: messages[i], mine: messages[i]['sender_id'] == db.auth.currentUser!.id));
        },
      )),
      if (_sending) const LinearProgressIndicator(minHeight: 2),
      SafeArea(top: false, child: Container(
        color: Colors.white, padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
        child: Row(children: [
          IconButton(onPressed: _attachmentMenu, icon: const Icon(Icons.add_circle_outline, color: kGreen)),
          Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: const InputDecoration(hintText: 'اكتب رسالة...', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11)))),
          IconButton(onPressed: _recording ? _stopRecordingAndSend : _startRecording, icon: Icon(_recording ? Icons.stop_circle : Icons.mic, color: _recording ? Colors.red : kGreen)),
          IconButton(onPressed: _sending ? null : _sendText, icon: const Icon(Icons.send_rounded, color: kGreen)),
        ]),
      )),
    ]),
  );
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.mine});
  final Map<String, dynamic> message;
  final bool mine;

  Future<String> _signedUrl(String path) => db.storage.from(kBucket).createSignedUrl(path, 3600);

  @override
  Widget build(BuildContext context) {
    final type = message['message_type']?.toString() ?? 'text';
    final created = DateTime.tryParse(message['created_at']?.toString() ?? '');
    final time = created == null ? '' : DateFormat('h:mm a').format(created.toLocal());
    final bg = mine ? const Color(0xFFDDF4E5) : Colors.white;
    Widget content;
    if (type == 'text') {
      content = Text(message['content']?.toString() ?? '', style: const TextStyle(fontSize: 15));
    } else {
      final path = message['attachment_path']?.toString() ?? '';
      content = FutureBuilder<String>(future: _signedUrl(path), builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('تعذر تحميل المرفق');
        if (!snapshot.hasData) return const SizedBox(width: 170, height: 54, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        final url = snapshot.data!;
        if (type == 'image') return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('تعذر عرض الصورة')));
        if (type == 'audio') return AudioMessage(url: url);
        return InkWell(onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(type == 'video' ? Icons.video_file : Icons.insert_drive_file, color: kGreen, size: 30), const SizedBox(width: 8), Flexible(child: Text(message['attachment_name']?.toString() ?? 'ملف', maxLines: 2, overflow: TextOverflow.ellipsis)), const Icon(Icons.open_in_new, size: 17)]));
      });
    }
    return Align(alignment: mine ? Alignment.centerLeft : Alignment.centerRight, child: Container(
      constraints: const BoxConstraints(maxWidth: 300), margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 5)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        content,
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(time, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          if (mine) FutureBuilder<List<Map<String, dynamic>>>(
            future: db.from('message_reads').select('read_at').eq('message_id', message['id']).limit(1),
            builder: (context, snapshot) => Icon(snapshot.hasData && snapshot.data!.isNotEmpty ? Icons.done_all : Icons.done, size: 14, color: snapshot.hasData && snapshot.data!.isNotEmpty ? kGreen : Colors.black45),
          ),
        ]),
      ]),
    ));
  }
}

class AudioMessage extends StatefulWidget {
  const AudioMessage({super.key, required this.url});
  final String url;
  @override
  State<AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<AudioMessage> {
  final _player = AudioPlayer();
  bool _playing = false;
  @override
  void initState() { super.initState(); _player.onPlayerComplete.listen((_) { if (mounted) setState(() => _playing = false); }); }
  @override
  void dispose() { _player.dispose(); super.dispose(); }
  Future<void> _toggle() async {
    if (_playing) { await _player.pause(); setState(() => _playing = false); }
    else { await _player.play(UrlSource(widget.url)); setState(() => _playing = true); }
  }
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: _toggle, icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, color: kGreen, size: 34)), const Text('رسالة صوتية')]);
}

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.chatId, required this.title, required this.video, this.signalId});
  final String chatId;
  final String title;
  final bool video;
  final String? signalId;
  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  Room? _room;
  Timer? _refresh;
  bool _busy = true;
  bool _muted = false;
  bool _camera = false;
  String? _error;

  @override
  void initState() { super.initState(); _connect(); }

  Future<void> _connect() async {
    try {
      final response = await db.functions.invoke('livekit-token', body: {'chat_id': widget.chatId});
      final data = response.data as Map<String, dynamic>;
      final url = data['url']?.toString() ?? '';
      final token = data['token']?.toString() ?? '';
      if (url.isEmpty || token.isEmpty) throw Exception('لم يرجع خادم المكالمات رابطاً ورمزاً صالحين.');
      final room = Room();
      await room.connect(url, token, roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
      final participant = room.localParticipant;
      if (participant == null) throw Exception('تعذر الوصول إلى مشارك المكالمة.');
      await participant.setMicrophoneEnabled(true);
      if (widget.signalId != null) {
        await db.from('call_signals').update({'status': 'accepted'}).eq('id', widget.signalId!);
      }
      if (widget.video) {
        try { await participant.setCameraEnabled(true); _camera = true; } catch (_) {}
      }
      if (!mounted) { await room.disconnect(); return; }
      setState(() { _room = room; _busy = false; });
      _refresh = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    } catch (e) {
      if (mounted) setState(() { _error = 'تعذر بدء المكالمة. تأكد من نشر دالة LiveKit وضبط مفاتيحها.\n$e'; _busy = false; });
    }
  }

  Future<void> _toggleMic() async {
    final room = _room; if (room == null) return;
    _muted = !_muted;
    final participant = room.localParticipant;
    if (participant == null) return;
    await participant.setMicrophoneEnabled(!_muted);
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    final room = _room; if (room == null) return;
    _camera = !_camera;
    final participant = room.localParticipant;
    if (participant == null) return;
    await participant.setCameraEnabled(_camera);
    if (mounted) setState(() {});
  }

  Future<void> _end() async {
    _refresh?.cancel();
    await _room?.disconnect();
    if (widget.signalId != null) {
      try { await db.from('call_signals').update({'status': 'ended'}).eq('id', widget.signalId!); } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() { _refresh?.cancel(); _room?.disconnect(); super.dispose(); }

  Widget _remoteVideo() {
    final room = _room;
    if (room == null) return const SizedBox.shrink();
    for (final participant in room.remoteParticipants.values) {
      final tracks = participant.videoTrackPublications;
      if (tracks.isNotEmpty && tracks.first.track != null) {
        return ClipRRect(borderRadius: BorderRadius.circular(20), child: VideoTrackRenderer(tracks.first.track!));
      }
    }
    return const Center(child: Icon(Icons.person, size: 100, color: Colors.white70));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF10251B),
    appBar: AppBar(backgroundColor: const Color(0xFF10251B), foregroundColor: Colors.white, title: Text(widget.video ? 'مكالمة فيديو' : 'مكالمة صوتية')),
    body: SafeArea(child: Column(children: [
      Expanded(child: Center(child: _busy ? const CircularProgressIndicator(color: Colors.white) : _error != null ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white))) : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (widget.video) Expanded(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: _remoteVideo())))
        else const CircleAvatar(radius: 62, backgroundColor: kGreen, child: Icon(Icons.person, size: 64, color: Colors.white)),
        const SizedBox(height: 18), Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('متصل بغرفة المكالمة', style: TextStyle(color: Colors.white70)),
      ]))),
      if (_error == null) Padding(padding: const EdgeInsets.fromLTRB(22, 12, 22, 28), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _CallButton(icon: _muted ? Icons.mic_off : Icons.mic, label: 'الميكروفون', onTap: _busy ? null : _toggleMic),
        if (widget.video) _CallButton(icon: _camera ? Icons.videocam : Icons.videocam_off, label: 'الكاميرا', onTap: _busy ? null : _toggleCamera),
        _CallButton(icon: Icons.call_end, label: 'إنهاء', color: Colors.red, onTap: _end),
      ])),
    ])),
  );
}

class _CallButton extends StatelessWidget {
  const _CallButton({required this.icon, required this.label, required this.onTap, this.color = kGreen});
  final IconData icon; final String label; final VoidCallback? onTap; final Color color;
  @override
  Widget build(BuildContext context) => Column(children: [CircleAvatar(radius: 28, backgroundColor: color, child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white))), const SizedBox(height: 6), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))]);
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { _profile = await db.from('profiles').select().eq('id', db.auth.currentUser!.id).maybeSingle(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }
  Future<void> _editName() async {
    final c = TextEditingController(text: _profile?['display_name']?.toString() ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('تعديل الاسم'), content: TextField(controller: c, decoration: const InputDecoration(labelText: 'الاسم الظاهر')), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))]));
    if (ok == true && c.text.trim().isNotEmpty) {
      try { await db.from('profiles').update({'display_name': c.text.trim()}).eq('id', db.auth.currentUser!.id); await _load(); } catch (e) { _snack(e.toString()); }
    }
    c.dispose();
  }
  void _snack(String t) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [const CircleAvatar(radius: 30, backgroundColor: kMint, child: Icon(Icons.person, color: kGreen, size: 30)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_loading ? '...' : _profile?['display_name']?.toString() ?? 'مستخدم شات Ali', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text(db.auth.currentUser?.phone ?? '', style: const TextStyle(color: Colors.black54))])), IconButton(onPressed: _editName, icon: const Icon(Icons.edit, color: kGreen))]))),
    const SizedBox(height: 10),
    _setting(Icons.privacy_tip_outlined, 'الخصوصية والأمان', 'إدارة الحظر وحماية حسابك', () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BlocksPage()))),
    _setting(Icons.notifications_outlined, 'الإشعارات', 'رسائل فورية أثناء فتح التطبيق؛ إشعارات الخلفية تحتاج ربط مزود Push', () => _snack('إشعارات الخلفية تحتاج إعداد FCM أو OneSignal ومفاتيح المشروع.')),
    _setting(Icons.palette_outlined, 'المظهر', 'أبيض وأخضر خافت', () => _snack('المظهر الحالي: أبيض وأخضر خافت.')),
    _setting(Icons.share_outlined, 'مشاركة التطبيق', 'شارك شات Ali مع أصدقائك', () => Share.share('جرّب تطبيق شات Ali للتواصل ومشاركة الملفات.')),
    _setting(Icons.workspace_premium_outlined, 'المطور علي النجار', 'للتواصل والاستفسار', () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DeveloperPage()))),
    _setting(Icons.info_outline, 'حول التطبيق', 'شات Ali — تطوير علي النجار', () => showAboutDialog(context: context, applicationName: 'شات Ali', applicationVersion: '1.0.0', children: const [Text('تطبيق دردشة عربي يعمل عبر Supabase وLiveKit.')])) ,
    const SizedBox(height: 12),
    OutlinedButton.icon(onPressed: () async { await db.auth.signOut(); }, icon: const Icon(Icons.logout), label: const Text('تسجيل الخروج')),
  ]);
  Widget _setting(IconData icon, String title, String sub, VoidCallback tap) => Card(margin: const EdgeInsets.symmetric(vertical: 5), child: ListTile(leading: Icon(icon, color: kGreen), title: Text(title), subtitle: Text(sub, style: const TextStyle(fontSize: 11)), trailing: const Icon(Icons.chevron_left), onTap: tap));
}

class BlocksPage extends StatefulWidget {
  const BlocksPage({super.key});
  @override
  State<BlocksPage> createState() => _BlocksPageState();
}
class _BlocksPageState extends State<BlocksPage> {
  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await db.from('user_blocks').select('blocked_id, profiles!user_blocks_blocked_id_fkey(display_name, phone)').eq('blocker_id', db.auth.currentUser!.id);
    return rows.cast<Map<String, dynamic>>();
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('المستخدمون المحظورون')), body: FutureBuilder<List<Map<String, dynamic>>>(future: _load(), builder: (context, s) {
    if (!s.hasData) return const Center(child: CircularProgressIndicator());
    if (s.data!.isEmpty) return const EmptyPanel(icon: Icons.verified_user, title: 'لا يوجد مستخدمون محظورون', subtitle: 'قائمة الحظر فارغة.');
    return ListView(children: s.data!.map((row) { final profile = row['profiles'] as Map<String, dynamic>? ?? {}; return ListTile(title: Text(profile['display_name']?.toString() ?? 'مستخدم'), subtitle: Text(profile['phone']?.toString() ?? ''), trailing: TextButton(onPressed: () async { await db.from('user_blocks').delete().eq('blocker_id', db.auth.currentUser!.id).eq('blocked_id', row['blocked_id']); setState(() {}); }, child: const Text('إلغاء الحظر'))); }).toList());
  }));
}

class DeveloperPage extends StatelessWidget {
  const DeveloperPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المطور علي النجار')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const AliLogo(size: 120), const SizedBox(height: 18), const Text('المطور علي النجار', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('للتواصل والاستفسار'), const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => launchUrl(Uri.parse('tel:$kDeveloperFullPhone')), icon: const Icon(Icons.call), label: const Text(kDeveloperPhone))),
      const SizedBox(height: 8), OutlinedButton.icon(onPressed: () => Share.share('تواصل مع المطور علي النجار: $kDeveloperFullPhone'), icon: const Icon(Icons.share), label: const Text('مشاركة رقم المطور')),
      const SizedBox(height: 24), const Text('معاً نصنع الأفضل', style: TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
    ]))),
  );
}

class AliLogo extends StatelessWidget {
  const AliLogo({super.key, this.size = 60});
  final double size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF12A964), kDarkGreen])), child: Icon(Icons.forum_rounded, color: Colors.white, size: size * .55));
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon; final String title; final String subtitle;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 64, color: kGreen.withOpacity(.6)), const SizedBox(height: 12), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54))])));
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(20), Chip