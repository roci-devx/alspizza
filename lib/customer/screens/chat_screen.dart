import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../core/widgets/ui.dart';
import '../state/session.dart';

/// Message the driver. Messages relay to the courier by SMS on the backend
/// (Twilio) — the customer only ever sees Al's.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  Order? _order;
  bool _sending = false;
  StreamSubscription<RealtimeEvent>? _sub;
  late final RealtimeClient _realtime;

  static const _quick = ['Please leave it at the door', 'I’m coming down', 'Call me when you’re here', 'Thank you!'];

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionStore>();
    _realtime = session.realtime;
    _realtime.subscribe('order:${widget.orderId}');
    _sub = _realtime.on('order:${widget.orderId}').listen((e) {
      if (e.event == 'chat.message') {
        final m = ChatMessage.fromJson(e.data as Json);
        if (_messages.every((x) => x.id != m.id)) setState(() => _messages = [..._messages, m]);
        _toBottom();
      } else if (e.event == 'order.updated') {
        setState(() => _order = Order.fromJson(e.data as Json));
      }
    });
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<SessionStore>().api;
    final res = await Future.wait([api.get('/orders/${widget.orderId}/messages'), api.get('/orders/${widget.orderId}')]);
    if (!mounted) return;
    setState(() {
      _messages = ((res[0]['messages'] as List?) ?? const []).map((e) => ChatMessage.fromJson(e as Json)).toList();
      _order = Order.fromJson(res[1]['order'] as Json);
    });
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  Future<void> _send([String? preset]) async {
    final body = (preset ?? _text.text).trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await context.read<SessionStore>().api.post('/orders/${widget.orderId}/messages', {'body': body});
      final m = ChatMessage.fromJson(res['message'] as Json);
      setState(() {
        if (_messages.every((x) => x.id != m.id)) _messages = [..._messages, m];
        _text.clear();
      });
      _toBottom();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _order?.delivery;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30), onPressed: () => context.pop()),
        title: Column(
          children: [
            Text(d?.driverName ?? 'Your driver'),
            Text(d?.driverVehicle ?? 'Al’s delivery', style: AlsText.body(12, color: AlsColors.muted)),
          ],
        ),
        actions: [if (d?.driverPhone != null) IconButton(icon: const Icon(Icons.call_rounded), onPressed: () => launchUrl(Uri.parse('tel:${d!.driverPhone}')))],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.forum_rounded, size: 56, color: AlsColors.orange),
                          const SizedBox(height: 12),
                          Text('Say hi to your driver', style: AlsText.display(22)),
                          const SizedBox(height: 6),
                          Text(
                            'Gate codes, drop-off spots, “I’m coming down” — they’ll get it right away.',
                            textAlign: TextAlign.center,
                            style: AlsText.body(14, color: AlsColors.muted),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(message: _messages[i]),
                  ),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quick.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ChoicePill(label: _quick[i], selected: false, onTap: () => _send(_quick[i])),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'Message your driver'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TapScale(
                    onTap: _send,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(color: AlsColors.orange, shape: BoxShape.circle),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: AlsColors.brown),
                            )
                          : const Icon(Icons.send_rounded, color: AlsColors.brown),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.sender == 'customer';
    if (message.sender == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.body,
            textAlign: TextAlign.center,
            style: AlsText.body(12, color: AlsColors.muted),
          ),
        ),
      );
    }
    return Reveal(
      offset: Offset(mine ? 0.15 : -0.15, 0),
      duration: const Duration(milliseconds: 320),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? AlsColors.orange : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 6),
              bottomRight: Radius.circular(mine ? 6 : 20),
            ),
            boxShadow: alsShadow,
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (message.sender == 'store') Text('Al’s team', style: AlsText.label(10, color: AlsColors.orangeDeep)),
              Text(message.body, style: AlsText.body(15, color: mine ? AlsColors.brown : AlsColors.ink)),
              const SizedBox(height: 2),
              Text(clock(message.createdAt), style: AlsText.body(10, color: mine ? AlsColors.brown.withValues(alpha: 0.6) : AlsColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
