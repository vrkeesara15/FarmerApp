/// Models of the M7 farmer advisory APIs: the crop calendar (FM-007), the
/// farm weather with spray windows (FM-008), the district pest and disease
/// alerts (FM-009) and the notification inbox (FA-007).
///
/// Contracts: docs/prs/M7-farmer-p1-api.md and docs/prs/M7-field-p1-api.md.
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;

DateTime? _time(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

/// Parses a `YYYY-MM-DD` wire date into a UTC midnight [DateTime].
DateTime? parseIsoDate(Object? v) {
  if (v is! String || v.length < 10) return null;
  final y = int.tryParse(v.substring(0, 4));
  final m = int.tryParse(v.substring(5, 7));
  final d = int.tryParse(v.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  return DateTime.utc(y, m, d);
}

/// Formats [date] as the `YYYY-MM-DD` the API expects (UTC).
String isoDay(DateTime date) {
  final d = date.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

double _num(Object? v) => switch (v) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};

int _int(Object? v) => v is num ? v.toInt() : 0;

Map<String, String> _names(Object? v) => <String, String>{
  for (final e in (v is Map ? v.entries : const <MapEntry<Object?, Object?>>[]))
    if (e.key is String && e.value is String)
      e.key! as String: e.value! as String,
};

List<Map<String, Object?>> _maps(Object? v) => <Map<String, Object?>>[
  for (final e in (v is List ? v : const <Object?>[]))
    if (e is Map) Map<String, Object?>.from(e),
];

List<String> _strings(Object? v) => <String>[
  for (final e in (v is List ? v : const <Object?>[]))
    if (e is String) e,
];

/// Picks the text for [language] out of a `{lang: text}` map, falling back
/// to English and then to anything present.
String? localised(Map<String, String> byLanguage, String language) =>
    byLanguage[language] ??
    byLanguage['en'] ??
    (byLanguage.isEmpty ? null : byLanguage.values.first);

// --- FM-007 crop calendar ----------------------------------------------------

/// Task types of `crop_task_template.task_type`.
abstract final class TaskTypes {
  /// Sowing.
  static const String sow = 'sow';

  /// Irrigation.
  static const String irrigate = 'irrigate';

  /// Fertiliser application.
  static const String fertilise = 'fertilise';

  /// Spray.
  static const String spray = 'spray';

  /// Harvest.
  static const String harvest = 'harvest';

  /// Wire values in calendar order.
  static const List<String> values = <String>[
    sow,
    irrigate,
    fertilise,
    spray,
    harvest,
  ];
}

/// One calendar task (`CropPlotTaskOut`).
@immutable
class CalendarTask {
  /// Creates the task.
  const CalendarTask({
    required this.id,
    required this.cropPlotId,
    required this.taskKey,
    required this.taskType,
    required this.dueDate,
    required this.version,
    this.stage,
    this.endDate,
    this.titles = const <String, String>{},
    this.instructions = const <String, String>{},
    this.productCategory,
    this.sortOrder = 0,
    this.status = 'pending',
    this.doneAt,
    this.reminderEnabled = true,
    this.basisSowingDate,
    this.pending = false,
  });

  /// Parses `CropPlotTaskOut`.
  factory CalendarTask.fromJson(Map<String, Object?> j, {String? cropPlotId}) =>
      CalendarTask(
        id: '${j['id']}',
        cropPlotId: '${j['crop_plot_id'] ?? cropPlotId ?? ''}',
        taskKey: (j['task_key'] as String?) ?? '',
        taskType: (j['task_type'] as String?) ?? TaskTypes.irrigate,
        stage: j['stage'] as String?,
        dueDate: parseIsoDate(j['due_date']) ?? DateTime.utc(1970),
        endDate: parseIsoDate(j['end_date']),
        titles: _names(j['titles']),
        instructions: _names(j['instructions']),
        productCategory: j['product_category'] as String?,
        sortOrder: _int(j['sort_order']),
        status: (j['status'] as String?) ?? 'pending',
        doneAt: _time(j['done_at']),
        reminderEnabled: j['reminder_enabled'] != false,
        basisSowingDate: parseIsoDate(j['basis_sowing_date']),
        version: _int(j['version']),
        pending: j['_pending'] == true,
      );

  /// Task id.
  final String id;

  /// The crop plot this task belongs to.
  final String cropPlotId;

  /// Stable template key, e.g. `paddy.top_dress_1`.
  final String taskKey;

  /// One of [TaskTypes].
  final String taskType;

  /// Crop stage the task belongs to.
  final String? stage;

  /// First day the task is due (UTC midnight).
  final DateTime dueDate;

  /// Last day of the window, when the task spans days.
  final DateTime? endDate;

  /// Short title per language code.
  final Map<String, String> titles;

  /// One-line instruction per language code.
  final Map<String, String> instructions;

  /// Product category to buy for the task (never a SKU — DX-007).
  final String? productCategory;

  /// Order inside a day.
  final int sortOrder;

  /// `pending` | `done`.
  final String status;

  /// When it was marked done.
  final DateTime? doneAt;

  /// The farmer wants a reminder for this task.
  final bool reminderEnabled;

  /// Sowing date the due date was computed from.
  final DateTime? basisSowingDate;

  /// Server row version (PATCH precondition).
  final int version;

  /// A change to this task is still queued in the outbox.
  final bool pending;

  /// Marked done.
  bool get done => status == 'done';

  /// Title in [language].
  String? titleIn(String language) => localised(titles, language);

  /// One-line instruction in [language].
  String? instructionIn(String language) => localised(instructions, language);

  /// What the audio button reads out (NF-009): title then instruction.
  String spokenIn(String language) =>
      <String>[?titleIn(language), ?instructionIn(language)].join('. ');

  /// 1-based week of the task counted from [sowingDate].
  int weekFrom(DateTime sowingDate) {
    final days = dueDate.difference(parseIsoDate(isoDay(sowingDate))!).inDays;
    return days < 0 ? 0 : days ~/ 7 + 1;
  }

  /// Due on or before [day] and not done.
  bool overdueOn(DateTime day) => !done && !dueDate.isAfter(day);

  /// A copy with the fields a device may change.
  CalendarTask copyWith({
    String? status,
    DateTime? doneAt,
    bool? reminderEnabled,
    bool? pending,
  }) => CalendarTask(
    id: id,
    cropPlotId: cropPlotId,
    taskKey: taskKey,
    taskType: taskType,
    stage: stage,
    dueDate: dueDate,
    endDate: endDate,
    titles: titles,
    instructions: instructions,
    productCategory: productCategory,
    sortOrder: sortOrder,
    status: status ?? this.status,
    doneAt: doneAt ?? this.doneAt,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    basisSowingDate: basisSowingDate,
    version: version,
    pending: pending ?? this.pending,
  );

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'crop_plot_id': cropPlotId,
    'task_key': taskKey,
    'task_type': taskType,
    'stage': stage,
    'due_date': isoDay(dueDate),
    'end_date': endDate == null ? null : isoDay(endDate!),
    'titles': titles,
    'instructions': instructions,
    'product_category': productCategory,
    'sort_order': sortOrder,
    'status': status,
    'done_at': doneAt?.toIso8601String(),
    'reminder_enabled': reminderEnabled,
    'basis_sowing_date': basisSowingDate == null
        ? null
        : isoDay(basisSowingDate!),
    'version': version,
    if (pending) '_pending': true,
  };

  @override
  bool operator ==(Object other) =>
      other is CalendarTask &&
      other.id == id &&
      other.status == status &&
      other.dueDate == dueDate &&
      other.reminderEnabled == reminderEnabled &&
      other.version == version &&
      other.pending == pending;

  @override
  int get hashCode =>
      Object.hash(id, status, dueDate, reminderEnabled, version, pending);
}

/// One crop plot's calendar (`CalendarPlotOut`).
@immutable
class CropPlotCalendar {
  /// Creates the calendar.
  const CropPlotCalendar({
    required this.cropPlotId,
    required this.farmId,
    required this.cropId,
    required this.cropCode,
    required this.tasks,
    this.cropNames = const <String, String>{},
    this.season,
    this.sowingDate,
  });

  /// Parses `CalendarPlotOut`.
  factory CropPlotCalendar.fromJson(Map<String, Object?> j) {
    final id = '${j['crop_plot_id']}';
    return CropPlotCalendar(
      cropPlotId: id,
      farmId: '${j['farm_id']}',
      cropId: '${j['crop_id']}',
      cropCode: (j['crop_code'] as String?) ?? '',
      cropNames: _names(j['crop_names']),
      season: j['season'] as String?,
      sowingDate: parseIsoDate(j['sowing_date']),
      tasks:
          <CalendarTask>[
            for (final t in _maps(j['tasks']))
              CalendarTask.fromJson(t, cropPlotId: id),
          ]..sort(
            (a, b) => a.dueDate == b.dueDate
                ? a.sortOrder.compareTo(b.sortOrder)
                : a.dueDate.compareTo(b.dueDate),
          ),
    );
  }

  /// Crop plot id.
  final String cropPlotId;

  /// Farm the plot belongs to.
  final String farmId;

  /// Crop reference id.
  final String cropId;

  /// Crop code (`paddy`, `cotton`, ...).
  final String cropCode;

  /// Crop name per language code.
  final Map<String, String> cropNames;

  /// Season.
  final String? season;

  /// Sowing date the tasks were generated from.
  final DateTime? sowingDate;

  /// Tasks, earliest first.
  final List<CalendarTask> tasks;

  /// Crop name in [language].
  String? cropNameIn(String language) => localised(cropNames, language);

  /// The next task still to do on or after [today] (else the oldest
  /// overdue one, else null).
  CalendarTask? nextTask(DateTime today) {
    final day = parseIsoDate(isoDay(today))!;
    CalendarTask? overdue;
    for (final t in tasks) {
      if (t.done) continue;
      if (!t.dueDate.isBefore(day)) return t;
      overdue ??= t;
    }
    return overdue;
  }

  /// Tasks grouped by 1-based week from the sowing date, in order.
  Map<int, List<CalendarTask>> byWeek() {
    final sowing = sowingDate;
    final out = <int, List<CalendarTask>>{};
    for (final t in tasks) {
      final week = sowing == null ? 1 : t.weekFrom(sowing);
      (out[week] ??= <CalendarTask>[]).add(t);
    }
    return out;
  }

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'crop_plot_id': cropPlotId,
    'farm_id': farmId,
    'crop_id': cropId,
    'crop_code': cropCode,
    'crop_names': cropNames,
    'season': season,
    'sowing_date': sowingDate == null ? null : isoDay(sowingDate!),
    'tasks': <Object?>[for (final t in tasks) t.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is CropPlotCalendar &&
      other.cropPlotId == cropPlotId &&
      other.sowingDate == sowingDate &&
      listEquals(other.tasks, tasks);

  @override
  int get hashCode =>
      Object.hash(cropPlotId, sowingDate, Object.hashAll(tasks));
}

/// `GET /v1/me/calendar`.
@immutable
class CropCalendar {
  /// Creates the calendar.
  const CropCalendar({
    required this.farmerId,
    required this.today,
    required this.plots,
  });

  /// Parses the API body.
  factory CropCalendar.fromJson(Map<String, Object?> j) => CropCalendar(
    farmerId: '${j['farmer_id']}',
    today: parseIsoDate(j['today']) ?? DateTime.utc(1970),
    plots: <CropPlotCalendar>[
      for (final p in _maps(j['plots'])) CropPlotCalendar.fromJson(p),
    ],
  );

  /// Farmer.
  final String farmerId;

  /// The server's IST date when the calendar was read.
  final DateTime today;

  /// One entry per active crop plot.
  final List<CropPlotCalendar> plots;

  /// The calendar of [cropPlotId], or null.
  CropPlotCalendar? plot(String cropPlotId) =>
      plots.where((p) => p.cropPlotId == cropPlotId).firstOrNull;

  /// The next task of [cropPlotId].
  CalendarTask? nextTaskOf(String cropPlotId) =>
      plot(cropPlotId)?.nextTask(today);

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'farmer_id': farmerId,
    'today': isoDay(today),
    'plots': <Object?>[for (final p in plots) p.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is CropCalendar &&
      other.farmerId == farmerId &&
      other.today == today &&
      listEquals(other.plots, plots);

  @override
  int get hashCode => Object.hash(farmerId, today, Object.hashAll(plots));
}

/// F42 "what changed": the sowing date of a plot moved and the pending
/// tasks moved with it (done tasks are never touched — FM-007).
@immutable
class CalendarChange {
  /// Creates the note.
  const CalendarChange({
    required this.cropPlotId,
    required this.movedDays,
    required this.moved,
    required this.added,
    required this.removed,
    required this.at,
    this.fromSowingDate,
    this.toSowingDate,
  });

  /// Parses the cached shape.
  factory CalendarChange.fromJson(Map<String, Object?> j) => CalendarChange(
    cropPlotId: '${j['crop_plot_id']}',
    fromSowingDate: parseIsoDate(j['from_sowing_date']),
    toSowingDate: parseIsoDate(j['to_sowing_date']),
    movedDays: _int(j['moved_days']),
    moved: _int(j['moved']),
    added: _int(j['added']),
    removed: _int(j['removed']),
    at: _time(j['at']) ?? DateTime.utc(1970),
  );

  /// Plot whose calendar changed.
  final String cropPlotId;

  /// Sowing date before.
  final DateTime? fromSowingDate;

  /// Sowing date after.
  final DateTime? toSowingDate;

  /// Days the sowing date moved (positive = later).
  final int movedDays;

  /// Pending tasks whose due date moved.
  final int moved;

  /// Tasks added.
  final int added;

  /// Tasks that disappeared.
  final int removed;

  /// When the change was noticed.
  final DateTime at;

  /// Something worth telling the farmer about.
  bool get isEmpty => moved == 0 && added == 0 && removed == 0;

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'crop_plot_id': cropPlotId,
    'from_sowing_date': fromSowingDate == null ? null : isoDay(fromSowingDate!),
    'to_sowing_date': toSowingDate == null ? null : isoDay(toSowingDate!),
    'moved_days': movedDays,
    'moved': moved,
    'added': added,
    'removed': removed,
    'at': at.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is CalendarChange &&
      other.cropPlotId == cropPlotId &&
      other.movedDays == movedDays &&
      other.moved == moved &&
      other.added == added &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(cropPlotId, movedDays, moved, added, removed);
}

/// Compares the tasks of a plot before and after a refresh (FM-007: the
/// server regenerates pending tasks in place, keeps their ids and never
/// touches done ones).
CalendarChange? diffPlotCalendar(
  CropPlotCalendar? before,
  CropPlotCalendar after, {
  required DateTime at,
}) {
  if (before == null) return null;
  final oldTasks = <String, CalendarTask>{
    for (final t in before.tasks) t.id: t,
  };
  final newTasks = <String, CalendarTask>{for (final t in after.tasks) t.id: t};
  var moved = 0;
  var movedDays = 0;
  for (final t in after.tasks) {
    final old = oldTasks[t.id];
    if (old == null || old.done) continue;
    final days = t.dueDate.difference(old.dueDate).inDays;
    if (days != 0) {
      moved += 1;
      if (movedDays == 0) movedDays = days;
    }
  }
  final added = newTasks.keys.where((id) => !oldTasks.containsKey(id)).length;
  final removed = oldTasks.keys.where((id) => !newTasks.containsKey(id)).length;
  final sowingMoved =
      before.sowingDate != null &&
      after.sowingDate != null &&
      before.sowingDate != after.sowingDate;
  if (sowingMoved) {
    movedDays = after.sowingDate!.difference(before.sowingDate!).inDays;
  }
  if (moved == 0 && added == 0 && removed == 0) return null;
  return CalendarChange(
    cropPlotId: after.cropPlotId,
    fromSowingDate: before.sowingDate,
    toSowingDate: after.sowingDate,
    movedDays: movedDays,
    moved: moved,
    added: added,
    removed: removed,
    at: at,
  );
}

// --- FM-008 weather and spray windows ---------------------------------------

/// One day of the 7-day forecast (`DailyForecastOut`).
@immutable
class DailyForecast {
  /// Creates the day.
  const DailyForecast({
    required this.date,
    required this.temperatureMaxC,
    required this.temperatureMinC,
    required this.precipitationMm,
    required this.precipitationProbabilityPct,
    required this.windMaxKmh,
    required this.weatherCode,
  });

  /// Parses the wire shape.
  factory DailyForecast.fromJson(Map<String, Object?> j) => DailyForecast(
    date: parseIsoDate(j['date']) ?? DateTime.utc(1970),
    temperatureMaxC: _num(j['temperature_max_c']),
    temperatureMinC: _num(j['temperature_min_c']),
    precipitationMm: _num(j['precipitation_mm']),
    precipitationProbabilityPct: _int(j['precipitation_probability_pct']),
    windMaxKmh: _num(j['wind_max_kmh']),
    weatherCode: _int(j['weather_code']),
  );

  /// Day (UTC midnight of the IST date).
  final DateTime date;

  /// Maximum temperature.
  final double temperatureMaxC;

  /// Minimum temperature.
  final double temperatureMinC;

  /// Total rain.
  final double precipitationMm;

  /// Chance of rain.
  final int precipitationProbabilityPct;

  /// Maximum wind.
  final double windMaxKmh;

  /// WMO weather code.
  final int weatherCode;

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'date': isoDay(date),
    'temperature_max_c': temperatureMaxC,
    'temperature_min_c': temperatureMinC,
    'precipitation_mm': precipitationMm,
    'precipitation_probability_pct': precipitationProbabilityPct,
    'wind_max_kmh': windMaxKmh,
    'weather_code': weatherCode,
  };

  @override
  bool operator ==(Object other) =>
      other is DailyForecast &&
      other.date == date &&
      other.temperatureMaxC == temperatureMaxC &&
      other.precipitationProbabilityPct == precipitationProbabilityPct;

  @override
  int get hashCode =>
      Object.hash(date, temperatureMaxC, precipitationProbabilityPct);
}

/// Thresholds the server used for the spray advice (`SprayThresholdsOut`).
@immutable
class SprayThresholds {
  /// Creates the thresholds.
  const SprayThresholds({
    this.maxRainProbabilityPct = 30,
    this.maxRainMm = 0.5,
    this.maxWindKmh = 15,
    this.cautionMaxTemperatureC = 35,
    this.cautionMaxHumidityPct = 90,
    this.cautionMinHumidityPct = 30,
  });

  /// Parses the wire shape.
  factory SprayThresholds.fromJson(Map<String, Object?> j) => SprayThresholds(
    maxRainProbabilityPct: j['max_rain_probability_pct'] == null
        ? 30
        : _int(j['max_rain_probability_pct']),
    maxRainMm: j['max_rain_mm'] == null ? 0.5 : _num(j['max_rain_mm']),
    maxWindKmh: j['max_wind_kmh'] == null ? 15 : _num(j['max_wind_kmh']),
    cautionMaxTemperatureC: j['caution_max_temperature_c'] == null
        ? 35
        : _num(j['caution_max_temperature_c']),
    cautionMaxHumidityPct: j['caution_max_humidity_pct'] == null
        ? 90
        : _int(j['caution_max_humidity_pct']),
    cautionMinHumidityPct: j['caution_min_humidity_pct'] == null
        ? 30
        : _int(j['caution_min_humidity_pct']),
  );

  /// Rain probability that hides a window.
  final int maxRainProbabilityPct;

  /// Rain in mm that hides a window.
  final double maxRainMm;

  /// Wind in km/h that hides a window.
  final double maxWindKmh;

  /// Above this the window gets a heat caution.
  final double cautionMaxTemperatureC;

  /// Above this the window gets a humidity caution.
  final int cautionMaxHumidityPct;

  /// Below this the window gets a dry-air caution.
  final int cautionMinHumidityPct;

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'max_rain_probability_pct': maxRainProbabilityPct,
    'max_rain_mm': maxRainMm,
    'max_wind_kmh': maxWindKmh,
    'caution_max_temperature_c': cautionMaxTemperatureC,
    'caution_max_humidity_pct': cautionMaxHumidityPct,
    'caution_min_humidity_pct': cautionMinHumidityPct,
  };

  @override
  bool operator ==(Object other) =>
      other is SprayThresholds &&
      other.maxRainProbabilityPct == maxRainProbabilityPct &&
      other.maxRainMm == maxRainMm &&
      other.maxWindKmh == maxWindKmh;

  @override
  int get hashCode => Object.hash(maxRainProbabilityPct, maxRainMm, maxWindKmh);
}

/// Why a spray window is not good. Codes are i18n keys (nothing is
/// translated server-side).
abstract final class SprayReasons {
  /// Rain is likely.
  static const String rainLikely = 'rain_likely';

  /// Rain is forecast.
  static const String rain = 'rain';

  /// Wind is too strong.
  static const String windHigh = 'wind_high';
}

/// One 3-hour spray window (`SprayWindowOut`).
@immutable
class SprayWindow {
  /// Creates the window.
  const SprayWindow({
    required this.start,
    required this.end,
    required this.advice,
    this.reasons = const <String>[],
    this.cautions = const <String>[],
    this.maxPrecipitationProbabilityPct = 0,
    this.precipitationMm = 0,
    this.maxWindKmh = 0,
    this.maxTemperatureC = 0,
    this.minRelativeHumidityPct,
    this.maxRelativeHumidityPct,
  });

  /// Parses the wire shape.
  factory SprayWindow.fromJson(Map<String, Object?> j) => SprayWindow(
    start: _time(j['start']) ?? DateTime.utc(1970),
    end: _time(j['end']) ?? DateTime.utc(1970),
    advice: (j['advice'] as String?) ?? 'good',
    reasons: _strings(j['reasons']),
    cautions: _strings(j['cautions']),
    maxPrecipitationProbabilityPct: _int(
      j['max_precipitation_probability_pct'],
    ),
    precipitationMm: _num(j['precipitation_mm']),
    maxWindKmh: _num(j['max_wind_kmh']),
    maxTemperatureC: _num(j['max_temperature_c']),
    minRelativeHumidityPct: j['min_relative_humidity_pct'] == null
        ? null
        : _int(j['min_relative_humidity_pct']),
    maxRelativeHumidityPct: j['max_relative_humidity_pct'] == null
        ? null
        : _int(j['max_relative_humidity_pct']),
  );

  /// Window start (UTC instant of the IST 3-hour slot).
  final DateTime start;

  /// Window end.
  final DateTime end;

  /// `good` | `avoid` as the server labelled it.
  final String advice;

  /// Why it is not good ([SprayReasons]).
  final List<String> reasons;

  /// Non-blocking warnings (`heat`, `humidity_high`, `humidity_low`).
  final List<String> cautions;

  /// Highest rain chance in the window.
  final int maxPrecipitationProbabilityPct;

  /// Rain in the window.
  final double precipitationMm;

  /// Highest wind in the window.
  final double maxWindKmh;

  /// Highest temperature in the window.
  final double maxTemperatureC;

  /// Lowest humidity.
  final int? minRelativeHumidityPct;

  /// Highest humidity.
  final int? maxRelativeHumidityPct;

  /// Re-checks the thresholds on the device, so a window that breaches
  /// rain or wind is never shown as good even if the server labelled it
  /// so (FM-008 acceptance: spray advice hides windows with rain or wind
  /// above the threshold).
  List<String> blockingReasons(SprayThresholds t) => <String>[
    if (maxPrecipitationProbabilityPct >= t.maxRainProbabilityPct)
      SprayReasons.rainLikely,
    if (precipitationMm >= t.maxRainMm) SprayReasons.rain,
    if (maxWindKmh >= t.maxWindKmh) SprayReasons.windHigh,
    for (final r in reasons)
      if (r != SprayReasons.rainLikely &&
          r != SprayReasons.rain &&
          r != SprayReasons.windHigh)
        r,
  ];

  /// Good to spray under [t] (and the server did not say otherwise).
  bool isGood(SprayThresholds t) =>
      advice == 'good' && blockingReasons(t).isEmpty;

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'advice': advice,
    'reasons': reasons,
    'cautions': cautions,
    'max_precipitation_probability_pct': maxPrecipitationProbabilityPct,
    'precipitation_mm': precipitationMm,
    'max_wind_kmh': maxWindKmh,
    'max_temperature_c': maxTemperatureC,
    'min_relative_humidity_pct': minRelativeHumidityPct,
    'max_relative_humidity_pct': maxRelativeHumidityPct,
  };

  @override
  bool operator ==(Object other) =>
      other is SprayWindow &&
      other.start == start &&
      other.advice == advice &&
      listEquals(other.reasons, reasons);

  @override
  int get hashCode => Object.hash(start, advice, Object.hashAll(reasons));
}

/// Spray advice for the next 72 h (`SprayAdviceOut`).
@immutable
class SprayAdvice {
  /// Creates the advice.
  const SprayAdvice({
    this.windows = const <SprayWindow>[],
    this.avoided = const <SprayWindow>[],
    this.thresholds = const SprayThresholds(),
  });

  /// Parses the wire shape.
  factory SprayAdvice.fromJson(Map<String, Object?> j) => SprayAdvice(
    windows: <SprayWindow>[
      for (final w in _maps(j['windows'])) SprayWindow.fromJson(w),
    ],
    avoided: <SprayWindow>[
      for (final w in _maps(j['avoided'])) SprayWindow.fromJson(w),
    ],
    thresholds: SprayThresholds.fromJson(
      j['thresholds'] is Map
          ? Map<String, Object?>.from(j['thresholds']! as Map)
          : const <String, Object?>{},
    ),
  );

  /// Windows the server considers good.
  final List<SprayWindow> windows;

  /// Windows the server hid, with their reasons.
  final List<SprayWindow> avoided;

  /// Thresholds used.
  final SprayThresholds thresholds;

  /// Every window in time order, good and avoided together.
  List<SprayWindow> get all =>
      <SprayWindow>[...windows, ...avoided]
        ..sort((a, b) => a.start.compareTo(b.start));

  /// Good windows only, re-checked against [thresholds] on the device.
  List<SprayWindow> get good => <SprayWindow>[
    for (final w in all)
      if (w.isGood(thresholds)) w,
  ];

  /// Windows to avoid: everything the server hid plus anything it called
  /// good that still breaches a threshold here.
  List<SprayWindow> get avoid => <SprayWindow>[
    for (final w in all)
      if (!w.isGood(thresholds)) w,
  ];

  /// Blocks of the first [days] IST days from [from], good and avoided,
  /// in time order (F43 shows three days).
  List<SprayWindow> blocks({required DateTime from, int days = 3}) {
    final until = from.add(Duration(days: days));
    return <SprayWindow>[
      for (final w in all)
        if (!w.start.isBefore(from) && w.start.isBefore(until)) w,
    ];
  }

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'windows': <Object?>[for (final w in windows) w.toJson()],
    'avoided': <Object?>[for (final w in avoided) w.toJson()],
    'thresholds': thresholds.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is SprayAdvice &&
      listEquals(other.windows, windows) &&
      listEquals(other.avoided, avoided) &&
      other.thresholds == thresholds;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(windows), Object.hashAll(avoided), thresholds);
}

/// `GET /v1/farms/{id}/weather` (`WeatherOut`). The hourly series is not
/// kept on the device: F43 shows the 7 days and the spray blocks.
@immutable
class FarmWeather {
  /// Creates the forecast.
  const FarmWeather({
    required this.farmId,
    required this.fetchedAt,
    this.latitude,
    this.longitude,
    this.locationSource,
    this.provider,
    this.cached = false,
    this.timezone,
    this.daily = const <DailyForecast>[],
    this.spray = const SprayAdvice(),
  });

  /// Parses the wire shape.
  factory FarmWeather.fromJson(Map<String, Object?> j) => FarmWeather(
    farmId: '${j['farm_id']}',
    latitude: j['latitude'] == null ? null : _num(j['latitude']),
    longitude: j['longitude'] == null ? null : _num(j['longitude']),
    locationSource: j['location_source'] as String?,
    provider: j['provider'] as String?,
    fetchedAt: _time(j['fetched_at']) ?? DateTime.utc(1970),
    cached: j['cached'] == true,
    timezone: j['timezone'] as String?,
    daily: <DailyForecast>[
      for (final d in _maps(j['daily'])) DailyForecast.fromJson(d),
    ],
    spray: SprayAdvice.fromJson(
      j['spray'] is Map
          ? Map<String, Object?>.from(j['spray']! as Map)
          : const <String, Object?>{},
    ),
  );

  /// Farm.
  final String farmId;

  /// Grid-cell latitude the provider was asked about.
  final double? latitude;

  /// Grid-cell longitude.
  final double? longitude;

  /// `farm` | `village`.
  final String? locationSource;

  /// Forecast provider.
  final String? provider;

  /// When the server fetched it from the provider.
  final DateTime fetchedAt;

  /// The server answered from its own cache.
  final bool cached;

  /// Forecast timezone (`Asia/Kolkata`).
  final String? timezone;

  /// Seven days.
  final List<DailyForecast> daily;

  /// Spray advice.
  final SprayAdvice spray;

  /// Wire shape (as cached; the hourly series is dropped).
  Map<String, Object?> toJson() => <String, Object?>{
    'farm_id': farmId,
    'latitude': latitude,
    'longitude': longitude,
    'location_source': locationSource,
    'provider': provider,
    'fetched_at': fetchedAt.toIso8601String(),
    'cached': cached,
    'timezone': timezone,
    'daily': <Object?>[for (final d in daily) d.toJson()],
    'spray': spray.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is FarmWeather &&
      other.farmId == farmId &&
      other.fetchedAt == fetchedAt &&
      listEquals(other.daily, daily) &&
      other.spray == spray;

  @override
  int get hashCode =>
      Object.hash(farmId, fetchedAt, Object.hashAll(daily), spray);
}

// --- FM-009 district alerts --------------------------------------------------

/// How bad an alert is. The API sends counts, not a severity: the app
/// derives one from the case count against the district baseline so F44
/// can sort and colour the list (documented in design/screens/F44.md).
enum AlertSeverity {
  /// Cases far above the baseline, or many farmers hit.
  high,

  /// Clearly above the baseline.
  medium,

  /// Just over the rule's threshold.
  low,
}

/// One district pest or disease alert (`OutbreakAlertOut`).
@immutable
class OutbreakAlert {
  /// Creates the alert.
  const OutbreakAlert({
    required this.id,
    required this.district,
    required this.cropId,
    required this.cropCode,
    required this.problemId,
    required this.problemType,
    required this.weekStart,
    required this.caseCount,
    required this.farmersAffected,
    required this.baselineMean,
    this.cropNames = const <String, String>{},
    this.problemCode,
    this.problemNames = const <String, String>{},
    this.isoYear = 0,
    this.isoWeek = 0,
    this.status = 'active',
    this.growsCrop,
    this.createdAt,
  });

  /// Parses the wire shape.
  factory OutbreakAlert.fromJson(Map<String, Object?> j) => OutbreakAlert(
    id: '${j['id']}',
    district: (j['district'] as String?) ?? '',
    cropId: '${j['crop_id']}',
    cropCode: (j['crop_code'] as String?) ?? '',
    cropNames: _names(j['crop_names']),
    problemId: '${j['problem_id']}',
    problemCode: j['problem_code'] as String?,
    problemType: (j['problem_type'] as String?) ?? 'pest',
    problemNames: _names(j['problem_names']),
    weekStart: parseIsoDate(j['week_start']) ?? DateTime.utc(1970),
    isoYear: _int(j['iso_year']),
    isoWeek: _int(j['iso_week']),
    caseCount: _int(j['case_count']),
    farmersAffected: _int(j['farmers_affected']),
    baselineMean: _num(j['baseline_mean']),
    status: (j['status'] as String?) ?? 'active',
    growsCrop: j['grows_crop'] as bool?,
    createdAt: _time(j['created_at']),
  );

  /// Alert id.
  final String id;

  /// District.
  final String district;

  /// Crop.
  final String cropId;

  /// Crop code.
  final String cropCode;

  /// Crop names per language.
  final Map<String, String> cropNames;

  /// Problem.
  final String problemId;

  /// Problem code.
  final String? problemCode;

  /// `pest` | `disease` | `deficiency` | `weed`.
  final String problemType;

  /// Problem names per language.
  final Map<String, String> problemNames;

  /// Monday of the ISO week.
  final DateTime weekStart;

  /// ISO year.
  final int isoYear;

  /// ISO week.
  final int isoWeek;

  /// Confirmed cases that week.
  final int caseCount;

  /// Farmers affected.
  final int farmersAffected;

  /// Baseline mean of the previous weeks.
  final double baselineMean;

  /// `active` | `closed`.
  final String status;

  /// One of the farmer's plots grows this crop.
  final bool? growsCrop;

  /// Raised at.
  final DateTime? createdAt;

  /// Crop name in [language].
  String? cropNameIn(String language) => localised(cropNames, language);

  /// Problem name in [language].
  String? problemNameIn(String language) => localised(problemNames, language);

  /// Cases against the district baseline (1.0 when there is no baseline).
  double get ratio =>
      baselineMean <= 0 ? caseCount.toDouble() : caseCount / baselineMean;

  /// Derived severity: `high` at three times the baseline or ten farmers
  /// hit, `medium` at twice the baseline or five farmers, else `low`.
  AlertSeverity get severity {
    if (ratio >= 3 || farmersAffected >= 10) return AlertSeverity.high;
    if (ratio >= 2 || farmersAffected >= 5) return AlertSeverity.medium;
    return AlertSeverity.low;
  }

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'district': district,
    'crop_id': cropId,
    'crop_code': cropCode,
    'crop_names': cropNames,
    'problem_id': problemId,
    'problem_code': problemCode,
    'problem_type': problemType,
    'problem_names': problemNames,
    'week_start': isoDay(weekStart),
    'iso_year': isoYear,
    'iso_week': isoWeek,
    'case_count': caseCount,
    'farmers_affected': farmersAffected,
    'baseline_mean': baselineMean,
    'status': status,
    'grows_crop': growsCrop,
    'created_at': createdAt?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is OutbreakAlert &&
      other.id == id &&
      other.caseCount == caseCount &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, caseCount, status);
}

// --- FA-007 notification inbox ----------------------------------------------

/// Notification kinds the farmer app understands (FA-007 deep links).
abstract final class NotificationKinds {
  /// The agronomist confirmed or corrected a crop check (F27).
  static const String diagnosisReviewed = 'diagnosis_reviewed';

  /// A crop check finished.
  static const String diagnosisReady = 'diagnosis_ready';

  /// An expert was asked to look at a crop check.
  static const String diagnosisExpertRequested = 'diagnosis_expert_requested';

  /// An order moved on.
  static const String orderStatus = 'order_status';

  /// A district pest or disease alert (FM-009).
  static const String outbreakAlert = 'outbreak_alert';

  /// A calendar task is due today (FM-007).
  static const String cropTaskReminder = 'crop_task_reminder';

  /// "Did your officer visit today?" (FM-011).
  static const String visitConfirmRequest = 'visit_confirm_request';
}

/// One inbox row (`NotificationOut`).
@immutable
class AppNotification {
  /// Creates the row.
  const AppNotification({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.titleKey = '',
    this.bodyKey = '',
    this.data = const <String, String>{},
    this.route = '/inbox',
    this.readAt,
    this.deliveryStatus,
  });

  /// Parses the wire shape.
  factory AppNotification.fromJson(Map<String, Object?> j) => AppNotification(
    id: '${j['id']}',
    kind: (j['kind'] as String?) ?? '',
    titleKey: (j['title_key'] as String?) ?? '',
    bodyKey: (j['body_key'] as String?) ?? '',
    data: <String, String>{
      for (final e
          in (j['data'] is Map
              ? (j['data']! as Map).entries
              : const <MapEntry<Object?, Object?>>[]))
        '${e.key}': '${e.value}',
    },
    route: (j['route'] as String?) ?? '/inbox',
    createdAt: _time(j['created_at']) ?? DateTime.utc(1970),
    readAt: _time(j['read_at']),
    deliveryStatus: j['delivery_status'] as String?,
  );

  /// Row id.
  final String id;

  /// Notification kind ([NotificationKinds]).
  final String kind;

  /// i18n key of the title (the app resolves it; no text from the server).
  final String titleKey;

  /// i18n key of the body.
  final String bodyKey;

  /// Ids for the deep link.
  final Map<String, String> data;

  /// Where the app opens this row (FA-007).
  final String route;

  /// When it was created (UTC).
  final DateTime createdAt;

  /// When the farmer read it.
  final DateTime? readAt;

  /// `pending` | `delivered` | `failed` | `no_device` | `skipped`.
  final String? deliveryStatus;

  /// Not read yet (drives the badge).
  bool get unread => readAt == null;

  /// A copy marked read at [at].
  AppNotification readNow(DateTime at) => AppNotification(
    id: id,
    kind: kind,
    titleKey: titleKey,
    bodyKey: bodyKey,
    data: data,
    route: route,
    createdAt: createdAt,
    readAt: readAt ?? at,
    deliveryStatus: deliveryStatus,
  );

  /// Wire shape (as cached).
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'title_key': titleKey,
    'body_key': bodyKey,
    'data': data,
    'route': route,
    'created_at': createdAt.toIso8601String(),
    'read_at': readAt?.toIso8601String(),
    'delivery_status': deliveryStatus,
  };

  @override
  bool operator ==(Object other) =>
      other is AppNotification &&
      other.id == id &&
      other.readAt == readAt &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(id, readAt, kind);
}
