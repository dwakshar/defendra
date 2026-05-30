import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../shell/home_shell.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _total = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _total - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    } else {
      _finish(requestPermission: true);
    }
  }

  Future<void> _finish({bool requestPermission = false}) async {
    if (requestPermission) {
      await Permission.sms.request();
    }
    final box = Hive.box('settings');
    await box.put('seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DefendraColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Skip row
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _finish(),
                  style: TextButton.styleFrom(
                    foregroundColor: DefendraColors.muted,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Skip', style: DefendraType.monoSmall),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const ClampingScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _ProblemPage(),
                  _SolutionPage(),
                  _PermissionsPage(),
                ],
              ),
            ),
            // Bottom controls
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Row(
                children: [
                  _DotIndicator(page: _page, total: _total),
                  const Spacer(),
                  TextButton(
                    onPressed: _next,
                    style: TextButton.styleFrom(
                      foregroundColor: DefendraColors.text,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _page == _total - 1 ? 'Get started' : 'Next',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: DefendraColors.text,
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Dot indicator
// ---------------------------------------------------------------------------

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.page, required this.total});
  final int page;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == page
                  ? DefendraColors.muted
                  : DefendraColors.border,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1 — Problem
// ---------------------------------------------------------------------------

class _ProblemPage extends StatelessWidget {
  const _ProblemPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const SizedBox(
            height: 100,
            child: _PhoneIllustration(),
          ),
          const SizedBox(height: 32),
          Text(
            '₹10,000+',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 52,
              fontWeight: FontWeight.w500,
              color: DefendraColors.text,
              height: 1.0,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'crore lost per year\nto scam SMS in India.',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: DefendraColors.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          _TagRow(tags: const [
            'OTP fraud',
            'KYC scams',
            'Delivery',
            'Digital arrest',
          ]),
        ],
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((t) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: DefendraColors.border, width: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            t,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: DefendraColors.muted,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// Minimal phone + scam-signal line illustration
class _PhoneIllustration extends StatelessWidget {
  const _PhoneIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PhonePainter());
  }
}

class _PhonePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = DefendraColors.border
      ..strokeWidth = 0.75
      ..style = PaintingStyle.stroke;

    final lineMuted = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..strokeWidth = 0.75
      ..style = PaintingStyle.stroke;

    // Phone outline
    final phoneW = size.width * 0.28;
    final phoneH = size.height * 0.78;
    final phoneL = size.width * 0.08;
    final phoneT = size.height * 0.11;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(phoneL, phoneT, phoneW, phoneH),
        const Radius.circular(6),
      ),
      stroke,
    );

    // Three text lines inside phone
    final lx = phoneL + phoneW * 0.18;
    final rx = phoneL + phoneW * 0.82;
    final lineY1 = phoneT + phoneH * 0.28;
    final lineY2 = phoneT + phoneH * 0.44;
    final lineY3 = phoneT + phoneH * 0.60;
    canvas.drawLine(Offset(lx, lineY1), Offset(rx, lineY1), lineMuted);
    canvas.drawLine(Offset(lx, lineY2), Offset(rx * 0.9 + lx * 0.1, lineY2), lineMuted);
    canvas.drawLine(Offset(lx, lineY3), Offset(rx * 0.7 + lx * 0.3, lineY3), lineMuted);

    // Scam dot — top-right of phone
    final dotPaint = Paint()
      ..color = DefendraColors.scam.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(phoneL + phoneW - 1, phoneT + 1),
      5,
      dotPaint,
    );

    // Diagonal "danger lines" to the right — sparse
    final warnPaint = Paint()
      ..color = DefendraColors.border
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final cx = phoneL + phoneW + 16;
    final cy = phoneT + phoneH * 0.3;
    for (int i = 0; i < 3; i++) {
      final angle = -math.pi / 6 + i * (math.pi / 10);
      final len = 18.0 + i * 8;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + len * math.cos(angle), cy + len * math.sin(angle)),
        warnPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ---------------------------------------------------------------------------
// Page 2 — Solution
// ---------------------------------------------------------------------------

class _SolutionPage extends StatelessWidget {
  const _SolutionPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Reads the message,\nnot just the number.',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: DefendraColors.text,
              height: 1.3,
              letterSpacing: -0.44,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '100% on-device. Nothing leaves your phone.',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: DefendraColors.muted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 32),
          const _FeatureRow(label: 'No internet required'),
          const SizedBox(height: 14),
          const _FeatureRow(label: 'No cloud processing'),
          const SizedBox(height: 14),
          const _FeatureRow(label: 'No data stored or shared'),
          const SizedBox(height: 14),
          const _FeatureRow(label: 'Works on airplane mode'),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DefendraColors.card,
              border: Border.all(color: DefendraColors.border, width: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'The ML model runs entirely on your device. '
              'SMS text is processed in memory and discarded — '
              'it is never written to a server, log, or analytics pipeline.',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: DefendraColors.muted,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: DefendraColors.safe,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: DefendraColors.text,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3 — Permissions
// ---------------------------------------------------------------------------

class _PermissionsPage extends StatelessWidget {
  const _PermissionsPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'One permission\nrequired.',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: DefendraColors.text,
              height: 1.3,
              letterSpacing: -0.44,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'To detect scams, Defendra needs to read incoming SMS.\n\n'
            'READ_SMS and RECEIVE_SMS are the only permissions requested. '
            'Messages are analysed on-device and never transmitted.',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: DefendraColors.muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          _PermRow(
            label: 'READ_SMS',
            detail: 'Scan message body for scam patterns',
          ),
          const SizedBox(height: 12),
          _PermRow(
            label: 'RECEIVE_SMS',
            detail: 'Intercept messages as they arrive',
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DefendraColors.card,
              border: Border.all(color: DefendraColors.border, width: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distribution',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: DefendraColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Defendra ships as a direct APK and via F-Droid. '
                  'No Play Store build. No Google Play Services dependency. '
                  'No crash-reporting SDK.',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: DefendraColors.muted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({required this.label, required this.detail});
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: DefendraColors.muted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: DefendraColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: DefendraColors.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
