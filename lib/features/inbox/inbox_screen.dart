import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/theme/widgets/empty_state.dart';
import '../../core/theme/widgets/shimmer.dart';
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

class _InboxScreenState extends ConsumerState<InboxScreen> {
  int _filterIndex = 0;
  bool _searchExpanded = false;
  String _searchQuery = '';
  bool _permissionDenied = false;
  bool _showShimmer = true;

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPermission();
    // Brief branded shimmer on first load regardless of Hive speed
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showShimmer = false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(inboxNotifierProvider);
    final filtered = _applyFilter(records);

    return Scaffold(
      backgroundColor: context.dCanvas,
      appBar: AppBar(
        backgroundColor: context.dCanvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('INBOX'),
        actions: [
          IconButton(
            icon: Icon(
              _searchExpanded ? Icons.close : Icons.search,
              color: context.dMuted,
              size: 18,
            ),
            onPressed: _toggleSearch,
            splashRadius: 20,
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: context.dMuted, size: 18),
            splashRadius: 20,
            tooltip: 'Clear inbox',
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_permissionDenied) _PermissionBanner(onGrant: _requestPermission),

          _FilterTabRow(
            selected: _filterIndex,
            onSelect: (i) => setState(() => _filterIndex = i),
          ),

          // Search bar with animated open/close
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

          Container(height: 0.5, color: context.dBorder),

          // List with shimmer → content transition
          Expanded(
            child: _showShimmer
                ? const _InboxShimmer()
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: filtered.isEmpty
                        ? EmptyState(
                            key: ValueKey(
                                'empty_${_filterIndex}_${_searchQuery.isNotEmpty}'),
                            label: _searchQuery.isNotEmpty
                                ? '~ no results found'
                                : _emptyLabel(_filterIndex),
                          )
                        : ListView.separated(
                            key: ValueKey('list_$_filterIndex'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final record = filtered[i];
                              return GestureDetector(
                                onTap: () {
                                  if (record.verdict == Verdict.scam) {
                                    HapticFeedback.lightImpact();
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          DetailScreen(record: record),
                                    ),
                                  );
                                },
                                child: _ScanCard(record: record),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
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
          .where((r) =>
              r.sender.toLowerCase().contains(q) ||
              r.body.toLowerCase().contains(q))
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

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.dCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: context.dBorder, width: 0.5),
        ),
        title: Text('Clear inbox?',
            style: context.dtMono.copyWith(color: context.dText)),
        content: Text('All scanned messages will be deleted.',
            style: context.dtBody.copyWith(color: context.dMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: context.dtMonoSmall.copyWith(color: context.dMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear',
                style: context.dtMonoSmall.copyWith(color: DefendraColors.scam)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(inboxNotifierProvider.notifier).clearAll();
    }
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

  String _emptyLabel(int filterIndex) => switch (filterIndex) {
        1 => '~ no scams detected',
        2 => '~ no suspicious messages',
        3 => '~ no safe messages',
        _ => '~ no messages intercepted yet',
      };
}

// ---------------------------------------------------------------------------
// Shimmer skeleton (first 500ms)
// ---------------------------------------------------------------------------

class _InboxShimmer extends StatelessWidget {
  const _InboxShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => const InboxShimmerCard(),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter tab row
// ---------------------------------------------------------------------------

class _FilterTabRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;

  const _FilterTabRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (label: 'all', accent: context.dText),
      (label: 'scam', accent: DefendraColors.scam),
      (label: 'suspicious', accent: DefendraColors.suspicious),
      (label: 'safe', accent: DefendraColors.safe),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            _Tab(
              label: tabs[i].label,
              accent: tabs[i].accent,
              active: selected == i,
              onTap: () => onSelect(i),
            ),
            if (i < tabs.length - 1) const SizedBox(width: 24),
          ],
        ],
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
          style: context.dtMonoSmall.copyWith(
            color: active ? context.dText : context.dMuted,
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
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
      color: context.dCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'SMS permission required',
              style: context.dtLabel.copyWith(color: context.dText),
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
              style: context.dtLabel.copyWith(color: DefendraColors.scam),
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  final ScanRecord record;
  const _ScanCard({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.dCard,
        border: Border.all(color: context.dBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Verdict dot — Hero source
              Hero(
                tag: 'dot_${record.id}',
                child: Container(
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
                  style: context.dtMono.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _relativeTime(record.timestamp),
                style: context.dtMonoSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            record.body,
            style: context.dtBody.copyWith(
              color: context.dMuted,
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
        style: context.dtMono.copyWith(fontSize: 13),
        cursorColor: context.dMuted,
        decoration: InputDecoration(
          hintText: 'search sender or body...',
          hintStyle: context.dtMono.copyWith(
            fontSize: 13,
            color: context.dMuted,
          ),
          filled: true,
          fillColor: context.dCard,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: context.dBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: context.dBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: context.dBorder),
          ),
        ),
      ),
    );
  }
}
