import 'dart:math';

/// Small, hand-written library of psychoeducation tips. Surfaced when the
/// network companion is unreachable, so the user still gets something useful.
/// No backend, no analytics — pure local content.
class PsychoedTip {
  final String title;
  final String body;
  const PsychoedTip(this.title, this.body);
}

const List<PsychoedTip> _kTips = [
  PsychoedTip(
    'A grounding exercise: 5-4-3-2-1',
    'Look around and name:\n'
    '• 5 things you can see\n'
    '• 4 things you can touch\n'
    '• 3 things you can hear\n'
    '• 2 things you can smell\n'
    '• 1 thing you can taste\n\n'
    'This pulls your mind back into the present moment when feelings get loud.',
  ),
  PsychoedTip(
    'Box breathing — for when your chest feels tight',
    'Breathe in for 4 seconds.\n'
    'Hold for 4 seconds.\n'
    'Breathe out for 4 seconds.\n'
    'Hold for 4 seconds.\n\n'
    'Do this 4 times. Your nervous system reads slow breath as "safe".',
  ),
  PsychoedTip(
    'Name it to tame it',
    'When emotions feel overwhelming, try labelling them out loud or in writing:\n'
    '"I notice I\'m feeling anxious."\n'
    '"There\'s sadness here."\n\n'
    'Naming an emotion engages the rational part of your brain and reduces '
    'the intensity of the feeling. You don\'t have to fix it — just name it.',
  ),
  PsychoedTip(
    'You can\'t outrun a feeling',
    'Avoiding hard emotions makes them bigger, not smaller. The way through '
    'is to let yourself feel it for a few minutes — without judgement, without '
    'fixing.\n\n'
    'Try this: set a timer for 3 minutes. Sit with whatever you\'re feeling. '
    'You\'ll likely find it shifts on its own.',
  ),
  PsychoedTip(
    'The 90-second rule',
    'Neuroscientist Jill Bolte Taylor found that the chemical surge of any '
    'emotion lasts about 90 seconds in the body. After that, what keeps it '
    'going is the story we tell ourselves.\n\n'
    'When something hits hard, try waiting 90 seconds before reacting.',
  ),
  PsychoedTip(
    'Thoughts are not facts',
    'Your brain produces around 6,000 thoughts a day. Most of them are '
    'automatic, repetitive, and often unkind. They\'re not orders — they\'re '
    'suggestions.\n\n'
    'Next time a harsh thought shows up, try: "Thank you, brain. I see you. '
    'I don\'t have to believe you."',
  ),
  PsychoedTip(
    'Self-compassion isn\'t weakness',
    'Talk to yourself the way you\'d talk to a close friend going through '
    'the same thing. If a friend told you what you\'re telling yourself right '
    'now, would you call them lazy? A failure? Probably not.\n\n'
    'You deserve the same kindness.',
  ),
  PsychoedTip(
    'Sleep, water, food — in that order',
    'When mental health feels heavy, check the body first:\n'
    '• Have you slept enough in the last 48 hours?\n'
    '• Have you had water in the last 2 hours?\n'
    '• Have you eaten in the last 4 hours?\n\n'
    'Many "I can\'t cope" moments are really "my body is depleted" moments.',
  ),
  PsychoedTip(
    'Tiny steps count',
    'Depression makes everything feel like a mountain. The trick isn\'t to '
    'climb it — it\'s to make the first step smaller than your brain expects.\n\n'
    'Don\'t "exercise" — put your shoes on.\n'
    'Don\'t "clean your room" — pick up one thing.\n'
    'Don\'t "study" — open the book.\n\n'
    'Momentum builds itself once you start.',
  ),
];

class PsychoedService {
  static final PsychoedService _instance = PsychoedService._();
  factory PsychoedService() => _instance;
  PsychoedService._();

  final _rand = Random();

  /// A random tip — used as a fallback when the chat companion can't be reached.
  PsychoedTip randomTip() => _kTips[_rand.nextInt(_kTips.length)];

  /// Full list — for a future "tips" screen.
  List<PsychoedTip> all() => List.unmodifiable(_kTips);

  /// Short one-liner insights, designed to be appended to a companion reply
  /// as a soft footnote. Keep them under ~120 chars so they read like a
  /// thought, not a lecture.
  static const List<String> _kInlineNudges = [
    'A small reminder — naming a feeling shrinks it. You don\'t have to fix it, just notice it.',
    'If your chest feels tight, try a slow exhale longer than your inhale. The body reads that as safety.',
    'Thoughts aren\'t facts. The harsh ones are just loud — they\'re not necessarily true.',
    'Whatever you\'re feeling now is part of being human. It will move. It always does.',
    'When everything feels heavy, the trick is to make the next step smaller than your brain expects.',
    'You can be doing your best AND struggling. Both are true at the same time.',
    'Try the 5-4-3-2-1: name 5 things you see, 4 you can touch, 3 you hear, 2 you smell, 1 you taste.',
    'Sleep, water, food — check the body first. A lot of "I can\'t cope" is actually depletion.',
    'Self-compassion is talking to yourself like you would to a friend going through the same thing.',
    'The hard feeling lasts about 90 seconds chemically. What keeps it going is the story we tell about it.',
  ];

  /// Returns a soft inline nudge (~one short sentence) suitable for
  /// appending to a companion reply, or null if this turn shouldn\'t carry
  /// one. We pace these out so they feel like care, not nagging.
  ///
  /// [companionReplyIndex] — how many companion replies have happened in
  /// this session so far (0-based). We nudge roughly every 3rd reply, with
  /// a small random jitter so it doesn't feel mechanical.
  String? maybeNudge(int companionReplyIndex) {
    if (companionReplyIndex < 1) return null;          // never on the very first reply
    if (companionReplyIndex % 3 != 0) return null;     // every 3rd-ish
    if (_rand.nextDouble() < 0.25) return null;        // skip ~25% for organic feel
    return _kInlineNudges[_rand.nextInt(_kInlineNudges.length)];
  }
}
