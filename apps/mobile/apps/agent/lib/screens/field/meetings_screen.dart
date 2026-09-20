import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import 'field_widgets.dart';

/// A35 Group meeting (FA-027), list half: the officer's meetings and
/// "new meeting" at a village meeting point.
class MeetingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MeetingsScreen({super.key});

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(fieldRepositoryProvider).refreshMeetings());
  }

  Future<void> _create() async {
    final villages = await ref.read(farmerRepositoryProvider).villages();
    if (!mounted || villages.isEmpty) return;
    final result = await showModalBottomSheet<(Village, String)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => NewMeetingSheet(villages: villages),
    );
    if (result == null || !mounted) return;
    final fix = await ref.read(locationSourceProvider).current();
    if (!mounted) return;
    final meeting = await ref
        .read(fieldRepositoryProvider)
        .createMeeting(
          villageId: result.$1.id,
          villageName: result.$1.name,
          topic: result.$2,
          lat: fix?.point.latitude ?? result.$1.latitude ?? 0,
          lon: fix?.point.longitude ?? result.$1.longitude ?? 0,
          accuracyM: fix?.accuracyMetres,
        );
    if (!mounted) return;
    unawaited(context.push(AppRoutes.meetingPath(meeting.id)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final meetings = ref.watch(meetingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.meetingsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('meeting-new'),
        onPressed: () => unawaited(_create()),
        icon: const Icon(Icons.groups_outlined),
        label: Text(l10n.meetingNew),
      ),
      body: SafeArea(
        child: meetings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(meetingsProvider)),
          data: (rows) => rows.isEmpty
              ? EmptyState(
                  key: const Key('meetings-empty'),
                  icon: Icons.groups_outlined,
                  title: l10n.meetingsEmpty,
                  help: l10n.meetingsEmptyHelp,
                )
              : ListView(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  children: <Widget>[
                    for (final m in rows)
                      FieldCard(
                        key: Key('meeting-${m.id}'),
                        onTap: () => context.push(AppRoutes.meetingPath(m.id)),
                        child: ListTile(
                          leading: const Icon(Icons.groups_outlined),
                          title: Text(m.topic, style: app.text.label),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              FieldCaption(
                                '${m.villageName ?? m.villageId} · '
                                '${formatDateIst(m.heldAt)}',
                              ),
                              FieldCaption(
                                m.open
                                    ? l10n.meetingAttendees(m.attendance.length)
                                    : l10n.meetingClosed,
                              ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Village picker + topic for a new meeting.
class NewMeetingSheet extends StatefulWidget {
  /// Creates the sheet.
  const NewMeetingSheet({required this.villages, super.key});

  /// Villages to choose from.
  final List<Village> villages;

  @override
  State<NewMeetingSheet> createState() => _NewMeetingSheetState();
}

class _NewMeetingSheetState extends State<NewMeetingSheet> {
  final TextEditingController _topic = TextEditingController();
  Village? _village;

  @override
  void initState() {
    super.initState();
    _village = widget.villages.firstOrNull;
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.spaceScreenPadding,
        right: Tokens.spaceScreenPadding,
        top: Tokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.meetingNew, style: app.text.heading),
          const SizedBox(height: Tokens.space3),
          Wrap(
            spacing: Tokens.space2,
            children: <Widget>[
              for (final v in widget.villages)
                ChoiceChip(
                  key: Key('meeting-village-${v.id}'),
                  label: Text(v.name),
                  selected: _village?.id == v.id,
                  onSelected: (_) => setState(() => _village = v),
                ),
            ],
          ),
          const SizedBox(height: Tokens.space3),
          VoiceTextField(
            label: l10n.meetingTopic,
            hintText: l10n.meetingTopicHint,
            controller: _topic,
            onChanged: (_) => setState(() {}),
            fieldKey: const Key('meeting-topic'),
            micKey: const Key('meeting-topic-mic'),
          ),
          const SizedBox(height: Tokens.space4),
          AppButton(
            key: const Key('meeting-create'),
            label: l10n.meetingStart,
            onPressed: _village == null || _topic.text.trim().isEmpty
                ? null
                : () =>
                      Navigator.of(context)
                          .pop((_village!, _topic.text.trim())),
          ),
        ],
      ),
    );
  }
}

/// A35 Group meeting detail: attendance by farmer OTP or QR scan, the
/// attendee list, and "finish meeting".
class MeetingScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MeetingScreen({required this.meetingId, super.key});

  /// Meeting being run.
  final String meetingId;

  @override
  ConsumerState<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends ConsumerState<MeetingScreen> {
  Future<void> _addByOtp(Meeting meeting) async {
    final farmers = await ref.read(farmerRepositoryProvider).farmers();
    if (!mounted) return;
    final farmer = await showModalBottomSheet<FarmerSummary>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final f in farmers)
              ListTile(
                key: Key('meeting-pick-${f.id}'),
                title: Text(f.name),
                subtitle: Text(f.villageName),
                onTap: () => Navigator.of(context).pop(f),
              ),
          ],
        ),
      ),
    );
    if (farmer == null || !mounted) return;
    final l10n = CoreLocalizations.of(context);
    if (meeting.attendance.any((a) => a.farmerId == farmer.id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.meetingAlreadyPresent)));
      return;
    }
    final String masked;
    try {
      masked = await ref
          .read(fieldRepositoryProvider)
          .sendAttendanceOtp(meeting.id, farmer.id);
    } on FieldUnavailableException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('meeting-otp-offline'),
          content: Text(l10n.meetingOtpNeedsNetwork),
        ),
      );
      return;
    }
    if (!mounted) return;
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _OtpSheet(phoneMasked: masked),
    );
    if (code == null || !mounted) return;
    await ref
        .read(fieldRepositoryProvider)
        .addAttendance(
          meetingId: meeting.id,
          method: AttendanceMethod.otp,
          farmerId: farmer.id,
          farmerName: farmer.name,
          code: code,
        );
  }

  Future<void> _addByQr(Meeting meeting) async {
    final l10n = CoreLocalizations.of(context);
    final scanned = await ref.read(barcodeScannerProvider).scan(context);
    if (scanned == null || !mounted) return;
    final token = parseAttendanceQr(scanned);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('meeting-qr-invalid'),
          content: Text(l10n.meetingQrInvalid),
        ),
      );
      return;
    }
    await ref
        .read(fieldRepositoryProvider)
        .addAttendance(
          meetingId: meeting.id,
          method: AttendanceMethod.qr,
          token: token,
        );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final meeting = ref.watch(meetingProvider(widget.meetingId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.meetingAttendance)),
      body: SafeArea(
        child: meeting.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const ErrorState(),
          data: (m) => m == null
              ? EmptyState(
                  key: const Key('meeting-missing'),
                  icon: Icons.groups_outlined,
                  title: l10n.meetingsEmpty,
                  help: l10n.meetingsEmptyHelp,
                )
              : ListView(
                  padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                  children: <Widget>[
                    Text(m.topic, style: app.text.heading),
                    FieldCaption(
                      '${m.villageName ?? m.villageId} · '
                      '${formatDateTimeIst(m.heldAt)}',
                    ),
                    if (m.pending)
                      Padding(
                        padding: const EdgeInsets.only(top: Tokens.space1),
                        child: FieldCaption(
                          l10n.fieldPendingSync,
                          icon: Icons.cloud_upload_outlined,
                        ),
                      ),
                    const SizedBox(height: Tokens.space3),
                    if (m.open)
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: AppButton(
                              key: const Key('meeting-add-otp'),
                              label: l10n.meetingAddByOtp,
                              icon: Icons.sms_outlined,
                              variant: AppButtonVariant.secondary,
                              size: AppButtonSize.medium,
                              onPressed: () => unawaited(_addByOtp(m)),
                            ),
                          ),
                          const SizedBox(width: Tokens.space2),
                          Expanded(
                            child: AppButton(
                              key: const Key('meeting-add-qr'),
                              label: l10n.meetingAddByQr,
                              icon: Icons.qr_code_scanner,
                              variant: AppButtonVariant.secondary,
                              size: AppButtonSize.medium,
                              onPressed: () => unawaited(_addByQr(m)),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: Tokens.space4),
                    Text(
                      l10n.meetingAttendees(m.attendance.length),
                      key: const Key('meeting-attendee-count'),
                      style: app.text.heading,
                    ),
                    const SizedBox(height: Tokens.space2),
                    for (final a in m.attendance)
                      FieldCard(
                        key: Key('attendee-${a.farmerId}'),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            a.method == AttendanceMethod.qr
                                ? Icons.qr_code
                                : Icons.sms_outlined,
                            color: p.primary,
                          ),
                          title: Text(
                            a.farmerName ?? a.farmerId,
                            style: app.text.label,
                          ),
                          subtitle: a.pending
                              ? FieldCaption(l10n.fieldPendingSync)
                              : FieldCaption(formatTimeIst(a.recordedAt)),
                        ),
                      ),
                    const SizedBox(height: Tokens.space4),
                    if (m.open)
                      AppButton(
                        key: const Key('meeting-finish'),
                        label: l10n.meetingFinish,
                        onPressed: () => unawaited(
                          ref.read(fieldRepositoryProvider).closeMeeting(m.id),
                        ),
                      )
                    else
                      FieldCaption(
                        l10n.meetingClosed,
                        key: const Key('meeting-closed'),
                        icon: Icons.lock_outline,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Reads the farmer's signed attendance token out of a scanned QR payload.
/// The farmer app renders `farmerapp://attendance?token=<jwt>`; a bare token
/// is accepted too.
String? parseAttendanceQr(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri != null) {
    final token = uri.queryParameters['token'];
    if (token != null && token.isNotEmpty) {
      return uri.host == 'attendance' || uri.path.contains('attendance')
          ? token
          : null;
    }
  }
  // A bare JWT: three dot-separated base64url segments.
  return text.split('.').length == 3 ? text : null;
}

class _OtpSheet extends StatefulWidget {
  const _OtpSheet({required this.phoneMasked});

  final String phoneMasked;

  @override
  State<_OtpSheet> createState() => _OtpSheetState();
}

class _OtpSheetState extends State<_OtpSheet> {
  String _code = '';

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: Tokens.spaceScreenPadding,
        right: Tokens.spaceScreenPadding,
        top: Tokens.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Tokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.meetingAddByOtp, style: app.text.heading),
          const SizedBox(height: Tokens.space1),
          FieldCaption(l10n.meetingOtpSent(widget.phoneMasked)),
          const SizedBox(height: Tokens.space3),
          OtpInput(
            key: const Key('meeting-otp-input'),
            onChanged: (v) => setState(() => _code = v),
          ),
          const SizedBox(height: Tokens.space3),
          AppButton(
            key: const Key('meeting-otp-confirm'),
            label: l10n.otpVerify,
            onPressed: _code.length < 6
                ? null
                : () => Navigator.of(context).pop(_code),
          ),
        ],
      ),
    );
  }
}
