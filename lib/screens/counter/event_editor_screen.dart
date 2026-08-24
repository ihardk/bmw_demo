import 'package:flutter/material.dart';

import '../../constants/counter_backgrounds.dart';
import '../../constants/my_colors.dart';
import '../../data/event_store.dart';
import '../../models/count_event.dart';
import '../../widgets/counter/counter_background.dart';
import '../../widgets/counter/day_counter_card.dart';

/// Create or edit a counter, with the card itself as the live preview — every
/// change to the title, date, span or background is visible before saving.
class EventEditorScreen extends StatefulWidget {
  const EventEditorScreen({super.key, this.event});

  final CountEvent? event;

  bool get isEditing => event != null;

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  static const List<int> _spanOptions = [30, 60, 90, 180, 365];

  static const List<List<String>> _suggestions = [
    ['My Birthday', '🎉'],
    ['Wedding', '💍'],
    ['Vacation', '🏝️'],
    ['Delivery Day', '🔑'],
    ['Launch', '🚀'],
    ['Anniversary', '❤️'],
  ];

  late final TextEditingController _titleController;
  late DateTime _target;
  late bool _allDay;
  late int _spanDays;
  late String _backgroundId;
  late String _emoji;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _titleController = TextEditingController(text: event?.title ?? '');
    final defaultTarget = DateTime.now().add(const Duration(days: 30));
    _target = event?.target ??
        DateTime(
          defaultTarget.year,
          defaultTarget.month,
          defaultTarget.day,
          9,
        );
    _allDay = event?.allDay ?? true;
    _spanDays = event?.spanDays ?? 180;
    _backgroundId = event?.backgroundId ?? kBackgroundEmber.id;
    _emoji = event?.emoji ?? '';
    _imagePath = event?.imagePath;
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  CountEvent get _draft => CountEvent(
        id: widget.event?.id ?? EventStore.newId(),
        title: _titleController.text.trim().isEmpty
            ? 'Untitled'
            : _titleController.text.trim(),
        target: _target,
        emoji: _emoji,
        allDay: _allDay,
        spanDays: _spanDays,
        backgroundId: _backgroundId,
        imagePath: _imagePath,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _target,
      firstDate: DateTime(DateTime.now().year - 50),
      lastDate: DateTime(DateTime.now().year + 50),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: kcSecondaryStart,
            surface: kcBGGrey,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _target = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _target.hour,
        _target.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_target),
    );
    if (picked == null) return;
    setState(() {
      _target = DateTime(
        _target.year,
        _target.month,
        _target.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    final event = _draft;
    if (widget.isEditing) {
      await EventStore.instance.update(event);
    } else {
      await EventStore.instance.add(event);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: kcBGDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  DayCounterCard(event: _draft, now: now),
                  const SizedBox(height: 28),
                  const _SectionLabel('TITLE'),
                  _buildTitleField(),
                  const SizedBox(height: 12),
                  _buildSuggestions(),
                  const SizedBox(height: 28),
                  const _SectionLabel('DATE & TIME'),
                  _buildDateRow(),
                  const SizedBox(height: 28),
                  _buildSpanSection(now),
                  const SizedBox(height: 28),
                  const _SectionLabel('BACKGROUND'),
                  _buildBackgroundPicker(),
                  const SizedBox(height: 32),
                  _buildSaveButton(),
                  if (widget.isEditing) ...[
                    const SizedBox(height: 12),
                    _buildDeleteButton(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      child: Row(
        children: [
          Text(
            widget.isEditing ? 'Edit Counter' : 'New Counter',
            style: const TextStyle(
              color: kcWhite,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: kcLabelGreyLight),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      style: const TextStyle(color: kcWhite, fontSize: 18),
      cursorColor: kcSecondaryEnd,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        hintText: 'Birthday, Vacation, Launch…',
        hintStyle: TextStyle(color: kcLabelGrey),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: kcBGGrey),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: kcSecondaryStart),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final suggestion in _suggestions)
          _Chip(
            label: '${suggestion[0]} ${suggestion[1]}',
            selected: _titleController.text.trim() == suggestion[0],
            onTap: () => setState(() {
              _titleController.text = suggestion[0];
              _emoji = suggestion[1];
            }),
          ),
      ],
    );
  }

  Widget _buildDateRow() {
    return Column(
      children: [
        Row(
          children: [
            const Text('All-day', style: TextStyle(color: kcWhite)),
            const Spacer(),
            Switch(
              value: _allDay,
              activeColor: kcSecondaryEnd,
              onChanged: (value) => setState(() => _allDay = value),
            ),
          ],
        ),
        Row(
          children: [
            const Text('Event date', style: TextStyle(color: kcWhite)),
            const Spacer(),
            _PillButton(
              label: formatEventDate(_target),
              onTap: _pickDate,
            ),
            if (!_allDay) ...[
              const SizedBox(width: 8),
              _PillButton(
                label: TimeOfDay.fromDateTime(_target).format(context),
                onTap: _pickTime,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSpanSection(DateTime now) {
    final draft = _draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('COUNTING WINDOW'),
            const Spacer(),
            Text(
              draft.fractionLabelAt(now),
              style: const TextStyle(
                color: kcSecondaryEnd,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          draft.directionAt(now) == CountDirection.until
              ? 'Counts down from $_spanDays / $_spanDays to 1 / $_spanDays.'
              : 'Counts up from 1 / $_spanDays to $_spanDays / $_spanDays.',
          style: const TextStyle(color: kcLabelGreyLight, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final span in _spanOptions)
              _Chip(
                label: '$span days',
                selected: _spanDays == span,
                onTap: () => setState(() => _spanDays = span),
              ),
          ],
        ),
        Slider(
          value: _spanDays.clamp(7, 730).toDouble(),
          min: 7,
          max: 730,
          activeColor: kcSecondaryStart,
          inactiveColor: kcBGGrey,
          onChanged: (value) => setState(() => _spanDays = value.round()),
        ),
      ],
    );
  }

  Widget _buildBackgroundPicker() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kCounterBackgrounds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final background = kCounterBackgrounds[index];
          final selected = background.id == _backgroundId;
          return GestureDetector(
            onTap: () => setState(() {
              _backgroundId = background.id;
              _imagePath = null;
            }),
            child: Container(
              width: 78,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? kcSecondaryEnd : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CounterBackgroundView(
                  background: background,
                  scrim: 0.35,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        background.name,
                        style: const TextStyle(
                          color: kcWhite,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: kcSecondaryStart,
          foregroundColor: kcWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(
          widget.isEditing ? 'Save changes' : 'Start counting',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return TextButton(
      onPressed: () async {
        await EventStore.instance.remove(widget.event!.id);
        if (mounted) Navigator.of(context).pop();
      },
      child: const Text(
        'Delete counter',
        style: TextStyle(color: kcLabelGreyLight),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: kcLabelGreyLight,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kcSecondaryStart : kcBGGrey,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? kcWhite : kcLabelGreyLight,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kcBGGrey,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: const TextStyle(color: kcWhite, fontSize: 13),
        ),
      ),
    );
  }
}
