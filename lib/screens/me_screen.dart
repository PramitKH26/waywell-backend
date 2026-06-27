import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/mood_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _ctrl = TextEditingController();
  String? _currentName;
  bool    _isEditing = false;

  // Check-in notification settings
  bool _checkInEnabled = false;
  int  _checkInHour    = 20;
  int  _checkInMinute  = 0;
  bool _panicShortcut  = true;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadNotificationSettings();
    UserService().addListener(_loadName);
    MoodService().addListener(_onMoodChanged);
  }

  @override
  void dispose() {
    UserService().removeListener(_loadName);
    MoodService().removeListener(_onMoodChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onMoodChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadName() async {
    final name = await UserService().getName();
    if (!mounted) return;
    setState(() {
      _currentName = name;
      if (!_isEditing) _ctrl.text = name ?? '';
    });
  }

  Future<void> _loadNotificationSettings() async {
    final s = await NotificationService().getCheckInSettings();
    final p = await NotificationService().isPanicShortcutEnabled();
    if (!mounted) return;
    setState(() {
      _checkInEnabled = s['enabled'] as bool;
      _checkInHour    = s['hour']    as int;
      _checkInMinute  = s['minute']  as int;
      _panicShortcut  = p;
    });
  }

  Future<void> _saveName() async {
    final newName = _ctrl.text.trim();
    if (newName.isEmpty) return;
    await UserService().setName(newName);
    if (!mounted) return;
    setState(() {
      _currentName = newName;
      _isEditing   = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Name saved',
            style: GoogleFonts.fraunces(color: Colors.white)),
        backgroundColor: const Color(0xFF4A7C59),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickCheckInTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _checkInHour, minute: _checkInMinute),
    );
    if (time == null) return;
    // Set the toggle on immediately — before async work, so the user sees
    // feedback even if scheduling fails (e.g. permission denied on this device).
    if (mounted) {
      setState(() {
        _checkInEnabled = true;
        _checkInHour    = time.hour;
        _checkInMinute  = time.minute;
      });
    }
    try {
      await NotificationService().requestPermission();
      await NotificationService().scheduleCheckIn(time.hour, time.minute);
    } catch (e) {
      debugPrint('[MeScreen] scheduleCheckIn error: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Check-in set for ${_formatTime(time.hour, time.minute)} daily 🌿',
            style: GoogleFonts.fraunces(color: Colors.white)),
        backgroundColor: const Color(0xFF4A7C59),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h      = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final m      = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final initials = (_currentName?.isNotEmpty == true)
        ? _currentName![0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: const Color(0xFFF5EAD3),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // ── Avatar + display name ──
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8D5B7),
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: GoogleFonts.caveat(
                          fontSize:   52,
                          color:      const Color(0xFF3D2817),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _currentName ?? 'Set your name',
                      style: GoogleFonts.caveat(
                        fontSize:   30,
                        color:      const Color(0xFF3D2817),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // ── Name field ──
              _sectionLabel('Your Name'),
              const SizedBox(height: 8),
              _whiteCard(
                child: _isEditing
                    ? Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            autofocus:  true,
                            maxLength:  20,
                            style: GoogleFonts.fraunces(
                                fontSize: 16,
                                color:    const Color(0xFF3D2817)),
                            decoration: const InputDecoration(
                              border:      InputBorder.none,
                              hintText:    'Enter your name',
                              counterText: '',
                            ),
                            onSubmitted: (_) => _saveName(),
                          ),
                        ),
                        GestureDetector(
                          onTap: _saveName,
                          child: Text(
                            'Save',
                            style: GoogleFonts.fraunces(
                              fontSize:   14,
                              fontWeight: FontWeight.w600,
                              color:      const Color(0xFF4A7C59),
                            ),
                          ),
                        ),
                      ])
                    : Row(children: [
                        Expanded(
                          child: Text(
                            _currentName ?? 'Not set',
                            style: GoogleFonts.fraunces(
                              fontSize: 16,
                              color:    const Color(0xFF3D2817),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _isEditing = true),
                          child: const Icon(
                            Icons.edit_outlined,
                            color: Color(0xFF6B4F36),
                            size: 20,
                          ),
                        ),
                      ]),
              ),

              const SizedBox(height: 32),

              // ── Mood chart ──
              _sectionLabel('How you\'ve been'),
              const SizedBox(height: 8),
              _MoodChart(),

              const SizedBox(height: 32),

              // ── Daily check-in ──
              _sectionLabel('Daily Check-in'),
              const SizedBox(height: 8),
              _whiteCard(
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reminder notification',
                              style: GoogleFonts.fraunces(
                                fontSize:   15,
                                fontWeight: FontWeight.w500,
                                color:      const Color(0xFF3D2817),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _checkInEnabled
                                  ? 'Set for ${_formatTime(_checkInHour, _checkInMinute)} daily'
                                  : 'Off — tap to set a time',
                              style: GoogleFonts.fraunces(
                                fontSize: 12,
                                color:    const Color(0xFF6B4F36),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _checkInEnabled,
                        activeColor: const Color(0xFF4A7C59),
                        onChanged: (val) async {
                          if (val) {
                            await _pickCheckInTime();
                          } else {
                            await NotificationService().cancelCheckIn();
                            if (!mounted) return;
                            setState(() => _checkInEnabled = false);
                          }
                        },
                      ),
                    ]),
                    if (_checkInEnabled) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: _pickCheckInTime,
                          child: Text(
                            'Change time',
                            style: GoogleFonts.fraunces(
                              fontSize:   13,
                              color:      const Color(0xFF4A7C59),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── About ──
              _sectionLabel('About Waywell'),
              const SizedBox(height: 8),
              _whiteCard(
                child: Text(
                  'Waywell is a soft, private companion for the moments '
                  'between everything else. A place to breathe, to write '
                  'what you can\'t say out loud, and to keep little reminders '
                  'of the days you got through.\n\n'
                  'You\'re never alone here.',
                  style: GoogleFonts.fraunces(
                    fontSize: 14,
                    height:   1.65,
                    color:    const Color(0xFF5C4A32),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Safety ──
              _sectionLabel('Safety'),
              const SizedBox(height: 8),
              _whiteCard(
                child: Row(children: [
                  const Icon(Icons.notifications_active_outlined,
                      color: Color(0xFF6B4F36), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Safe Space shortcut',
                            style: GoogleFonts.fraunces(
                              fontSize:   15,
                              fontWeight: FontWeight.w500,
                              color:      const Color(0xFF3D2817),
                            )),
                        const SizedBox(height: 2),
                        Text('Persistent notification for quick access',
                            style: GoogleFonts.fraunces(
                              fontSize: 12,
                              color:    const Color(0xFF6B4F36),
                            )),
                      ],
                    ),
                  ),
                  Switch(
                    value: _panicShortcut,
                    activeColor: const Color(0xFF1A2530),
                    onChanged: (val) async {
                      await NotificationService().setPanicShortcutEnabled(val);
                      if (!mounted) return;
                      setState(() => _panicShortcut = val);
                    },
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              _settingRow(
                icon:     Icons.shield_outlined,
                title:    'Trusted Contact',
                subtitle: 'Someone Waywell can reach when you need support',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Set up from the Safe Space screen'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.fraunces(
          fontSize:      13,
          fontWeight:    FontWeight.w600,
          color:         const Color(0xFF6B4F36),
          letterSpacing: 0.3,
        ),
      );

  Widget _whiteCard({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFB0957A), width: 0.5),
        ),
        child: child,
      );

  Widget _settingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: _whiteCard(
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6B4F36), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.fraunces(
                        fontSize:   15,
                        fontWeight: FontWeight.w500,
                        color:      const Color(0xFF3D2817),
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.fraunces(
                        fontSize: 12,
                        color:    const Color(0xFF6B4F36),
                      )),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Color(0xFFB0957A)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mood chart — shows the most recent mood per day for the past 7 days as
// colored dots in a small calendar strip. Nothing fancy, just a quick "what
// have I been carrying" view.
// ─────────────────────────────────────────────────────────────────────────────

const _kMoodColors = {
  'Calm':        Color(0xFFB5C9A8),
  'Hopeful':     Color(0xFFDCE3A8),
  'Tired':       Color(0xFFC3B5D9),
  'Stressed':    Color(0xFFE8B5A0),
  'Overwhelmed': Color(0xFFD89898),
  'Lonely':      Color(0xFFA8B9C9),
};

// Each mood maps to a 1–5 wellbeing score so we can draw a trend line.
const _kMoodScore = {
  'Hopeful':     5.0,
  'Calm':        4.0,
  'Tired':       3.0,
  'Lonely':      2.0,
  'Stressed':    2.0,
  'Overwhelmed': 1.0,
};

class _MoodChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final history = MoodService().history; // oldest → newest
    final recent  = history.length > 12
        ? history.sublist(history.length - 12)
        : history;
    final has = recent.isNotEmpty;

    String insight = '';
    if (has) {
      final avg = recent
              .map((e) => _kMoodScore[e.mood] ?? 3.0)
              .reduce((a, b) => a + b) /
          recent.length;
      if (avg >= 4) {
        insight = "You've been in a good place lately. That matters.";
      } else if (avg >= 3) {
        insight = "A mixed stretch — be gentle with yourself.";
      } else {
        insight = "It's been a heavy few days. You kept showing up anyway.";
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: const Color(0xFFB0957A), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            has
                ? 'Your mood lately'
                : 'No mood check-ins yet — they\'ll show up here once you start.',
            style: GoogleFonts.fraunces(
              fontSize:   has ? 14 : 12.5,
              fontWeight: has ? FontWeight.w600 : FontWeight.w400,
              color:      const Color(0xFF3D2817),
              height:     1.4,
            ),
          ),
          if (has) ...[
            const SizedBox(height: 2),
            Text(
              insight,
              style: GoogleFonts.fraunces(
                fontSize:  12.5,
                fontStyle: FontStyle.italic,
                color:     const Color(0xFF4A7C59),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // y-axis emoji scale
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('😊', style: TextStyle(fontSize: 13)),
                      Text('😐', style: TextStyle(fontSize: 13)),
                      Text('😢', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _MoodLinePainter(recent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10, runSpacing: 6,
              children: _kMoodColors.entries.map((e) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: e.value, shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(e.key,
                      style: GoogleFonts.fraunces(
                          fontSize: 11, color: const Color(0xFF6B4F36))),
                ],
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoodLinePainter extends CustomPainter {
  final List<MoodEntry> entries;
  const _MoodLinePainter(this.entries);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFEDE3D0)
      ..strokeWidth = 1;
    for (var s = 1; s <= 5; s++) {
      final y = size.height - (s - 1) / 4 * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (entries.isEmpty) return;

    final n = entries.length;
    double xFor(int i) => n == 1 ? size.width / 2 : i / (n - 1) * size.width;
    double yFor(double sc) => size.height - (sc - 1) / 4 * size.height;

    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(xFor(i), yFor(_kMoodScore[entries[i].mood] ?? 3.0)),
    ];

    final line = Paint()
      ..color = const Color(0xFF4A7C59)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, line);

    for (var i = 0; i < n; i++) {
      final c = _kMoodColors[entries[i].mood] ?? const Color(0xFF4A7C59);
      canvas.drawCircle(pts[i], 5, Paint()..color = Colors.white);
      canvas.drawCircle(
          pts[i], 5,
          Paint()
            ..color = const Color(0xFF4A7C59)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.drawCircle(pts[i], 3.2, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(covariant _MoodLinePainter old) =>
      old.entries.length != entries.length;
}
