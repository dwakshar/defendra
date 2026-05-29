import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/theme/widgets/empty_state.dart';
import '../../data/models/scan_record.dart';
import '../detail/detail_screen.dart';
import 'inbox_provider.dart';

// ---------------------------------------------------------------------------
// Root screen
// ---------------------------------------------------------------------------

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

// ---------------------------------------------------------------------------
// Filter tab row
// ---------------------------------------------------------------------------

class _FilterTabRow extends StatelessWidget {
  static const _tabs = [
    ('all', DefendraColors.text),
    ('scam', DefendraColors.scam),
    ('suspicious', DefendraColors.suspicious),
    ('safe', DefendraColors.safe),
  ];

  final int selected;
  final ValueChanged<int> onSelect;

  const _FilterTabRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            _Tab(
              label: _tabs[i].$1,
              accent: _tabs[i].$2,
              active: selected == i,
              onTap: () => onSelect(i),
            ),
            if (i < _tabs.length - 1) const SizedBox(width: 24),
          ],
        ],
      ),
    );
  }
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  int _filterIndex = 0;
  bool _searchExpanded = false;
  String _searchQuery = '';
  bool _permissionDenied = false;

  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(inboxNotifierProvider);
    debugPrint('[D6] build triggered — ${records.length} record(s)');
    final filtered = _applyFilter(records);

    return Scaffold(
      backgroundColor: DefendraColors.canvas,
      appBar: AppBar(
        backgroundColor: DefendraColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'inbox',
          style: DefendraType.body.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _searchExpanded ? Icons.close : Icons.search,
              color: DefendraColors.muted,
              size: 18,
            ),
            onPressed: _toggleSearch,
            splashRadius: 20,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Permission banner
          if (_permissionDenied) _PermissionBanner(onGrant: _requestPermission),

          // Filter tabs
          _FilterTabRow(
            selected: _filterIndex,
            onSelect: (i) => setState(() => _filterIndex = i),
          ),

          // Search bar
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, anim) => SizeTransition(
              sizeFactor: anim,
              alignment: Alignment.topCenter,
              child: child,
            ),
            child: _searchExpanded
                ? _SearchBar(
                    key: const ValueKey('search'),
                    controller: _searchController,
                    onChanged: (q) => setState(() => _searchQuery = q),
                  )
                : const SizedBox.shrink(key: ValueKey('no-search')),
          ),

          // Divider
          Container(height: 0.5, color: DefendraColors.border),

          // List
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(label: '~ no messages intercepted yet')
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final record = filtered[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailScreen(record: record),
                          ),
                        ),
                        child: Hero(
                          tag: 'scan_${record.id}',
                          child: Material(
                            color: Colors.transparent,
                            child: _ScanCard(record: record),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  List<ScanRecord> _applyFilter(List<ScanRecord> all) {
    var records = switch (_filterIndex) {
      1 => all.where((r) => r.verdict == Verdict.scam).toList(),
      2 => all.where((r) => r.verdict == Verdict.suspicious).toList(),
      3 => all.where((r) => r.verdict == Verdict.safe).toList(),
      _ => all,
    };

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      records = records
          .where(
            (r) =>
                r.sender.toLowerCase().contains(q) ||
                r.body.toLowerCase().contains(q),
          )
          .toList();
    }

    return records;
  }

  Future<void> _checkPermission() async {
    final status = await Permission.sms.status;
    if (mounted) setState(() => _permissionDenied = !status.isGranted);
  }

  Future<void> _requestPermission() async {
    final status = await Permission.sms.request();
    if (mounted) setState(() => _permissionDenied = !status.isGranted);
  }

  void _toggleSearch() {
    setState(() {
      _searchExpanded = !_searchExpanded;
      if (!_searchExpanded) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Permission banner
// ---------------------------------------------------------------------------

class _PermissionBanner extends StatelessWidget {
  final VoidCallback onGrant;

  const _PermissionBanner({required this.onGrant});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: DefendraColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'SMS permission required',
              style: DefendraType.label.copyWith(color: DefendraColors.text),
            ),
          ),
          TextButton(
            onPressed: onGrant,
            style: TextButton.styleFrom(
              foregroundColor: DefendraColors.scam,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Grant',
              style: DefendraType.label.copyWith(color: DefendraColors.scam),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan record card
// ---------------------------------------------------------------------------

class _ScanCard extends StatelessWidget {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final ScanRecord record;

  const _ScanCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DefendraColors.card,
        border: Border.all(color: DefendraColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Verdict dot with animated transition
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(record.verdict),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _dotColor(record.verdict),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Sender
              Expanded(
                child: Text(
                  record.sender,
                  style: DefendraType.mono.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              // Timestamp
              Text(
                _relativeTime(record.timestamp),
                style: DefendraType.monoSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            record.body,
            style: DefendraType.body.copyWith(
              color: DefendraColors.muted,
              fontSize: 13,
              height: 1.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Color _dotColor(Verdict verdict) => switch (verdict) {
    Verdict.safe => DefendraColors.safe,
    Verdict.suspicious => DefendraColors.suspicious,
    Verdict.scam => DefendraColors.scam,
  };

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day} ${_months[dt.month - 1]}';
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;

  final ValueChanged<String> onChanged;
  const _SearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autofocus: true,
        style: DefendraType.mono.copyWith(fontSize: 13),
        cursorColor: DefendraColors.muted,
        decoration: InputDecoration(
          hintText: 'search sender or body...',
          hintStyle: DefendraType.mono.copyWith(
            fontSize: 13,
            color: DefendraColors.muted,
          ),
          filled: true,
          fillColor: DefendraColors.card,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: DefendraColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: DefendraColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: DefendraColors.border),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;

  final Color accent;
  final bool active;
  final VoidCallback onTap;
  const _Tab({
    required this.label,
    required this.accent,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? accent : Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: DefendraType.monoSmall.copyWith(
            color: active ? DefendraColors.text : DefendraColors.muted,
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
