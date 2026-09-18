// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $KvTable extends Kv with TableInfo<$KvTable, KvData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $KvTable createAlias(String alias) {
    return $KvTable(attachedDatabase, alias);
  }
}

class KvData extends DataClass implements Insertable<KvData> {
  /// Setting key, e.g. `theme_mode` or `locale`.
  final String key;

  /// Stored value as text (callers encode JSON when needed).
  final String value;

  /// Last write time in UTC.
  final DateTime updatedAt;
  const KvData({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  KvCompanion toCompanion(bool nullToAbsent) {
    return KvCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory KvData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  KvData copyWith({String? key, String? value, DateTime? updatedAt}) => KvData(
    key: key ?? this.key,
    value: value ?? this.value,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  KvData copyWithCompanion(KvCompanion data) {
    return KvData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class KvCompanion extends UpdateCompanion<KvData> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const KvCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvCompanion.insert({
    required String key,
    required String value,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAt = Value(updatedAt);
  static Insertable<KvData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return KvCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FarmersTable extends Farmers with TableInfo<$FarmersTable, Farmer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FarmersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _villageIdMeta = const VerificationMeta(
    'villageId',
  );
  @override
  late final GeneratedColumn<String> villageId = GeneratedColumn<String>(
    'village_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _landmarkMeta = const VerificationMeta(
    'landmark',
  );
  @override
  late final GeneratedColumn<String> landmark = GeneratedColumn<String>(
    'landmark',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preferredLanguageMeta = const VerificationMeta(
    'preferredLanguage',
  );
  @override
  late final GeneratedColumn<String> preferredLanguage =
      GeneratedColumn<String>(
        'preferred_language',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _landOwnershipMeta = const VerificationMeta(
    'landOwnership',
  );
  @override
  late final GeneratedColumn<String> landOwnership = GeneratedColumn<String>(
    'land_ownership',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phoneVerifiedMeta = const VerificationMeta(
    'phoneVerified',
  );
  @override
  late final GeneratedColumn<bool> phoneVerified = GeneratedColumn<bool>(
    'phone_verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("phone_verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _consentMarketingMeta = const VerificationMeta(
    'consentMarketing',
  );
  @override
  late final GeneratedColumn<bool> consentMarketing = GeneratedColumn<bool>(
    'consent_marketing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("consent_marketing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    phone,
    name,
    villageId,
    landmark,
    language,
    preferredLanguage,
    landOwnership,
    source,
    phoneVerified,
    consentMarketing,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'farmers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Farmer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('village_id')) {
      context.handle(
        _villageIdMeta,
        villageId.isAcceptableOrUnknown(data['village_id']!, _villageIdMeta),
      );
    }
    if (data.containsKey('landmark')) {
      context.handle(
        _landmarkMeta,
        landmark.isAcceptableOrUnknown(data['landmark']!, _landmarkMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('preferred_language')) {
      context.handle(
        _preferredLanguageMeta,
        preferredLanguage.isAcceptableOrUnknown(
          data['preferred_language']!,
          _preferredLanguageMeta,
        ),
      );
    }
    if (data.containsKey('land_ownership')) {
      context.handle(
        _landOwnershipMeta,
        landOwnership.isAcceptableOrUnknown(
          data['land_ownership']!,
          _landOwnershipMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('phone_verified')) {
      context.handle(
        _phoneVerifiedMeta,
        phoneVerified.isAcceptableOrUnknown(
          data['phone_verified']!,
          _phoneVerifiedMeta,
        ),
      );
    }
    if (data.containsKey('consent_marketing')) {
      context.handle(
        _consentMarketingMeta,
        consentMarketing.isAcceptableOrUnknown(
          data['consent_marketing']!,
          _consentMarketingMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Farmer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Farmer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      villageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}village_id'],
      ),
      landmark: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}landmark'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      preferredLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preferred_language'],
      ),
      landOwnership: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}land_ownership'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      phoneVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}phone_verified'],
      )!,
      consentMarketing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}consent_marketing'],
      )!,
    );
  }

  @override
  $FarmersTable createAlias(String alias) {
    return $FarmersTable(attachedDatabase, alias);
  }
}

class Farmer extends DataClass implements Insertable<Farmer> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// E.164 phone.
  final String? phone;

  /// Display name.
  final String name;

  /// Village id (reference data in `synced_refs`).
  final String? villageId;

  /// Landmark near the home.
  final String? landmark;

  /// Spoken language code.
  final String? language;

  /// Preferred language for messages.
  final String? preferredLanguage;

  /// `own` | `leased`.
  final String? landOwnership;

  /// How the farmer was acquired (e.g. `field_officer`).
  final String? source;

  /// Phone verified by OTP at registration.
  final bool phoneVerified;

  /// Marketing consent cache (FM-002).
  final bool consentMarketing;
  const Farmer({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    this.phone,
    required this.name,
    this.villageId,
    this.landmark,
    this.language,
    this.preferredLanguage,
    this.landOwnership,
    this.source,
    required this.phoneVerified,
    required this.consentMarketing,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || villageId != null) {
      map['village_id'] = Variable<String>(villageId);
    }
    if (!nullToAbsent || landmark != null) {
      map['landmark'] = Variable<String>(landmark);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    if (!nullToAbsent || preferredLanguage != null) {
      map['preferred_language'] = Variable<String>(preferredLanguage);
    }
    if (!nullToAbsent || landOwnership != null) {
      map['land_ownership'] = Variable<String>(landOwnership);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    map['phone_verified'] = Variable<bool>(phoneVerified);
    map['consent_marketing'] = Variable<bool>(consentMarketing);
    return map;
  }

  FarmersCompanion toCompanion(bool nullToAbsent) {
    return FarmersCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      name: Value(name),
      villageId: villageId == null && nullToAbsent
          ? const Value.absent()
          : Value(villageId),
      landmark: landmark == null && nullToAbsent
          ? const Value.absent()
          : Value(landmark),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      preferredLanguage: preferredLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(preferredLanguage),
      landOwnership: landOwnership == null && nullToAbsent
          ? const Value.absent()
          : Value(landOwnership),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      phoneVerified: Value(phoneVerified),
      consentMarketing: Value(consentMarketing),
    );
  }

  factory Farmer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Farmer(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      phone: serializer.fromJson<String?>(json['phone']),
      name: serializer.fromJson<String>(json['name']),
      villageId: serializer.fromJson<String?>(json['villageId']),
      landmark: serializer.fromJson<String?>(json['landmark']),
      language: serializer.fromJson<String?>(json['language']),
      preferredLanguage: serializer.fromJson<String?>(
        json['preferredLanguage'],
      ),
      landOwnership: serializer.fromJson<String?>(json['landOwnership']),
      source: serializer.fromJson<String?>(json['source']),
      phoneVerified: serializer.fromJson<bool>(json['phoneVerified']),
      consentMarketing: serializer.fromJson<bool>(json['consentMarketing']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'phone': serializer.toJson<String?>(phone),
      'name': serializer.toJson<String>(name),
      'villageId': serializer.toJson<String?>(villageId),
      'landmark': serializer.toJson<String?>(landmark),
      'language': serializer.toJson<String?>(language),
      'preferredLanguage': serializer.toJson<String?>(preferredLanguage),
      'landOwnership': serializer.toJson<String?>(landOwnership),
      'source': serializer.toJson<String?>(source),
      'phoneVerified': serializer.toJson<bool>(phoneVerified),
      'consentMarketing': serializer.toJson<bool>(consentMarketing),
    };
  }

  Farmer copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    Value<String?> phone = const Value.absent(),
    String? name,
    Value<String?> villageId = const Value.absent(),
    Value<String?> landmark = const Value.absent(),
    Value<String?> language = const Value.absent(),
    Value<String?> preferredLanguage = const Value.absent(),
    Value<String?> landOwnership = const Value.absent(),
    Value<String?> source = const Value.absent(),
    bool? phoneVerified,
    bool? consentMarketing,
  }) => Farmer(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    phone: phone.present ? phone.value : this.phone,
    name: name ?? this.name,
    villageId: villageId.present ? villageId.value : this.villageId,
    landmark: landmark.present ? landmark.value : this.landmark,
    language: language.present ? language.value : this.language,
    preferredLanguage: preferredLanguage.present
        ? preferredLanguage.value
        : this.preferredLanguage,
    landOwnership: landOwnership.present
        ? landOwnership.value
        : this.landOwnership,
    source: source.present ? source.value : this.source,
    phoneVerified: phoneVerified ?? this.phoneVerified,
    consentMarketing: consentMarketing ?? this.consentMarketing,
  );
  Farmer copyWithCompanion(FarmersCompanion data) {
    return Farmer(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      phone: data.phone.present ? data.phone.value : this.phone,
      name: data.name.present ? data.name.value : this.name,
      villageId: data.villageId.present ? data.villageId.value : this.villageId,
      landmark: data.landmark.present ? data.landmark.value : this.landmark,
      language: data.language.present ? data.language.value : this.language,
      preferredLanguage: data.preferredLanguage.present
          ? data.preferredLanguage.value
          : this.preferredLanguage,
      landOwnership: data.landOwnership.present
          ? data.landOwnership.value
          : this.landOwnership,
      source: data.source.present ? data.source.value : this.source,
      phoneVerified: data.phoneVerified.present
          ? data.phoneVerified.value
          : this.phoneVerified,
      consentMarketing: data.consentMarketing.present
          ? data.consentMarketing.value
          : this.consentMarketing,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Farmer(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('phone: $phone, ')
          ..write('name: $name, ')
          ..write('villageId: $villageId, ')
          ..write('landmark: $landmark, ')
          ..write('language: $language, ')
          ..write('preferredLanguage: $preferredLanguage, ')
          ..write('landOwnership: $landOwnership, ')
          ..write('source: $source, ')
          ..write('phoneVerified: $phoneVerified, ')
          ..write('consentMarketing: $consentMarketing')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    phone,
    name,
    villageId,
    landmark,
    language,
    preferredLanguage,
    landOwnership,
    source,
    phoneVerified,
    consentMarketing,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Farmer &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.phone == this.phone &&
          other.name == this.name &&
          other.villageId == this.villageId &&
          other.landmark == this.landmark &&
          other.language == this.language &&
          other.preferredLanguage == this.preferredLanguage &&
          other.landOwnership == this.landOwnership &&
          other.source == this.source &&
          other.phoneVerified == this.phoneVerified &&
          other.consentMarketing == this.consentMarketing);
}

class FarmersCompanion extends UpdateCompanion<Farmer> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String?> phone;
  final Value<String> name;
  final Value<String?> villageId;
  final Value<String?> landmark;
  final Value<String?> language;
  final Value<String?> preferredLanguage;
  final Value<String?> landOwnership;
  final Value<String?> source;
  final Value<bool> phoneVerified;
  final Value<bool> consentMarketing;
  final Value<int> rowid;
  const FarmersCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.phone = const Value.absent(),
    this.name = const Value.absent(),
    this.villageId = const Value.absent(),
    this.landmark = const Value.absent(),
    this.language = const Value.absent(),
    this.preferredLanguage = const Value.absent(),
    this.landOwnership = const Value.absent(),
    this.source = const Value.absent(),
    this.phoneVerified = const Value.absent(),
    this.consentMarketing = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FarmersCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.phone = const Value.absent(),
    this.name = const Value.absent(),
    this.villageId = const Value.absent(),
    this.landmark = const Value.absent(),
    this.language = const Value.absent(),
    this.preferredLanguage = const Value.absent(),
    this.landOwnership = const Value.absent(),
    this.source = const Value.absent(),
    this.phoneVerified = const Value.absent(),
    this.consentMarketing = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt);
  static Insertable<Farmer> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? phone,
    Expression<String>? name,
    Expression<String>? villageId,
    Expression<String>? landmark,
    Expression<String>? language,
    Expression<String>? preferredLanguage,
    Expression<String>? landOwnership,
    Expression<String>? source,
    Expression<bool>? phoneVerified,
    Expression<bool>? consentMarketing,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (phone != null) 'phone': phone,
      if (name != null) 'name': name,
      if (villageId != null) 'village_id': villageId,
      if (landmark != null) 'landmark': landmark,
      if (language != null) 'language': language,
      if (preferredLanguage != null) 'preferred_language': preferredLanguage,
      if (landOwnership != null) 'land_ownership': landOwnership,
      if (source != null) 'source': source,
      if (phoneVerified != null) 'phone_verified': phoneVerified,
      if (consentMarketing != null) 'consent_marketing': consentMarketing,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FarmersCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String?>? phone,
    Value<String>? name,
    Value<String?>? villageId,
    Value<String?>? landmark,
    Value<String?>? language,
    Value<String?>? preferredLanguage,
    Value<String?>? landOwnership,
    Value<String?>? source,
    Value<bool>? phoneVerified,
    Value<bool>? consentMarketing,
    Value<int>? rowid,
  }) {
    return FarmersCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      villageId: villageId ?? this.villageId,
      landmark: landmark ?? this.landmark,
      language: language ?? this.language,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      landOwnership: landOwnership ?? this.landOwnership,
      source: source ?? this.source,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      consentMarketing: consentMarketing ?? this.consentMarketing,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (villageId.present) {
      map['village_id'] = Variable<String>(villageId.value);
    }
    if (landmark.present) {
      map['landmark'] = Variable<String>(landmark.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (preferredLanguage.present) {
      map['preferred_language'] = Variable<String>(preferredLanguage.value);
    }
    if (landOwnership.present) {
      map['land_ownership'] = Variable<String>(landOwnership.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (phoneVerified.present) {
      map['phone_verified'] = Variable<bool>(phoneVerified.value);
    }
    if (consentMarketing.present) {
      map['consent_marketing'] = Variable<bool>(consentMarketing.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FarmersCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('phone: $phone, ')
          ..write('name: $name, ')
          ..write('villageId: $villageId, ')
          ..write('landmark: $landmark, ')
          ..write('language: $language, ')
          ..write('preferredLanguage: $preferredLanguage, ')
          ..write('landOwnership: $landOwnership, ')
          ..write('source: $source, ')
          ..write('phoneVerified: $phoneVerified, ')
          ..write('consentMarketing: $consentMarketing, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FarmsTable extends Farms with TableInfo<$FarmsTable, Farm> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FarmsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _farmerIdMeta = const VerificationMeta(
    'farmerId',
  );
  @override
  late final GeneratedColumn<String> farmerId = GeneratedColumn<String>(
    'farmer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _boundaryMeta = const VerificationMeta(
    'boundary',
  );
  @override
  late final GeneratedColumn<String> boundary = GeneratedColumn<String>(
    'boundary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _areaAcresMeta = const VerificationMeta(
    'areaAcres',
  );
  @override
  late final GeneratedColumn<double> areaAcres = GeneratedColumn<double>(
    'area_acres',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _soilMeta = const VerificationMeta('soil');
  @override
  late final GeneratedColumn<String> soil = GeneratedColumn<String>(
    'soil',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _irrigationMeta = const VerificationMeta(
    'irrigation',
  );
  @override
  late final GeneratedColumn<String> irrigation = GeneratedColumn<String>(
    'irrigation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ownershipMeta = const VerificationMeta(
    'ownership',
  );
  @override
  late final GeneratedColumn<String> ownership = GeneratedColumn<String>(
    'ownership',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photosMeta = const VerificationMeta('photos');
  @override
  late final GeneratedColumn<String> photos = GeneratedColumn<String>(
    'photos',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    name,
    boundary,
    areaAcres,
    soil,
    irrigation,
    ownership,
    photos,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'farms';
  @override
  VerificationContext validateIntegrity(
    Insertable<Farm> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('farmer_id')) {
      context.handle(
        _farmerIdMeta,
        farmerId.isAcceptableOrUnknown(data['farmer_id']!, _farmerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmerIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('boundary')) {
      context.handle(
        _boundaryMeta,
        boundary.isAcceptableOrUnknown(data['boundary']!, _boundaryMeta),
      );
    }
    if (data.containsKey('area_acres')) {
      context.handle(
        _areaAcresMeta,
        areaAcres.isAcceptableOrUnknown(data['area_acres']!, _areaAcresMeta),
      );
    }
    if (data.containsKey('soil')) {
      context.handle(
        _soilMeta,
        soil.isAcceptableOrUnknown(data['soil']!, _soilMeta),
      );
    }
    if (data.containsKey('irrigation')) {
      context.handle(
        _irrigationMeta,
        irrigation.isAcceptableOrUnknown(data['irrigation']!, _irrigationMeta),
      );
    }
    if (data.containsKey('ownership')) {
      context.handle(
        _ownershipMeta,
        ownership.isAcceptableOrUnknown(data['ownership']!, _ownershipMeta),
      );
    }
    if (data.containsKey('photos')) {
      context.handle(
        _photosMeta,
        photos.isAcceptableOrUnknown(data['photos']!, _photosMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Farm map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Farm(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      farmerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farmer_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      boundary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}boundary'],
      ),
      areaAcres: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}area_acres'],
      ),
      soil: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}soil'],
      ),
      irrigation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}irrigation'],
      ),
      ownership: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ownership'],
      ),
      photos: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photos'],
      )!,
    );
  }

  @override
  $FarmsTable createAlias(String alias) {
    return $FarmsTable(attachedDatabase, alias);
  }
}

class Farm extends DataClass implements Insertable<Farm> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Owning farmer.
  final String farmerId;

  /// Farm label.
  final String? name;

  /// GeoJSON Polygon as text.
  final String? boundary;

  /// Area in acres as entered.
  final double? areaAcres;

  /// Soil type.
  final String? soil;

  /// Irrigation type.
  final String? irrigation;

  /// `own` | `leased`.
  final String? ownership;

  /// JSON list of blob URIs (or `upload:<id>` placeholders while queued).
  final String photos;
  const Farm({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    required this.farmerId,
    this.name,
    this.boundary,
    this.areaAcres,
    this.soil,
    this.irrigation,
    this.ownership,
    required this.photos,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['farmer_id'] = Variable<String>(farmerId);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || boundary != null) {
      map['boundary'] = Variable<String>(boundary);
    }
    if (!nullToAbsent || areaAcres != null) {
      map['area_acres'] = Variable<double>(areaAcres);
    }
    if (!nullToAbsent || soil != null) {
      map['soil'] = Variable<String>(soil);
    }
    if (!nullToAbsent || irrigation != null) {
      map['irrigation'] = Variable<String>(irrigation);
    }
    if (!nullToAbsent || ownership != null) {
      map['ownership'] = Variable<String>(ownership);
    }
    map['photos'] = Variable<String>(photos);
    return map;
  }

  FarmsCompanion toCompanion(bool nullToAbsent) {
    return FarmsCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      farmerId: Value(farmerId),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      boundary: boundary == null && nullToAbsent
          ? const Value.absent()
          : Value(boundary),
      areaAcres: areaAcres == null && nullToAbsent
          ? const Value.absent()
          : Value(areaAcres),
      soil: soil == null && nullToAbsent ? const Value.absent() : Value(soil),
      irrigation: irrigation == null && nullToAbsent
          ? const Value.absent()
          : Value(irrigation),
      ownership: ownership == null && nullToAbsent
          ? const Value.absent()
          : Value(ownership),
      photos: Value(photos),
    );
  }

  factory Farm.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Farm(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      farmerId: serializer.fromJson<String>(json['farmerId']),
      name: serializer.fromJson<String?>(json['name']),
      boundary: serializer.fromJson<String?>(json['boundary']),
      areaAcres: serializer.fromJson<double?>(json['areaAcres']),
      soil: serializer.fromJson<String?>(json['soil']),
      irrigation: serializer.fromJson<String?>(json['irrigation']),
      ownership: serializer.fromJson<String?>(json['ownership']),
      photos: serializer.fromJson<String>(json['photos']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'farmerId': serializer.toJson<String>(farmerId),
      'name': serializer.toJson<String?>(name),
      'boundary': serializer.toJson<String?>(boundary),
      'areaAcres': serializer.toJson<double?>(areaAcres),
      'soil': serializer.toJson<String?>(soil),
      'irrigation': serializer.toJson<String?>(irrigation),
      'ownership': serializer.toJson<String?>(ownership),
      'photos': serializer.toJson<String>(photos),
    };
  }

  Farm copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    String? farmerId,
    Value<String?> name = const Value.absent(),
    Value<String?> boundary = const Value.absent(),
    Value<double?> areaAcres = const Value.absent(),
    Value<String?> soil = const Value.absent(),
    Value<String?> irrigation = const Value.absent(),
    Value<String?> ownership = const Value.absent(),
    String? photos,
  }) => Farm(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    farmerId: farmerId ?? this.farmerId,
    name: name.present ? name.value : this.name,
    boundary: boundary.present ? boundary.value : this.boundary,
    areaAcres: areaAcres.present ? areaAcres.value : this.areaAcres,
    soil: soil.present ? soil.value : this.soil,
    irrigation: irrigation.present ? irrigation.value : this.irrigation,
    ownership: ownership.present ? ownership.value : this.ownership,
    photos: photos ?? this.photos,
  );
  Farm copyWithCompanion(FarmsCompanion data) {
    return Farm(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      farmerId: data.farmerId.present ? data.farmerId.value : this.farmerId,
      name: data.name.present ? data.name.value : this.name,
      boundary: data.boundary.present ? data.boundary.value : this.boundary,
      areaAcres: data.areaAcres.present ? data.areaAcres.value : this.areaAcres,
      soil: data.soil.present ? data.soil.value : this.soil,
      irrigation: data.irrigation.present
          ? data.irrigation.value
          : this.irrigation,
      ownership: data.ownership.present ? data.ownership.value : this.ownership,
      photos: data.photos.present ? data.photos.value : this.photos,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Farm(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('name: $name, ')
          ..write('boundary: $boundary, ')
          ..write('areaAcres: $areaAcres, ')
          ..write('soil: $soil, ')
          ..write('irrigation: $irrigation, ')
          ..write('ownership: $ownership, ')
          ..write('photos: $photos')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    name,
    boundary,
    areaAcres,
    soil,
    irrigation,
    ownership,
    photos,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Farm &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.farmerId == this.farmerId &&
          other.name == this.name &&
          other.boundary == this.boundary &&
          other.areaAcres == this.areaAcres &&
          other.soil == this.soil &&
          other.irrigation == this.irrigation &&
          other.ownership == this.ownership &&
          other.photos == this.photos);
}

class FarmsCompanion extends UpdateCompanion<Farm> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String> farmerId;
  final Value<String?> name;
  final Value<String?> boundary;
  final Value<double?> areaAcres;
  final Value<String?> soil;
  final Value<String?> irrigation;
  final Value<String?> ownership;
  final Value<String> photos;
  final Value<int> rowid;
  const FarmsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.farmerId = const Value.absent(),
    this.name = const Value.absent(),
    this.boundary = const Value.absent(),
    this.areaAcres = const Value.absent(),
    this.soil = const Value.absent(),
    this.irrigation = const Value.absent(),
    this.ownership = const Value.absent(),
    this.photos = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FarmsCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required String farmerId,
    this.name = const Value.absent(),
    this.boundary = const Value.absent(),
    this.areaAcres = const Value.absent(),
    this.soil = const Value.absent(),
    this.irrigation = const Value.absent(),
    this.ownership = const Value.absent(),
    this.photos = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       farmerId = Value(farmerId);
  static Insertable<Farm> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? farmerId,
    Expression<String>? name,
    Expression<String>? boundary,
    Expression<double>? areaAcres,
    Expression<String>? soil,
    Expression<String>? irrigation,
    Expression<String>? ownership,
    Expression<String>? photos,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (farmerId != null) 'farmer_id': farmerId,
      if (name != null) 'name': name,
      if (boundary != null) 'boundary': boundary,
      if (areaAcres != null) 'area_acres': areaAcres,
      if (soil != null) 'soil': soil,
      if (irrigation != null) 'irrigation': irrigation,
      if (ownership != null) 'ownership': ownership,
      if (photos != null) 'photos': photos,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FarmsCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String>? farmerId,
    Value<String?>? name,
    Value<String?>? boundary,
    Value<double?>? areaAcres,
    Value<String?>? soil,
    Value<String?>? irrigation,
    Value<String?>? ownership,
    Value<String>? photos,
    Value<int>? rowid,
  }) {
    return FarmsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      farmerId: farmerId ?? this.farmerId,
      name: name ?? this.name,
      boundary: boundary ?? this.boundary,
      areaAcres: areaAcres ?? this.areaAcres,
      soil: soil ?? this.soil,
      irrigation: irrigation ?? this.irrigation,
      ownership: ownership ?? this.ownership,
      photos: photos ?? this.photos,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (farmerId.present) {
      map['farmer_id'] = Variable<String>(farmerId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (boundary.present) {
      map['boundary'] = Variable<String>(boundary.value);
    }
    if (areaAcres.present) {
      map['area_acres'] = Variable<double>(areaAcres.value);
    }
    if (soil.present) {
      map['soil'] = Variable<String>(soil.value);
    }
    if (irrigation.present) {
      map['irrigation'] = Variable<String>(irrigation.value);
    }
    if (ownership.present) {
      map['ownership'] = Variable<String>(ownership.value);
    }
    if (photos.present) {
      map['photos'] = Variable<String>(photos.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FarmsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('name: $name, ')
          ..write('boundary: $boundary, ')
          ..write('areaAcres: $areaAcres, ')
          ..write('soil: $soil, ')
          ..write('irrigation: $irrigation, ')
          ..write('ownership: $ownership, ')
          ..write('photos: $photos, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CropPlotsTable extends CropPlots
    with TableInfo<$CropPlotsTable, CropPlot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CropPlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cropIdMeta = const VerificationMeta('cropId');
  @override
  late final GeneratedColumn<String> cropId = GeneratedColumn<String>(
    'crop_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _varietyMeta = const VerificationMeta(
    'variety',
  );
  @override
  late final GeneratedColumn<String> variety = GeneratedColumn<String>(
    'variety',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonMeta = const VerificationMeta('season');
  @override
  late final GeneratedColumn<String> season = GeneratedColumn<String>(
    'season',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sowingDateMeta = const VerificationMeta(
    'sowingDate',
  );
  @override
  late final GeneratedColumn<String> sowingDate = GeneratedColumn<String>(
    'sowing_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _areaAcresMeta = const VerificationMeta(
    'areaAcres',
  );
  @override
  late final GeneratedColumn<double> areaAcres = GeneratedColumn<double>(
    'area_acres',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmId,
    cropId,
    variety,
    season,
    sowingDate,
    stage,
    areaAcres,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'crop_plots';
  @override
  VerificationContext validateIntegrity(
    Insertable<CropPlot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmIdMeta);
    }
    if (data.containsKey('crop_id')) {
      context.handle(
        _cropIdMeta,
        cropId.isAcceptableOrUnknown(data['crop_id']!, _cropIdMeta),
      );
    }
    if (data.containsKey('variety')) {
      context.handle(
        _varietyMeta,
        variety.isAcceptableOrUnknown(data['variety']!, _varietyMeta),
      );
    }
    if (data.containsKey('season')) {
      context.handle(
        _seasonMeta,
        season.isAcceptableOrUnknown(data['season']!, _seasonMeta),
      );
    }
    if (data.containsKey('sowing_date')) {
      context.handle(
        _sowingDateMeta,
        sowingDate.isAcceptableOrUnknown(data['sowing_date']!, _sowingDateMeta),
      );
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    }
    if (data.containsKey('area_acres')) {
      context.handle(
        _areaAcresMeta,
        areaAcres.isAcceptableOrUnknown(data['area_acres']!, _areaAcresMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CropPlot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CropPlot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      )!,
      cropId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop_id'],
      ),
      variety: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variety'],
      ),
      season: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}season'],
      ),
      sowingDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sowing_date'],
      ),
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      ),
      areaAcres: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}area_acres'],
      ),
    );
  }

  @override
  $CropPlotsTable createAlias(String alias) {
    return $CropPlotsTable(attachedDatabase, alias);
  }
}

class CropPlot extends DataClass implements Insertable<CropPlot> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Owning farm.
  final String farmId;

  /// Crop id (reference data in `synced_refs`).
  final String? cropId;

  /// Variety as entered.
  final String? variety;

  /// `kharif` | `rabi` | `summer`.
  final String? season;

  /// ISO-8601 date.
  final String? sowingDate;

  /// Growth stage.
  final String? stage;

  /// Area in acres.
  final double? areaAcres;
  const CropPlot({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    required this.farmId,
    this.cropId,
    this.variety,
    this.season,
    this.sowingDate,
    this.stage,
    this.areaAcres,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['farm_id'] = Variable<String>(farmId);
    if (!nullToAbsent || cropId != null) {
      map['crop_id'] = Variable<String>(cropId);
    }
    if (!nullToAbsent || variety != null) {
      map['variety'] = Variable<String>(variety);
    }
    if (!nullToAbsent || season != null) {
      map['season'] = Variable<String>(season);
    }
    if (!nullToAbsent || sowingDate != null) {
      map['sowing_date'] = Variable<String>(sowingDate);
    }
    if (!nullToAbsent || stage != null) {
      map['stage'] = Variable<String>(stage);
    }
    if (!nullToAbsent || areaAcres != null) {
      map['area_acres'] = Variable<double>(areaAcres);
    }
    return map;
  }

  CropPlotsCompanion toCompanion(bool nullToAbsent) {
    return CropPlotsCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      farmId: Value(farmId),
      cropId: cropId == null && nullToAbsent
          ? const Value.absent()
          : Value(cropId),
      variety: variety == null && nullToAbsent
          ? const Value.absent()
          : Value(variety),
      season: season == null && nullToAbsent
          ? const Value.absent()
          : Value(season),
      sowingDate: sowingDate == null && nullToAbsent
          ? const Value.absent()
          : Value(sowingDate),
      stage: stage == null && nullToAbsent
          ? const Value.absent()
          : Value(stage),
      areaAcres: areaAcres == null && nullToAbsent
          ? const Value.absent()
          : Value(areaAcres),
    );
  }

  factory CropPlot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CropPlot(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      farmId: serializer.fromJson<String>(json['farmId']),
      cropId: serializer.fromJson<String?>(json['cropId']),
      variety: serializer.fromJson<String?>(json['variety']),
      season: serializer.fromJson<String?>(json['season']),
      sowingDate: serializer.fromJson<String?>(json['sowingDate']),
      stage: serializer.fromJson<String?>(json['stage']),
      areaAcres: serializer.fromJson<double?>(json['areaAcres']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'farmId': serializer.toJson<String>(farmId),
      'cropId': serializer.toJson<String?>(cropId),
      'variety': serializer.toJson<String?>(variety),
      'season': serializer.toJson<String?>(season),
      'sowingDate': serializer.toJson<String?>(sowingDate),
      'stage': serializer.toJson<String?>(stage),
      'areaAcres': serializer.toJson<double?>(areaAcres),
    };
  }

  CropPlot copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    String? farmId,
    Value<String?> cropId = const Value.absent(),
    Value<String?> variety = const Value.absent(),
    Value<String?> season = const Value.absent(),
    Value<String?> sowingDate = const Value.absent(),
    Value<String?> stage = const Value.absent(),
    Value<double?> areaAcres = const Value.absent(),
  }) => CropPlot(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    farmId: farmId ?? this.farmId,
    cropId: cropId.present ? cropId.value : this.cropId,
    variety: variety.present ? variety.value : this.variety,
    season: season.present ? season.value : this.season,
    sowingDate: sowingDate.present ? sowingDate.value : this.sowingDate,
    stage: stage.present ? stage.value : this.stage,
    areaAcres: areaAcres.present ? areaAcres.value : this.areaAcres,
  );
  CropPlot copyWithCompanion(CropPlotsCompanion data) {
    return CropPlot(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      cropId: data.cropId.present ? data.cropId.value : this.cropId,
      variety: data.variety.present ? data.variety.value : this.variety,
      season: data.season.present ? data.season.value : this.season,
      sowingDate: data.sowingDate.present
          ? data.sowingDate.value
          : this.sowingDate,
      stage: data.stage.present ? data.stage.value : this.stage,
      areaAcres: data.areaAcres.present ? data.areaAcres.value : this.areaAcres,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CropPlot(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmId: $farmId, ')
          ..write('cropId: $cropId, ')
          ..write('variety: $variety, ')
          ..write('season: $season, ')
          ..write('sowingDate: $sowingDate, ')
          ..write('stage: $stage, ')
          ..write('areaAcres: $areaAcres')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmId,
    cropId,
    variety,
    season,
    sowingDate,
    stage,
    areaAcres,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CropPlot &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.farmId == this.farmId &&
          other.cropId == this.cropId &&
          other.variety == this.variety &&
          other.season == this.season &&
          other.sowingDate == this.sowingDate &&
          other.stage == this.stage &&
          other.areaAcres == this.areaAcres);
}

class CropPlotsCompanion extends UpdateCompanion<CropPlot> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String> farmId;
  final Value<String?> cropId;
  final Value<String?> variety;
  final Value<String?> season;
  final Value<String?> sowingDate;
  final Value<String?> stage;
  final Value<double?> areaAcres;
  final Value<int> rowid;
  const CropPlotsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.farmId = const Value.absent(),
    this.cropId = const Value.absent(),
    this.variety = const Value.absent(),
    this.season = const Value.absent(),
    this.sowingDate = const Value.absent(),
    this.stage = const Value.absent(),
    this.areaAcres = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CropPlotsCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required String farmId,
    this.cropId = const Value.absent(),
    this.variety = const Value.absent(),
    this.season = const Value.absent(),
    this.sowingDate = const Value.absent(),
    this.stage = const Value.absent(),
    this.areaAcres = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       farmId = Value(farmId);
  static Insertable<CropPlot> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? farmId,
    Expression<String>? cropId,
    Expression<String>? variety,
    Expression<String>? season,
    Expression<String>? sowingDate,
    Expression<String>? stage,
    Expression<double>? areaAcres,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (farmId != null) 'farm_id': farmId,
      if (cropId != null) 'crop_id': cropId,
      if (variety != null) 'variety': variety,
      if (season != null) 'season': season,
      if (sowingDate != null) 'sowing_date': sowingDate,
      if (stage != null) 'stage': stage,
      if (areaAcres != null) 'area_acres': areaAcres,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CropPlotsCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String>? farmId,
    Value<String?>? cropId,
    Value<String?>? variety,
    Value<String?>? season,
    Value<String?>? sowingDate,
    Value<String?>? stage,
    Value<double?>? areaAcres,
    Value<int>? rowid,
  }) {
    return CropPlotsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      farmId: farmId ?? this.farmId,
      cropId: cropId ?? this.cropId,
      variety: variety ?? this.variety,
      season: season ?? this.season,
      sowingDate: sowingDate ?? this.sowingDate,
      stage: stage ?? this.stage,
      areaAcres: areaAcres ?? this.areaAcres,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (cropId.present) {
      map['crop_id'] = Variable<String>(cropId.value);
    }
    if (variety.present) {
      map['variety'] = Variable<String>(variety.value);
    }
    if (season.present) {
      map['season'] = Variable<String>(season.value);
    }
    if (sowingDate.present) {
      map['sowing_date'] = Variable<String>(sowingDate.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (areaAcres.present) {
      map['area_acres'] = Variable<double>(areaAcres.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CropPlotsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmId: $farmId, ')
          ..write('cropId: $cropId, ')
          ..write('variety: $variety, ')
          ..write('season: $season, ')
          ..write('sowingDate: $sowingDate, ')
          ..write('stage: $stage, ')
          ..write('areaAcres: $areaAcres, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConsentRecordsTable extends ConsentRecords
    with TableInfo<$ConsentRecordsTable, ConsentRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConsentRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _farmerIdMeta = const VerificationMeta(
    'farmerId',
  );
  @override
  late final GeneratedColumn<String> farmerId = GeneratedColumn<String>(
    'farmer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _purposeMeta = const VerificationMeta(
    'purpose',
  );
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
    'purpose',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grantedMeta = const VerificationMeta(
    'granted',
  );
  @override
  late final GeneratedColumn<bool> granted = GeneratedColumn<bool>(
    'granted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("granted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _consentVersionMeta = const VerificationMeta(
    'consentVersion',
  );
  @override
  late final GeneratedColumn<String> consentVersion = GeneratedColumn<String>(
    'consent_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    purpose,
    granted,
    consentVersion,
    channel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'consent_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConsentRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('farmer_id')) {
      context.handle(
        _farmerIdMeta,
        farmerId.isAcceptableOrUnknown(data['farmer_id']!, _farmerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmerIdMeta);
    }
    if (data.containsKey('purpose')) {
      context.handle(
        _purposeMeta,
        purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta),
      );
    } else if (isInserting) {
      context.missing(_purposeMeta);
    }
    if (data.containsKey('granted')) {
      context.handle(
        _grantedMeta,
        granted.isAcceptableOrUnknown(data['granted']!, _grantedMeta),
      );
    }
    if (data.containsKey('consent_version')) {
      context.handle(
        _consentVersionMeta,
        consentVersion.isAcceptableOrUnknown(
          data['consent_version']!,
          _consentVersionMeta,
        ),
      );
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConsentRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConsentRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      farmerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farmer_id'],
      )!,
      purpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purpose'],
      )!,
      granted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}granted'],
      )!,
      consentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consent_version'],
      ),
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      ),
    );
  }

  @override
  $ConsentRecordsTable createAlias(String alias) {
    return $ConsentRecordsTable(attachedDatabase, alias);
  }
}

class ConsentRecord extends DataClass implements Insertable<ConsentRecord> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Subject farmer.
  final String farmerId;

  /// `data` | `marketing`.
  final String purpose;

  /// Granted or withdrawn.
  final bool granted;

  /// Consent text version (e.g. `2026-09-v1`), distinct from the row version.
  final String? consentVersion;

  /// Channel the consent was taken on.
  final String? channel;
  const ConsentRecord({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    required this.farmerId,
    required this.purpose,
    required this.granted,
    this.consentVersion,
    this.channel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['farmer_id'] = Variable<String>(farmerId);
    map['purpose'] = Variable<String>(purpose);
    map['granted'] = Variable<bool>(granted);
    if (!nullToAbsent || consentVersion != null) {
      map['consent_version'] = Variable<String>(consentVersion);
    }
    if (!nullToAbsent || channel != null) {
      map['channel'] = Variable<String>(channel);
    }
    return map;
  }

  ConsentRecordsCompanion toCompanion(bool nullToAbsent) {
    return ConsentRecordsCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      farmerId: Value(farmerId),
      purpose: Value(purpose),
      granted: Value(granted),
      consentVersion: consentVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(consentVersion),
      channel: channel == null && nullToAbsent
          ? const Value.absent()
          : Value(channel),
    );
  }

  factory ConsentRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConsentRecord(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      farmerId: serializer.fromJson<String>(json['farmerId']),
      purpose: serializer.fromJson<String>(json['purpose']),
      granted: serializer.fromJson<bool>(json['granted']),
      consentVersion: serializer.fromJson<String?>(json['consentVersion']),
      channel: serializer.fromJson<String?>(json['channel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'farmerId': serializer.toJson<String>(farmerId),
      'purpose': serializer.toJson<String>(purpose),
      'granted': serializer.toJson<bool>(granted),
      'consentVersion': serializer.toJson<String?>(consentVersion),
      'channel': serializer.toJson<String?>(channel),
    };
  }

  ConsentRecord copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    String? farmerId,
    String? purpose,
    bool? granted,
    Value<String?> consentVersion = const Value.absent(),
    Value<String?> channel = const Value.absent(),
  }) => ConsentRecord(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    farmerId: farmerId ?? this.farmerId,
    purpose: purpose ?? this.purpose,
    granted: granted ?? this.granted,
    consentVersion: consentVersion.present
        ? consentVersion.value
        : this.consentVersion,
    channel: channel.present ? channel.value : this.channel,
  );
  ConsentRecord copyWithCompanion(ConsentRecordsCompanion data) {
    return ConsentRecord(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      farmerId: data.farmerId.present ? data.farmerId.value : this.farmerId,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      granted: data.granted.present ? data.granted.value : this.granted,
      consentVersion: data.consentVersion.present
          ? data.consentVersion.value
          : this.consentVersion,
      channel: data.channel.present ? data.channel.value : this.channel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConsentRecord(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('purpose: $purpose, ')
          ..write('granted: $granted, ')
          ..write('consentVersion: $consentVersion, ')
          ..write('channel: $channel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    purpose,
    granted,
    consentVersion,
    channel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsentRecord &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.farmerId == this.farmerId &&
          other.purpose == this.purpose &&
          other.granted == this.granted &&
          other.consentVersion == this.consentVersion &&
          other.channel == this.channel);
}

class ConsentRecordsCompanion extends UpdateCompanion<ConsentRecord> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String> farmerId;
  final Value<String> purpose;
  final Value<bool> granted;
  final Value<String?> consentVersion;
  final Value<String?> channel;
  final Value<int> rowid;
  const ConsentRecordsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.farmerId = const Value.absent(),
    this.purpose = const Value.absent(),
    this.granted = const Value.absent(),
    this.consentVersion = const Value.absent(),
    this.channel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConsentRecordsCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required String farmerId,
    required String purpose,
    this.granted = const Value.absent(),
    this.consentVersion = const Value.absent(),
    this.channel = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       farmerId = Value(farmerId),
       purpose = Value(purpose);
  static Insertable<ConsentRecord> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? farmerId,
    Expression<String>? purpose,
    Expression<bool>? granted,
    Expression<String>? consentVersion,
    Expression<String>? channel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (farmerId != null) 'farmer_id': farmerId,
      if (purpose != null) 'purpose': purpose,
      if (granted != null) 'granted': granted,
      if (consentVersion != null) 'consent_version': consentVersion,
      if (channel != null) 'channel': channel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConsentRecordsCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String>? farmerId,
    Value<String>? purpose,
    Value<bool>? granted,
    Value<String?>? consentVersion,
    Value<String?>? channel,
    Value<int>? rowid,
  }) {
    return ConsentRecordsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      farmerId: farmerId ?? this.farmerId,
      purpose: purpose ?? this.purpose,
      granted: granted ?? this.granted,
      consentVersion: consentVersion ?? this.consentVersion,
      channel: channel ?? this.channel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (farmerId.present) {
      map['farmer_id'] = Variable<String>(farmerId.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (granted.present) {
      map['granted'] = Variable<bool>(granted.value);
    }
    if (consentVersion.present) {
      map['consent_version'] = Variable<String>(consentVersion.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConsentRecordsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('purpose: $purpose, ')
          ..write('granted: $granted, ')
          ..write('consentVersion: $consentVersion, ')
          ..write('channel: $channel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTableTable extends OutboxTable
    with TableInfo<$OutboxTableTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _opIdMeta = const VerificationMeta('opId');
  @override
  late final GeneratedColumn<String> opId = GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
    'base_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientTsMeta = const VerificationMeta(
    'clientTs',
  );
  @override
  late final GeneratedColumn<String> clientTs = GeneratedColumn<String>(
    'client_ts',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _dependsOnUploadIdMeta = const VerificationMeta(
    'dependsOnUploadId',
  );
  @override
  late final GeneratedColumn<String> dependsOnUploadId =
      GeneratedColumn<String>(
        'depends_on_upload_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    opId,
    seq,
    entity,
    action,
    entityId,
    baseVersion,
    payload,
    clientTs,
    state,
    attempts,
    lastError,
    nextAttemptAt,
    dependsOnUploadId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('client_ts')) {
      context.handle(
        _clientTsMeta,
        clientTs.isAcceptableOrUnknown(data['client_ts']!, _clientTsMeta),
      );
    } else if (isInserting) {
      context.missing(_clientTsMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('depends_on_upload_id')) {
      context.handle(
        _dependsOnUploadIdMeta,
        dependsOnUploadId.isAcceptableOrUnknown(
          data['depends_on_upload_id']!,
          _dependsOnUploadIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {opId};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      opId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_version'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      clientTs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_ts'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      dependsOnUploadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}depends_on_upload_id'],
      ),
    );
  }

  @override
  $OutboxTableTable createAlias(String alias) {
    return $OutboxTableTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  /// Idempotency key (uuid), generated when the op is queued.
  final String opId;

  /// Local insertion order; the push order.
  final int seq;

  /// `farmer` | `farm` | `crop_plot` | `consent_record`.
  final String entity;

  /// `create` | `update` | `delete`.
  final String action;

  /// The row this op targets.
  final String entityId;

  /// Server version the op was based on (0 for create).
  final int baseVersion;

  /// JSON payload.
  final String payload;

  /// ISO-8601 UTC time the op was queued.
  final String clientTs;

  /// queued | sending | applied | duplicate | conflict | rejected.
  final String state;

  /// Push attempts so far.
  final int attempts;

  /// JSON `{code, detail}` of the last error.
  final String? lastError;

  /// Earliest next push (UTC); null = as soon as possible.
  final DateTime? nextAttemptAt;

  /// Local upload row this op waits for (photo `blob_uri`).
  final String? dependsOnUploadId;
  const OutboxRow({
    required this.opId,
    required this.seq,
    required this.entity,
    required this.action,
    required this.entityId,
    required this.baseVersion,
    required this.payload,
    required this.clientTs,
    required this.state,
    required this.attempts,
    this.lastError,
    this.nextAttemptAt,
    this.dependsOnUploadId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['op_id'] = Variable<String>(opId);
    map['seq'] = Variable<int>(seq);
    map['entity'] = Variable<String>(entity);
    map['action'] = Variable<String>(action);
    map['entity_id'] = Variable<String>(entityId);
    map['base_version'] = Variable<int>(baseVersion);
    map['payload'] = Variable<String>(payload);
    map['client_ts'] = Variable<String>(clientTs);
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || dependsOnUploadId != null) {
      map['depends_on_upload_id'] = Variable<String>(dependsOnUploadId);
    }
    return map;
  }

  OutboxTableCompanion toCompanion(bool nullToAbsent) {
    return OutboxTableCompanion(
      opId: Value(opId),
      seq: Value(seq),
      entity: Value(entity),
      action: Value(action),
      entityId: Value(entityId),
      baseVersion: Value(baseVersion),
      payload: Value(payload),
      clientTs: Value(clientTs),
      state: Value(state),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      dependsOnUploadId: dependsOnUploadId == null && nullToAbsent
          ? const Value.absent()
          : Value(dependsOnUploadId),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      opId: serializer.fromJson<String>(json['opId']),
      seq: serializer.fromJson<int>(json['seq']),
      entity: serializer.fromJson<String>(json['entity']),
      action: serializer.fromJson<String>(json['action']),
      entityId: serializer.fromJson<String>(json['entityId']),
      baseVersion: serializer.fromJson<int>(json['baseVersion']),
      payload: serializer.fromJson<String>(json['payload']),
      clientTs: serializer.fromJson<String>(json['clientTs']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      dependsOnUploadId: serializer.fromJson<String?>(
        json['dependsOnUploadId'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'opId': serializer.toJson<String>(opId),
      'seq': serializer.toJson<int>(seq),
      'entity': serializer.toJson<String>(entity),
      'action': serializer.toJson<String>(action),
      'entityId': serializer.toJson<String>(entityId),
      'baseVersion': serializer.toJson<int>(baseVersion),
      'payload': serializer.toJson<String>(payload),
      'clientTs': serializer.toJson<String>(clientTs),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'dependsOnUploadId': serializer.toJson<String?>(dependsOnUploadId),
    };
  }

  OutboxRow copyWith({
    String? opId,
    int? seq,
    String? entity,
    String? action,
    String? entityId,
    int? baseVersion,
    String? payload,
    String? clientTs,
    String? state,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> dependsOnUploadId = const Value.absent(),
  }) => OutboxRow(
    opId: opId ?? this.opId,
    seq: seq ?? this.seq,
    entity: entity ?? this.entity,
    action: action ?? this.action,
    entityId: entityId ?? this.entityId,
    baseVersion: baseVersion ?? this.baseVersion,
    payload: payload ?? this.payload,
    clientTs: clientTs ?? this.clientTs,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    dependsOnUploadId: dependsOnUploadId.present
        ? dependsOnUploadId.value
        : this.dependsOnUploadId,
  );
  OutboxRow copyWithCompanion(OutboxTableCompanion data) {
    return OutboxRow(
      opId: data.opId.present ? data.opId.value : this.opId,
      seq: data.seq.present ? data.seq.value : this.seq,
      entity: data.entity.present ? data.entity.value : this.entity,
      action: data.action.present ? data.action.value : this.action,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      payload: data.payload.present ? data.payload.value : this.payload,
      clientTs: data.clientTs.present ? data.clientTs.value : this.clientTs,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      dependsOnUploadId: data.dependsOnUploadId.present
          ? data.dependsOnUploadId.value
          : this.dependsOnUploadId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('opId: $opId, ')
          ..write('seq: $seq, ')
          ..write('entity: $entity, ')
          ..write('action: $action, ')
          ..write('entityId: $entityId, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('payload: $payload, ')
          ..write('clientTs: $clientTs, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('dependsOnUploadId: $dependsOnUploadId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    opId,
    seq,
    entity,
    action,
    entityId,
    baseVersion,
    payload,
    clientTs,
    state,
    attempts,
    lastError,
    nextAttemptAt,
    dependsOnUploadId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.opId == this.opId &&
          other.seq == this.seq &&
          other.entity == this.entity &&
          other.action == this.action &&
          other.entityId == this.entityId &&
          other.baseVersion == this.baseVersion &&
          other.payload == this.payload &&
          other.clientTs == this.clientTs &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.dependsOnUploadId == this.dependsOnUploadId);
}

class OutboxTableCompanion extends UpdateCompanion<OutboxRow> {
  final Value<String> opId;
  final Value<int> seq;
  final Value<String> entity;
  final Value<String> action;
  final Value<String> entityId;
  final Value<int> baseVersion;
  final Value<String> payload;
  final Value<String> clientTs;
  final Value<String> state;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> dependsOnUploadId;
  final Value<int> rowid;
  const OutboxTableCompanion({
    this.opId = const Value.absent(),
    this.seq = const Value.absent(),
    this.entity = const Value.absent(),
    this.action = const Value.absent(),
    this.entityId = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.payload = const Value.absent(),
    this.clientTs = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.dependsOnUploadId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxTableCompanion.insert({
    required String opId,
    required int seq,
    required String entity,
    required String action,
    required String entityId,
    this.baseVersion = const Value.absent(),
    required String payload,
    required String clientTs,
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.dependsOnUploadId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : opId = Value(opId),
       seq = Value(seq),
       entity = Value(entity),
       action = Value(action),
       entityId = Value(entityId),
       payload = Value(payload),
       clientTs = Value(clientTs);
  static Insertable<OutboxRow> custom({
    Expression<String>? opId,
    Expression<int>? seq,
    Expression<String>? entity,
    Expression<String>? action,
    Expression<String>? entityId,
    Expression<int>? baseVersion,
    Expression<String>? payload,
    Expression<String>? clientTs,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? dependsOnUploadId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (seq != null) 'seq': seq,
      if (entity != null) 'entity': entity,
      if (action != null) 'action': action,
      if (entityId != null) 'entity_id': entityId,
      if (baseVersion != null) 'base_version': baseVersion,
      if (payload != null) 'payload': payload,
      if (clientTs != null) 'client_ts': clientTs,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (dependsOnUploadId != null) 'depends_on_upload_id': dependsOnUploadId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxTableCompanion copyWith({
    Value<String>? opId,
    Value<int>? seq,
    Value<String>? entity,
    Value<String>? action,
    Value<String>? entityId,
    Value<int>? baseVersion,
    Value<String>? payload,
    Value<String>? clientTs,
    Value<String>? state,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? dependsOnUploadId,
    Value<int>? rowid,
  }) {
    return OutboxTableCompanion(
      opId: opId ?? this.opId,
      seq: seq ?? this.seq,
      entity: entity ?? this.entity,
      action: action ?? this.action,
      entityId: entityId ?? this.entityId,
      baseVersion: baseVersion ?? this.baseVersion,
      payload: payload ?? this.payload,
      clientTs: clientTs ?? this.clientTs,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      dependsOnUploadId: dependsOnUploadId ?? this.dependsOnUploadId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (opId.present) {
      map['op_id'] = Variable<String>(opId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (clientTs.present) {
      map['client_ts'] = Variable<String>(clientTs.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (dependsOnUploadId.present) {
      map['depends_on_upload_id'] = Variable<String>(dependsOnUploadId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxTableCompanion(')
          ..write('opId: $opId, ')
          ..write('seq: $seq, ')
          ..write('entity: $entity, ')
          ..write('action: $action, ')
          ..write('entityId: $entityId, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('payload: $payload, ')
          ..write('clientTs: $clientTs, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('dependsOnUploadId: $dependsOnUploadId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadsTable extends Uploads with TableInfo<$UploadsTable, Upload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadIdMeta = const VerificationMeta(
    'uploadId',
  );
  @override
  late final GeneratedColumn<String> uploadId = GeneratedColumn<String>(
    'upload_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chunkSizeMeta = const VerificationMeta(
    'chunkSize',
  );
  @override
  late final GeneratedColumn<int> chunkSize = GeneratedColumn<int>(
    'chunk_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedChunksMeta = const VerificationMeta(
    'receivedChunks',
  );
  @override
  late final GeneratedColumn<String> receivedChunks = GeneratedColumn<String>(
    'received_chunks',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _blobUriMeta = const VerificationMeta(
    'blobUri',
  );
  @override
  late final GeneratedColumn<String> blobUri = GeneratedColumn<String>(
    'blob_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purposeMeta = const VerificationMeta(
    'purpose',
  );
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
    'purpose',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('image/jpeg'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uploadId,
    filePath,
    sha256,
    sizeBytes,
    chunkSize,
    receivedChunks,
    state,
    blobUri,
    purpose,
    contentType,
    attempts,
    lastError,
    expiresAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<Upload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('upload_id')) {
      context.handle(
        _uploadIdMeta,
        uploadId.isAcceptableOrUnknown(data['upload_id']!, _uploadIdMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('chunk_size')) {
      context.handle(
        _chunkSizeMeta,
        chunkSize.isAcceptableOrUnknown(data['chunk_size']!, _chunkSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_chunkSizeMeta);
    }
    if (data.containsKey('received_chunks')) {
      context.handle(
        _receivedChunksMeta,
        receivedChunks.isAcceptableOrUnknown(
          data['received_chunks']!,
          _receivedChunksMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('blob_uri')) {
      context.handle(
        _blobUriMeta,
        blobUri.isAcceptableOrUnknown(data['blob_uri']!, _blobUriMeta),
      );
    }
    if (data.containsKey('purpose')) {
      context.handle(
        _purposeMeta,
        purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta),
      );
    } else if (isInserting) {
      context.missing(_purposeMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Upload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Upload(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      uploadId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}upload_id'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      chunkSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_size'],
      )!,
      receivedChunks: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}received_chunks'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      blobUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blob_uri'],
      ),
      purpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purpose'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $UploadsTable createAlias(String alias) {
    return $UploadsTable(attachedDatabase, alias);
  }
}

class Upload extends DataClass implements Insertable<Upload> {
  /// Local id, referenced by outbox payloads as `upload:<id>`.
  final String id;

  /// Server upload id; null until `POST /v1/uploads` succeeds.
  final String? uploadId;

  /// Local file path of the processed photo.
  final String filePath;

  /// Hex SHA-256 of the whole file.
  final String sha256;

  /// File size.
  final int sizeBytes;

  /// Chunk size negotiated with the server.
  final int chunkSize;

  /// JSON list of acknowledged chunk indexes.
  final String receivedChunks;

  /// pending | uploading | complete | failed.
  final String state;

  /// Server blob URI once complete.
  final String? blobUri;

  /// e.g. `farm_photo`, `visit_photo`.
  final String purpose;

  /// MIME type.
  final String contentType;

  /// Attempts so far.
  final int attempts;

  /// JSON `{code, detail}` of the last error.
  final String? lastError;

  /// Server-side expiry of the upload session.
  final DateTime? expiresAt;

  /// When the upload was queued (UTC).
  final DateTime createdAt;
  const Upload({
    required this.id,
    this.uploadId,
    required this.filePath,
    required this.sha256,
    required this.sizeBytes,
    required this.chunkSize,
    required this.receivedChunks,
    required this.state,
    this.blobUri,
    required this.purpose,
    required this.contentType,
    required this.attempts,
    this.lastError,
    this.expiresAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || uploadId != null) {
      map['upload_id'] = Variable<String>(uploadId);
    }
    map['file_path'] = Variable<String>(filePath);
    map['sha256'] = Variable<String>(sha256);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['chunk_size'] = Variable<int>(chunkSize);
    map['received_chunks'] = Variable<String>(receivedChunks);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || blobUri != null) {
      map['blob_uri'] = Variable<String>(blobUri);
    }
    map['purpose'] = Variable<String>(purpose);
    map['content_type'] = Variable<String>(contentType);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  UploadsCompanion toCompanion(bool nullToAbsent) {
    return UploadsCompanion(
      id: Value(id),
      uploadId: uploadId == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadId),
      filePath: Value(filePath),
      sha256: Value(sha256),
      sizeBytes: Value(sizeBytes),
      chunkSize: Value(chunkSize),
      receivedChunks: Value(receivedChunks),
      state: Value(state),
      blobUri: blobUri == null && nullToAbsent
          ? const Value.absent()
          : Value(blobUri),
      purpose: Value(purpose),
      contentType: Value(contentType),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      createdAt: Value(createdAt),
    );
  }

  factory Upload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Upload(
      id: serializer.fromJson<String>(json['id']),
      uploadId: serializer.fromJson<String?>(json['uploadId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      sha256: serializer.fromJson<String>(json['sha256']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      chunkSize: serializer.fromJson<int>(json['chunkSize']),
      receivedChunks: serializer.fromJson<String>(json['receivedChunks']),
      state: serializer.fromJson<String>(json['state']),
      blobUri: serializer.fromJson<String?>(json['blobUri']),
      purpose: serializer.fromJson<String>(json['purpose']),
      contentType: serializer.fromJson<String>(json['contentType']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'uploadId': serializer.toJson<String?>(uploadId),
      'filePath': serializer.toJson<String>(filePath),
      'sha256': serializer.toJson<String>(sha256),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'chunkSize': serializer.toJson<int>(chunkSize),
      'receivedChunks': serializer.toJson<String>(receivedChunks),
      'state': serializer.toJson<String>(state),
      'blobUri': serializer.toJson<String?>(blobUri),
      'purpose': serializer.toJson<String>(purpose),
      'contentType': serializer.toJson<String>(contentType),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Upload copyWith({
    String? id,
    Value<String?> uploadId = const Value.absent(),
    String? filePath,
    String? sha256,
    int? sizeBytes,
    int? chunkSize,
    String? receivedChunks,
    String? state,
    Value<String?> blobUri = const Value.absent(),
    String? purpose,
    String? contentType,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    DateTime? createdAt,
  }) => Upload(
    id: id ?? this.id,
    uploadId: uploadId.present ? uploadId.value : this.uploadId,
    filePath: filePath ?? this.filePath,
    sha256: sha256 ?? this.sha256,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    chunkSize: chunkSize ?? this.chunkSize,
    receivedChunks: receivedChunks ?? this.receivedChunks,
    state: state ?? this.state,
    blobUri: blobUri.present ? blobUri.value : this.blobUri,
    purpose: purpose ?? this.purpose,
    contentType: contentType ?? this.contentType,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    createdAt: createdAt ?? this.createdAt,
  );
  Upload copyWithCompanion(UploadsCompanion data) {
    return Upload(
      id: data.id.present ? data.id.value : this.id,
      uploadId: data.uploadId.present ? data.uploadId.value : this.uploadId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      chunkSize: data.chunkSize.present ? data.chunkSize.value : this.chunkSize,
      receivedChunks: data.receivedChunks.present
          ? data.receivedChunks.value
          : this.receivedChunks,
      state: data.state.present ? data.state.value : this.state,
      blobUri: data.blobUri.present ? data.blobUri.value : this.blobUri,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Upload(')
          ..write('id: $id, ')
          ..write('uploadId: $uploadId, ')
          ..write('filePath: $filePath, ')
          ..write('sha256: $sha256, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('chunkSize: $chunkSize, ')
          ..write('receivedChunks: $receivedChunks, ')
          ..write('state: $state, ')
          ..write('blobUri: $blobUri, ')
          ..write('purpose: $purpose, ')
          ..write('contentType: $contentType, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uploadId,
    filePath,
    sha256,
    sizeBytes,
    chunkSize,
    receivedChunks,
    state,
    blobUri,
    purpose,
    contentType,
    attempts,
    lastError,
    expiresAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Upload &&
          other.id == this.id &&
          other.uploadId == this.uploadId &&
          other.filePath == this.filePath &&
          other.sha256 == this.sha256 &&
          other.sizeBytes == this.sizeBytes &&
          other.chunkSize == this.chunkSize &&
          other.receivedChunks == this.receivedChunks &&
          other.state == this.state &&
          other.blobUri == this.blobUri &&
          other.purpose == this.purpose &&
          other.contentType == this.contentType &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.expiresAt == this.expiresAt &&
          other.createdAt == this.createdAt);
}

class UploadsCompanion extends UpdateCompanion<Upload> {
  final Value<String> id;
  final Value<String?> uploadId;
  final Value<String> filePath;
  final Value<String> sha256;
  final Value<int> sizeBytes;
  final Value<int> chunkSize;
  final Value<String> receivedChunks;
  final Value<String> state;
  final Value<String?> blobUri;
  final Value<String> purpose;
  final Value<String> contentType;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<DateTime?> expiresAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const UploadsCompanion({
    this.id = const Value.absent(),
    this.uploadId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.chunkSize = const Value.absent(),
    this.receivedChunks = const Value.absent(),
    this.state = const Value.absent(),
    this.blobUri = const Value.absent(),
    this.purpose = const Value.absent(),
    this.contentType = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UploadsCompanion.insert({
    required String id,
    this.uploadId = const Value.absent(),
    required String filePath,
    required String sha256,
    required int sizeBytes,
    required int chunkSize,
    this.receivedChunks = const Value.absent(),
    this.state = const Value.absent(),
    this.blobUri = const Value.absent(),
    required String purpose,
    this.contentType = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.expiresAt = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       filePath = Value(filePath),
       sha256 = Value(sha256),
       sizeBytes = Value(sizeBytes),
       chunkSize = Value(chunkSize),
       purpose = Value(purpose),
       createdAt = Value(createdAt);
  static Insertable<Upload> custom({
    Expression<String>? id,
    Expression<String>? uploadId,
    Expression<String>? filePath,
    Expression<String>? sha256,
    Expression<int>? sizeBytes,
    Expression<int>? chunkSize,
    Expression<String>? receivedChunks,
    Expression<String>? state,
    Expression<String>? blobUri,
    Expression<String>? purpose,
    Expression<String>? contentType,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uploadId != null) 'upload_id': uploadId,
      if (filePath != null) 'file_path': filePath,
      if (sha256 != null) 'sha256': sha256,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (chunkSize != null) 'chunk_size': chunkSize,
      if (receivedChunks != null) 'received_chunks': receivedChunks,
      if (state != null) 'state': state,
      if (blobUri != null) 'blob_uri': blobUri,
      if (purpose != null) 'purpose': purpose,
      if (contentType != null) 'content_type': contentType,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UploadsCompanion copyWith({
    Value<String>? id,
    Value<String?>? uploadId,
    Value<String>? filePath,
    Value<String>? sha256,
    Value<int>? sizeBytes,
    Value<int>? chunkSize,
    Value<String>? receivedChunks,
    Value<String>? state,
    Value<String?>? blobUri,
    Value<String>? purpose,
    Value<String>? contentType,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<DateTime?>? expiresAt,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return UploadsCompanion(
      id: id ?? this.id,
      uploadId: uploadId ?? this.uploadId,
      filePath: filePath ?? this.filePath,
      sha256: sha256 ?? this.sha256,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      chunkSize: chunkSize ?? this.chunkSize,
      receivedChunks: receivedChunks ?? this.receivedChunks,
      state: state ?? this.state,
      blobUri: blobUri ?? this.blobUri,
      purpose: purpose ?? this.purpose,
      contentType: contentType ?? this.contentType,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (uploadId.present) {
      map['upload_id'] = Variable<String>(uploadId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (chunkSize.present) {
      map['chunk_size'] = Variable<int>(chunkSize.value);
    }
    if (receivedChunks.present) {
      map['received_chunks'] = Variable<String>(receivedChunks.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (blobUri.present) {
      map['blob_uri'] = Variable<String>(blobUri.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadsCompanion(')
          ..write('id: $id, ')
          ..write('uploadId: $uploadId, ')
          ..write('filePath: $filePath, ')
          ..write('sha256: $sha256, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('chunkSize: $chunkSize, ')
          ..write('receivedChunks: $receivedChunks, ')
          ..write('state: $state, ')
          ..write('blobUri: $blobUri, ')
          ..write('purpose: $purpose, ')
          ..write('contentType: $contentType, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStatesTable extends SyncStates
    with TableInfo<$SyncStatesTable, SyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncAtMeta = const VerificationMeta(
    'lastSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAt = GeneratedColumn<DateTime>(
    'last_sync_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cursor,
    lastSyncAt,
    lastError,
    attempts,
    nextAttemptAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
        _lastSyncAtMeta,
        lastSyncAt.isAcceptableOrUnknown(
          data['last_sync_at']!,
          _lastSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      ),
      lastSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
    );
  }

  @override
  $SyncStatesTable createAlias(String alias) {
    return $SyncStatesTable(attachedDatabase, alias);
  }
}

class SyncStateRow extends DataClass implements Insertable<SyncStateRow> {
  /// Always 1.
  final int id;

  /// Pull cursor from the last `/v1/sync` response.
  final String? cursor;

  /// Last fully successful sync (UTC).
  final DateTime? lastSyncAt;

  /// JSON `{code, detail}` of the last transport failure.
  final String? lastError;

  /// Consecutive transport failures (drives the backoff).
  final int attempts;

  /// Earliest next automatic attempt (UTC) after a failure.
  final DateTime? nextAttemptAt;
  const SyncStateRow({
    required this.id,
    this.cursor,
    this.lastSyncAt,
    this.lastError,
    required this.attempts,
    this.nextAttemptAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || cursor != null) {
      map['cursor'] = Variable<String>(cursor);
    }
    if (!nullToAbsent || lastSyncAt != null) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    return map;
  }

  SyncStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncStatesCompanion(
      id: Value(id),
      cursor: cursor == null && nullToAbsent
          ? const Value.absent()
          : Value(cursor),
      lastSyncAt: lastSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
    );
  }

  factory SyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateRow(
      id: serializer.fromJson<int>(json['id']),
      cursor: serializer.fromJson<String?>(json['cursor']),
      lastSyncAt: serializer.fromJson<DateTime?>(json['lastSyncAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cursor': serializer.toJson<String?>(cursor),
      'lastSyncAt': serializer.toJson<DateTime?>(lastSyncAt),
      'lastError': serializer.toJson<String?>(lastError),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
    };
  }

  SyncStateRow copyWith({
    int? id,
    Value<String?> cursor = const Value.absent(),
    Value<DateTime?> lastSyncAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
  }) => SyncStateRow(
    id: id ?? this.id,
    cursor: cursor.present ? cursor.value : this.cursor,
    lastSyncAt: lastSyncAt.present ? lastSyncAt.value : this.lastSyncAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
  );
  SyncStateRow copyWithCompanion(SyncStatesCompanion data) {
    return SyncStateRow(
      id: data.id.present ? data.id.value : this.id,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      lastSyncAt: data.lastSyncAt.present
          ? data.lastSyncAt.value
          : this.lastSyncAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateRow(')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastError: $lastError, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, cursor, lastSyncAt, lastError, attempts, nextAttemptAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateRow &&
          other.id == this.id &&
          other.cursor == this.cursor &&
          other.lastSyncAt == this.lastSyncAt &&
          other.lastError == this.lastError &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt);
}

class SyncStatesCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<int> id;
  final Value<String?> cursor;
  final Value<DateTime?> lastSyncAt;
  final Value<String?> lastError;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  const SyncStatesCompanion({
    this.id = const Value.absent(),
    this.cursor = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    this.id = const Value.absent(),
    this.cursor = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
  });
  static Insertable<SyncStateRow> custom({
    Expression<int>? id,
    Expression<String>? cursor,
    Expression<DateTime>? lastSyncAt,
    Expression<String>? lastError,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cursor != null) 'cursor': cursor,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (lastError != null) 'last_error': lastError,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
    });
  }

  SyncStatesCompanion copyWith({
    Value<int>? id,
    Value<String?>? cursor,
    Value<DateTime?>? lastSyncAt,
    Value<String?>? lastError,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
  }) {
    return SyncStatesCompanion(
      id: id ?? this.id,
      cursor: cursor ?? this.cursor,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError ?? this.lastError,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<DateTime>(lastSyncAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStatesCompanion(')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('lastError: $lastError, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt')
          ..write(')'))
        .toString();
  }
}

class $SyncedRefsTable extends SyncedRefs
    with TableInfo<$SyncedRefsTable, SyncedRef> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncedRefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entity,
    refId,
    version,
    data,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'synced_refs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncedRef> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity, refId};
  @override
  SyncedRef map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncedRef(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncedRefsTable createAlias(String alias) {
    return $SyncedRefsTable(attachedDatabase, alias);
  }
}

class SyncedRef extends DataClass implements Insertable<SyncedRef> {
  /// Entity name as sent by the server.
  final String entity;

  /// Entity id.
  final String refId;

  /// Server version.
  final int version;

  /// JSON data.
  final String data;

  /// Last pull that touched the row (UTC).
  final DateTime updatedAt;
  const SyncedRef({
    required this.entity,
    required this.refId,
    required this.version,
    required this.data,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['ref_id'] = Variable<String>(refId);
    map['version'] = Variable<int>(version);
    map['data'] = Variable<String>(data);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncedRefsCompanion toCompanion(bool nullToAbsent) {
    return SyncedRefsCompanion(
      entity: Value(entity),
      refId: Value(refId),
      version: Value(version),
      data: Value(data),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncedRef.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncedRef(
      entity: serializer.fromJson<String>(json['entity']),
      refId: serializer.fromJson<String>(json['refId']),
      version: serializer.fromJson<int>(json['version']),
      data: serializer.fromJson<String>(json['data']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'refId': serializer.toJson<String>(refId),
      'version': serializer.toJson<int>(version),
      'data': serializer.toJson<String>(data),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncedRef copyWith({
    String? entity,
    String? refId,
    int? version,
    String? data,
    DateTime? updatedAt,
  }) => SyncedRef(
    entity: entity ?? this.entity,
    refId: refId ?? this.refId,
    version: version ?? this.version,
    data: data ?? this.data,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncedRef copyWithCompanion(SyncedRefsCompanion data) {
    return SyncedRef(
      entity: data.entity.present ? data.entity.value : this.entity,
      refId: data.refId.present ? data.refId.value : this.refId,
      version: data.version.present ? data.version.value : this.version,
      data: data.data.present ? data.data.value : this.data,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncedRef(')
          ..write('entity: $entity, ')
          ..write('refId: $refId, ')
          ..write('version: $version, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entity, refId, version, data, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncedRef &&
          other.entity == this.entity &&
          other.refId == this.refId &&
          other.version == this.version &&
          other.data == this.data &&
          other.updatedAt == this.updatedAt);
}

class SyncedRefsCompanion extends UpdateCompanion<SyncedRef> {
  final Value<String> entity;
  final Value<String> refId;
  final Value<int> version;
  final Value<String> data;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncedRefsCompanion({
    this.entity = const Value.absent(),
    this.refId = const Value.absent(),
    this.version = const Value.absent(),
    this.data = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncedRefsCompanion.insert({
    required String entity,
    required String refId,
    this.version = const Value.absent(),
    required String data,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : entity = Value(entity),
       refId = Value(refId),
       data = Value(data),
       updatedAt = Value(updatedAt);
  static Insertable<SyncedRef> custom({
    Expression<String>? entity,
    Expression<String>? refId,
    Expression<int>? version,
    Expression<String>? data,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (refId != null) 'ref_id': refId,
      if (version != null) 'version': version,
      if (data != null) 'data': data,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncedRefsCompanion copyWith({
    Value<String>? entity,
    Value<String>? refId,
    Value<int>? version,
    Value<String>? data,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncedRefsCompanion(
      entity: entity ?? this.entity,
      refId: refId ?? this.refId,
      version: version ?? this.version,
      data: data ?? this.data,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncedRefsCompanion(')
          ..write('entity: $entity, ')
          ..write('refId: $refId, ')
          ..write('version: $version, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VillagesTable extends Villages with TableInfo<$VillagesTable, Village> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VillagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _districtMeta = const VerificationMeta(
    'district',
  );
  @override
  late final GeneratedColumn<String> district = GeneratedColumn<String>(
    'district',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _mandalMeta = const VerificationMeta('mandal');
  @override
  late final GeneratedColumn<String> mandal = GeneratedColumn<String>(
    'mandal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meetingPointLatMeta = const VerificationMeta(
    'meetingPointLat',
  );
  @override
  late final GeneratedColumn<double> meetingPointLat = GeneratedColumn<double>(
    'meeting_point_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meetingPointLonMeta = const VerificationMeta(
    'meetingPointLon',
  );
  @override
  late final GeneratedColumn<double> meetingPointLon = GeneratedColumn<double>(
    'meeting_point_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _meetingPointRadiusMMeta =
      const VerificationMeta('meetingPointRadiusM');
  @override
  late final GeneratedColumn<double> meetingPointRadiusM =
      GeneratedColumn<double>(
        'meeting_point_radius_m',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    district,
    mandal,
    state,
    storeId,
    latitude,
    longitude,
    meetingPointLat,
    meetingPointLon,
    meetingPointRadiusM,
    version,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'villages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Village> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('district')) {
      context.handle(
        _districtMeta,
        district.isAcceptableOrUnknown(data['district']!, _districtMeta),
      );
    }
    if (data.containsKey('mandal')) {
      context.handle(
        _mandalMeta,
        mandal.isAcceptableOrUnknown(data['mandal']!, _mandalMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('meeting_point_lat')) {
      context.handle(
        _meetingPointLatMeta,
        meetingPointLat.isAcceptableOrUnknown(
          data['meeting_point_lat']!,
          _meetingPointLatMeta,
        ),
      );
    }
    if (data.containsKey('meeting_point_lon')) {
      context.handle(
        _meetingPointLonMeta,
        meetingPointLon.isAcceptableOrUnknown(
          data['meeting_point_lon']!,
          _meetingPointLonMeta,
        ),
      );
    }
    if (data.containsKey('meeting_point_radius_m')) {
      context.handle(
        _meetingPointRadiusMMeta,
        meetingPointRadiusM.isAcceptableOrUnknown(
          data['meeting_point_radius_m']!,
          _meetingPointRadiusMMeta,
        ),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Village map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Village(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      district: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}district'],
      )!,
      mandal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mandal'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      meetingPointLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}meeting_point_lat'],
      ),
      meetingPointLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}meeting_point_lon'],
      ),
      meetingPointRadiusM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}meeting_point_radius_m'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $VillagesTable createAlias(String alias) {
    return $VillagesTable(attachedDatabase, alias);
  }
}

class Village extends DataClass implements Insertable<Village> {
  /// Server id.
  final String id;

  /// Village name.
  final String name;

  /// District.
  final String district;

  /// Mandal / taluk.
  final String mandal;

  /// State.
  final String state;

  /// Nearest store, if assigned.
  final String? storeId;

  /// Village centre latitude.
  final double? latitude;

  /// Village centre longitude.
  final double? longitude;

  /// Meeting point latitude (VV-003), if registered.
  final double? meetingPointLat;

  /// Meeting point longitude.
  final double? meetingPointLon;

  /// Meeting point radius (m); null = tenant default.
  final double? meetingPointRadiusM;

  /// Server row version.
  final int version;

  /// Last pull that touched the row (UTC).
  final DateTime updatedAt;
  const Village({
    required this.id,
    required this.name,
    required this.district,
    required this.mandal,
    required this.state,
    this.storeId,
    this.latitude,
    this.longitude,
    this.meetingPointLat,
    this.meetingPointLon,
    this.meetingPointRadiusM,
    required this.version,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['district'] = Variable<String>(district);
    map['mandal'] = Variable<String>(mandal);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || storeId != null) {
      map['store_id'] = Variable<String>(storeId);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || meetingPointLat != null) {
      map['meeting_point_lat'] = Variable<double>(meetingPointLat);
    }
    if (!nullToAbsent || meetingPointLon != null) {
      map['meeting_point_lon'] = Variable<double>(meetingPointLon);
    }
    if (!nullToAbsent || meetingPointRadiusM != null) {
      map['meeting_point_radius_m'] = Variable<double>(meetingPointRadiusM);
    }
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  VillagesCompanion toCompanion(bool nullToAbsent) {
    return VillagesCompanion(
      id: Value(id),
      name: Value(name),
      district: Value(district),
      mandal: Value(mandal),
      state: Value(state),
      storeId: storeId == null && nullToAbsent
          ? const Value.absent()
          : Value(storeId),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      meetingPointLat: meetingPointLat == null && nullToAbsent
          ? const Value.absent()
          : Value(meetingPointLat),
      meetingPointLon: meetingPointLon == null && nullToAbsent
          ? const Value.absent()
          : Value(meetingPointLon),
      meetingPointRadiusM: meetingPointRadiusM == null && nullToAbsent
          ? const Value.absent()
          : Value(meetingPointRadiusM),
      version: Value(version),
      updatedAt: Value(updatedAt),
    );
  }

  factory Village.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Village(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      district: serializer.fromJson<String>(json['district']),
      mandal: serializer.fromJson<String>(json['mandal']),
      state: serializer.fromJson<String>(json['state']),
      storeId: serializer.fromJson<String?>(json['storeId']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      meetingPointLat: serializer.fromJson<double?>(json['meetingPointLat']),
      meetingPointLon: serializer.fromJson<double?>(json['meetingPointLon']),
      meetingPointRadiusM: serializer.fromJson<double?>(
        json['meetingPointRadiusM'],
      ),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'district': serializer.toJson<String>(district),
      'mandal': serializer.toJson<String>(mandal),
      'state': serializer.toJson<String>(state),
      'storeId': serializer.toJson<String?>(storeId),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'meetingPointLat': serializer.toJson<double?>(meetingPointLat),
      'meetingPointLon': serializer.toJson<double?>(meetingPointLon),
      'meetingPointRadiusM': serializer.toJson<double?>(meetingPointRadiusM),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Village copyWith({
    String? id,
    String? name,
    String? district,
    String? mandal,
    String? state,
    Value<String?> storeId = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> meetingPointLat = const Value.absent(),
    Value<double?> meetingPointLon = const Value.absent(),
    Value<double?> meetingPointRadiusM = const Value.absent(),
    int? version,
    DateTime? updatedAt,
  }) => Village(
    id: id ?? this.id,
    name: name ?? this.name,
    district: district ?? this.district,
    mandal: mandal ?? this.mandal,
    state: state ?? this.state,
    storeId: storeId.present ? storeId.value : this.storeId,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    meetingPointLat: meetingPointLat.present
        ? meetingPointLat.value
        : this.meetingPointLat,
    meetingPointLon: meetingPointLon.present
        ? meetingPointLon.value
        : this.meetingPointLon,
    meetingPointRadiusM: meetingPointRadiusM.present
        ? meetingPointRadiusM.value
        : this.meetingPointRadiusM,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Village copyWithCompanion(VillagesCompanion data) {
    return Village(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      district: data.district.present ? data.district.value : this.district,
      mandal: data.mandal.present ? data.mandal.value : this.mandal,
      state: data.state.present ? data.state.value : this.state,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      meetingPointLat: data.meetingPointLat.present
          ? data.meetingPointLat.value
          : this.meetingPointLat,
      meetingPointLon: data.meetingPointLon.present
          ? data.meetingPointLon.value
          : this.meetingPointLon,
      meetingPointRadiusM: data.meetingPointRadiusM.present
          ? data.meetingPointRadiusM.value
          : this.meetingPointRadiusM,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Village(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('district: $district, ')
          ..write('mandal: $mandal, ')
          ..write('state: $state, ')
          ..write('storeId: $storeId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('meetingPointLat: $meetingPointLat, ')
          ..write('meetingPointLon: $meetingPointLon, ')
          ..write('meetingPointRadiusM: $meetingPointRadiusM, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    district,
    mandal,
    state,
    storeId,
    latitude,
    longitude,
    meetingPointLat,
    meetingPointLon,
    meetingPointRadiusM,
    version,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Village &&
          other.id == this.id &&
          other.name == this.name &&
          other.district == this.district &&
          other.mandal == this.mandal &&
          other.state == this.state &&
          other.storeId == this.storeId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.meetingPointLat == this.meetingPointLat &&
          other.meetingPointLon == this.meetingPointLon &&
          other.meetingPointRadiusM == this.meetingPointRadiusM &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt);
}

class VillagesCompanion extends UpdateCompanion<Village> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> district;
  final Value<String> mandal;
  final Value<String> state;
  final Value<String?> storeId;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> meetingPointLat;
  final Value<double?> meetingPointLon;
  final Value<double?> meetingPointRadiusM;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const VillagesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.district = const Value.absent(),
    this.mandal = const Value.absent(),
    this.state = const Value.absent(),
    this.storeId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.meetingPointLat = const Value.absent(),
    this.meetingPointLon = const Value.absent(),
    this.meetingPointRadiusM = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VillagesCompanion.insert({
    required String id,
    required String name,
    this.district = const Value.absent(),
    this.mandal = const Value.absent(),
    this.state = const Value.absent(),
    this.storeId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.meetingPointLat = const Value.absent(),
    this.meetingPointLon = const Value.absent(),
    this.meetingPointRadiusM = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<Village> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? district,
    Expression<String>? mandal,
    Expression<String>? state,
    Expression<String>? storeId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? meetingPointLat,
    Expression<double>? meetingPointLon,
    Expression<double>? meetingPointRadiusM,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (district != null) 'district': district,
      if (mandal != null) 'mandal': mandal,
      if (state != null) 'state': state,
      if (storeId != null) 'store_id': storeId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (meetingPointLat != null) 'meeting_point_lat': meetingPointLat,
      if (meetingPointLon != null) 'meeting_point_lon': meetingPointLon,
      if (meetingPointRadiusM != null)
        'meeting_point_radius_m': meetingPointRadiusM,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VillagesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? district,
    Value<String>? mandal,
    Value<String>? state,
    Value<String?>? storeId,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? meetingPointLat,
    Value<double?>? meetingPointLon,
    Value<double?>? meetingPointRadiusM,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return VillagesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      district: district ?? this.district,
      mandal: mandal ?? this.mandal,
      state: state ?? this.state,
      storeId: storeId ?? this.storeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      meetingPointLat: meetingPointLat ?? this.meetingPointLat,
      meetingPointLon: meetingPointLon ?? this.meetingPointLon,
      meetingPointRadiusM: meetingPointRadiusM ?? this.meetingPointRadiusM,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (district.present) {
      map['district'] = Variable<String>(district.value);
    }
    if (mandal.present) {
      map['mandal'] = Variable<String>(mandal.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (meetingPointLat.present) {
      map['meeting_point_lat'] = Variable<double>(meetingPointLat.value);
    }
    if (meetingPointLon.present) {
      map['meeting_point_lon'] = Variable<double>(meetingPointLon.value);
    }
    if (meetingPointRadiusM.present) {
      map['meeting_point_radius_m'] = Variable<double>(
        meetingPointRadiusM.value,
      );
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VillagesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('district: $district, ')
          ..write('mandal: $mandal, ')
          ..write('state: $state, ')
          ..write('storeId: $storeId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('meetingPointLat: $meetingPointLat, ')
          ..write('meetingPointLon: $meetingPointLon, ')
          ..write('meetingPointRadiusM: $meetingPointRadiusM, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DutySessionsTable extends DutySessions
    with TableInfo<$DutySessionsTable, DutySession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DutySessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<DateTime> startAt = GeneratedColumn<DateTime>(
    'start_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<DateTime> endAt = GeneratedColumn<DateTime>(
    'end_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endReasonMeta = const VerificationMeta(
    'endReason',
  );
  @override
  late final GeneratedColumn<String> endReason = GeneratedColumn<String>(
    'end_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startLatMeta = const VerificationMeta(
    'startLat',
  );
  @override
  late final GeneratedColumn<double> startLat = GeneratedColumn<double>(
    'start_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startLonMeta = const VerificationMeta(
    'startLon',
  );
  @override
  late final GeneratedColumn<double> startLon = GeneratedColumn<double>(
    'start_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startAccuracyMMeta = const VerificationMeta(
    'startAccuracyM',
  );
  @override
  late final GeneratedColumn<double> startAccuracyM = GeneratedColumn<double>(
    'start_accuracy_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endLatMeta = const VerificationMeta('endLat');
  @override
  late final GeneratedColumn<double> endLat = GeneratedColumn<double>(
    'end_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endLonMeta = const VerificationMeta('endLon');
  @override
  late final GeneratedColumn<double> endLon = GeneratedColumn<double>(
    'end_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endAccuracyMMeta = const VerificationMeta(
    'endAccuracyM',
  );
  @override
  late final GeneratedColumn<double> endAccuracyM = GeneratedColumn<double>(
    'end_accuracy_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _policyVersionMeta = const VerificationMeta(
    'policyVersion',
  );
  @override
  late final GeneratedColumn<String> policyVersion = GeneratedColumn<String>(
    'policy_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _integrityMeta = const VerificationMeta(
    'integrity',
  );
  @override
  late final GeneratedColumn<String> integrity = GeneratedColumn<String>(
    'integrity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  @override
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
    'distance_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _autoEndedMeta = const VerificationMeta(
    'autoEnded',
  );
  @override
  late final GeneratedColumn<bool> autoEnded = GeneratedColumn<bool>(
    'auto_ended',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_ended" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    startAt,
    endAt,
    endReason,
    startLat,
    startLon,
    startAccuracyM,
    endLat,
    endLon,
    endAccuracyM,
    policyVersion,
    deviceId,
    appVersion,
    integrity,
    distanceM,
    autoEnded,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'duty_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DutySession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startAtMeta);
    }
    if (data.containsKey('end_at')) {
      context.handle(
        _endAtMeta,
        endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta),
      );
    }
    if (data.containsKey('end_reason')) {
      context.handle(
        _endReasonMeta,
        endReason.isAcceptableOrUnknown(data['end_reason']!, _endReasonMeta),
      );
    }
    if (data.containsKey('start_lat')) {
      context.handle(
        _startLatMeta,
        startLat.isAcceptableOrUnknown(data['start_lat']!, _startLatMeta),
      );
    }
    if (data.containsKey('start_lon')) {
      context.handle(
        _startLonMeta,
        startLon.isAcceptableOrUnknown(data['start_lon']!, _startLonMeta),
      );
    }
    if (data.containsKey('start_accuracy_m')) {
      context.handle(
        _startAccuracyMMeta,
        startAccuracyM.isAcceptableOrUnknown(
          data['start_accuracy_m']!,
          _startAccuracyMMeta,
        ),
      );
    }
    if (data.containsKey('end_lat')) {
      context.handle(
        _endLatMeta,
        endLat.isAcceptableOrUnknown(data['end_lat']!, _endLatMeta),
      );
    }
    if (data.containsKey('end_lon')) {
      context.handle(
        _endLonMeta,
        endLon.isAcceptableOrUnknown(data['end_lon']!, _endLonMeta),
      );
    }
    if (data.containsKey('end_accuracy_m')) {
      context.handle(
        _endAccuracyMMeta,
        endAccuracyM.isAcceptableOrUnknown(
          data['end_accuracy_m']!,
          _endAccuracyMMeta,
        ),
      );
    }
    if (data.containsKey('policy_version')) {
      context.handle(
        _policyVersionMeta,
        policyVersion.isAcceptableOrUnknown(
          data['policy_version']!,
          _policyVersionMeta,
        ),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    }
    if (data.containsKey('integrity')) {
      context.handle(
        _integrityMeta,
        integrity.isAcceptableOrUnknown(data['integrity']!, _integrityMeta),
      );
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    }
    if (data.containsKey('auto_ended')) {
      context.handle(
        _autoEndedMeta,
        autoEnded.isAcceptableOrUnknown(data['auto_ended']!, _autoEndedMeta),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DutySession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DutySession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_at'],
      )!,
      endAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_at'],
      ),
      endReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_reason'],
      ),
      startLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}start_lat'],
      ),
      startLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}start_lon'],
      ),
      startAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}start_accuracy_m'],
      ),
      endLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_lat'],
      ),
      endLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_lon'],
      ),
      endAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_accuracy_m'],
      ),
      policyVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}policy_version'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      ),
      integrity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}integrity'],
      )!,
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_m'],
      )!,
      autoEnded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_ended'],
      )!,
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      )!,
    );
  }

  @override
  $DutySessionsTable createAlias(String alias) {
    return $DutySessionsTable(attachedDatabase, alias);
  }
}

class DutySession extends DataClass implements Insertable<DutySession> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// When duty started (UTC).
  final DateTime startAt;

  /// When duty ended (UTC); null while active.
  final DateTime? endAt;

  /// `manual` | `auto_time` | `auto_idle` | `forced` | `rejected`.
  final String? endReason;

  /// Start fix latitude.
  final double? startLat;

  /// Start fix longitude.
  final double? startLon;

  /// Start fix accuracy (m).
  final double? startAccuracyM;

  /// End fix latitude.
  final double? endLat;

  /// End fix longitude.
  final double? endLon;

  /// End fix accuracy (m).
  final double? endAccuracyM;

  /// Location policy version accepted when the session started (VV-010).
  final String? policyVersion;

  /// Device that started the session.
  final String? deviceId;

  /// App version that started the session.
  final String? appVersion;

  /// JSON `{is_mock, is_rooted, clock_drift_s}` at start (FA-028).
  final String integrity;

  /// Client-side distance estimate in metres (sum of accepted point hops).
  final double distanceM;

  /// The server ended the session (VV-007); end fields are then read-only.
  final bool autoEnded;

  /// JSON of server fields this app does not model (km, stops, points).
  final String extra;
  const DutySession({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    required this.startAt,
    this.endAt,
    this.endReason,
    this.startLat,
    this.startLon,
    this.startAccuracyM,
    this.endLat,
    this.endLon,
    this.endAccuracyM,
    this.policyVersion,
    this.deviceId,
    this.appVersion,
    required this.integrity,
    required this.distanceM,
    required this.autoEnded,
    required this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['start_at'] = Variable<DateTime>(startAt);
    if (!nullToAbsent || endAt != null) {
      map['end_at'] = Variable<DateTime>(endAt);
    }
    if (!nullToAbsent || endReason != null) {
      map['end_reason'] = Variable<String>(endReason);
    }
    if (!nullToAbsent || startLat != null) {
      map['start_lat'] = Variable<double>(startLat);
    }
    if (!nullToAbsent || startLon != null) {
      map['start_lon'] = Variable<double>(startLon);
    }
    if (!nullToAbsent || startAccuracyM != null) {
      map['start_accuracy_m'] = Variable<double>(startAccuracyM);
    }
    if (!nullToAbsent || endLat != null) {
      map['end_lat'] = Variable<double>(endLat);
    }
    if (!nullToAbsent || endLon != null) {
      map['end_lon'] = Variable<double>(endLon);
    }
    if (!nullToAbsent || endAccuracyM != null) {
      map['end_accuracy_m'] = Variable<double>(endAccuracyM);
    }
    if (!nullToAbsent || policyVersion != null) {
      map['policy_version'] = Variable<String>(policyVersion);
    }
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    if (!nullToAbsent || appVersion != null) {
      map['app_version'] = Variable<String>(appVersion);
    }
    map['integrity'] = Variable<String>(integrity);
    map['distance_m'] = Variable<double>(distanceM);
    map['auto_ended'] = Variable<bool>(autoEnded);
    map['extra'] = Variable<String>(extra);
    return map;
  }

  DutySessionsCompanion toCompanion(bool nullToAbsent) {
    return DutySessionsCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      startAt: Value(startAt),
      endAt: endAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endAt),
      endReason: endReason == null && nullToAbsent
          ? const Value.absent()
          : Value(endReason),
      startLat: startLat == null && nullToAbsent
          ? const Value.absent()
          : Value(startLat),
      startLon: startLon == null && nullToAbsent
          ? const Value.absent()
          : Value(startLon),
      startAccuracyM: startAccuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(startAccuracyM),
      endLat: endLat == null && nullToAbsent
          ? const Value.absent()
          : Value(endLat),
      endLon: endLon == null && nullToAbsent
          ? const Value.absent()
          : Value(endLon),
      endAccuracyM: endAccuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(endAccuracyM),
      policyVersion: policyVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(policyVersion),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      appVersion: appVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(appVersion),
      integrity: Value(integrity),
      distanceM: Value(distanceM),
      autoEnded: Value(autoEnded),
      extra: Value(extra),
    );
  }

  factory DutySession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DutySession(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      startAt: serializer.fromJson<DateTime>(json['startAt']),
      endAt: serializer.fromJson<DateTime?>(json['endAt']),
      endReason: serializer.fromJson<String?>(json['endReason']),
      startLat: serializer.fromJson<double?>(json['startLat']),
      startLon: serializer.fromJson<double?>(json['startLon']),
      startAccuracyM: serializer.fromJson<double?>(json['startAccuracyM']),
      endLat: serializer.fromJson<double?>(json['endLat']),
      endLon: serializer.fromJson<double?>(json['endLon']),
      endAccuracyM: serializer.fromJson<double?>(json['endAccuracyM']),
      policyVersion: serializer.fromJson<String?>(json['policyVersion']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      appVersion: serializer.fromJson<String?>(json['appVersion']),
      integrity: serializer.fromJson<String>(json['integrity']),
      distanceM: serializer.fromJson<double>(json['distanceM']),
      autoEnded: serializer.fromJson<bool>(json['autoEnded']),
      extra: serializer.fromJson<String>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'startAt': serializer.toJson<DateTime>(startAt),
      'endAt': serializer.toJson<DateTime?>(endAt),
      'endReason': serializer.toJson<String?>(endReason),
      'startLat': serializer.toJson<double?>(startLat),
      'startLon': serializer.toJson<double?>(startLon),
      'startAccuracyM': serializer.toJson<double?>(startAccuracyM),
      'endLat': serializer.toJson<double?>(endLat),
      'endLon': serializer.toJson<double?>(endLon),
      'endAccuracyM': serializer.toJson<double?>(endAccuracyM),
      'policyVersion': serializer.toJson<String?>(policyVersion),
      'deviceId': serializer.toJson<String?>(deviceId),
      'appVersion': serializer.toJson<String?>(appVersion),
      'integrity': serializer.toJson<String>(integrity),
      'distanceM': serializer.toJson<double>(distanceM),
      'autoEnded': serializer.toJson<bool>(autoEnded),
      'extra': serializer.toJson<String>(extra),
    };
  }

  DutySession copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    DateTime? startAt,
    Value<DateTime?> endAt = const Value.absent(),
    Value<String?> endReason = const Value.absent(),
    Value<double?> startLat = const Value.absent(),
    Value<double?> startLon = const Value.absent(),
    Value<double?> startAccuracyM = const Value.absent(),
    Value<double?> endLat = const Value.absent(),
    Value<double?> endLon = const Value.absent(),
    Value<double?> endAccuracyM = const Value.absent(),
    Value<String?> policyVersion = const Value.absent(),
    Value<String?> deviceId = const Value.absent(),
    Value<String?> appVersion = const Value.absent(),
    String? integrity,
    double? distanceM,
    bool? autoEnded,
    String? extra,
  }) => DutySession(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    startAt: startAt ?? this.startAt,
    endAt: endAt.present ? endAt.value : this.endAt,
    endReason: endReason.present ? endReason.value : this.endReason,
    startLat: startLat.present ? startLat.value : this.startLat,
    startLon: startLon.present ? startLon.value : this.startLon,
    startAccuracyM: startAccuracyM.present
        ? startAccuracyM.value
        : this.startAccuracyM,
    endLat: endLat.present ? endLat.value : this.endLat,
    endLon: endLon.present ? endLon.value : this.endLon,
    endAccuracyM: endAccuracyM.present ? endAccuracyM.value : this.endAccuracyM,
    policyVersion: policyVersion.present
        ? policyVersion.value
        : this.policyVersion,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    appVersion: appVersion.present ? appVersion.value : this.appVersion,
    integrity: integrity ?? this.integrity,
    distanceM: distanceM ?? this.distanceM,
    autoEnded: autoEnded ?? this.autoEnded,
    extra: extra ?? this.extra,
  );
  DutySession copyWithCompanion(DutySessionsCompanion data) {
    return DutySession(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      endReason: data.endReason.present ? data.endReason.value : this.endReason,
      startLat: data.startLat.present ? data.startLat.value : this.startLat,
      startLon: data.startLon.present ? data.startLon.value : this.startLon,
      startAccuracyM: data.startAccuracyM.present
          ? data.startAccuracyM.value
          : this.startAccuracyM,
      endLat: data.endLat.present ? data.endLat.value : this.endLat,
      endLon: data.endLon.present ? data.endLon.value : this.endLon,
      endAccuracyM: data.endAccuracyM.present
          ? data.endAccuracyM.value
          : this.endAccuracyM,
      policyVersion: data.policyVersion.present
          ? data.policyVersion.value
          : this.policyVersion,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
      integrity: data.integrity.present ? data.integrity.value : this.integrity,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
      autoEnded: data.autoEnded.present ? data.autoEnded.value : this.autoEnded,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DutySession(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('endReason: $endReason, ')
          ..write('startLat: $startLat, ')
          ..write('startLon: $startLon, ')
          ..write('startAccuracyM: $startAccuracyM, ')
          ..write('endLat: $endLat, ')
          ..write('endLon: $endLon, ')
          ..write('endAccuracyM: $endAccuracyM, ')
          ..write('policyVersion: $policyVersion, ')
          ..write('deviceId: $deviceId, ')
          ..write('appVersion: $appVersion, ')
          ..write('integrity: $integrity, ')
          ..write('distanceM: $distanceM, ')
          ..write('autoEnded: $autoEnded, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    startAt,
    endAt,
    endReason,
    startLat,
    startLon,
    startAccuracyM,
    endLat,
    endLon,
    endAccuracyM,
    policyVersion,
    deviceId,
    appVersion,
    integrity,
    distanceM,
    autoEnded,
    extra,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DutySession &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.endReason == this.endReason &&
          other.startLat == this.startLat &&
          other.startLon == this.startLon &&
          other.startAccuracyM == this.startAccuracyM &&
          other.endLat == this.endLat &&
          other.endLon == this.endLon &&
          other.endAccuracyM == this.endAccuracyM &&
          other.policyVersion == this.policyVersion &&
          other.deviceId == this.deviceId &&
          other.appVersion == this.appVersion &&
          other.integrity == this.integrity &&
          other.distanceM == this.distanceM &&
          other.autoEnded == this.autoEnded &&
          other.extra == this.extra);
}

class DutySessionsCompanion extends UpdateCompanion<DutySession> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<DateTime> startAt;
  final Value<DateTime?> endAt;
  final Value<String?> endReason;
  final Value<double?> startLat;
  final Value<double?> startLon;
  final Value<double?> startAccuracyM;
  final Value<double?> endLat;
  final Value<double?> endLon;
  final Value<double?> endAccuracyM;
  final Value<String?> policyVersion;
  final Value<String?> deviceId;
  final Value<String?> appVersion;
  final Value<String> integrity;
  final Value<double> distanceM;
  final Value<bool> autoEnded;
  final Value<String> extra;
  final Value<int> rowid;
  const DutySessionsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.endReason = const Value.absent(),
    this.startLat = const Value.absent(),
    this.startLon = const Value.absent(),
    this.startAccuracyM = const Value.absent(),
    this.endLat = const Value.absent(),
    this.endLon = const Value.absent(),
    this.endAccuracyM = const Value.absent(),
    this.policyVersion = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.integrity = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.autoEnded = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DutySessionsCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required DateTime startAt,
    this.endAt = const Value.absent(),
    this.endReason = const Value.absent(),
    this.startLat = const Value.absent(),
    this.startLon = const Value.absent(),
    this.startAccuracyM = const Value.absent(),
    this.endLat = const Value.absent(),
    this.endLon = const Value.absent(),
    this.endAccuracyM = const Value.absent(),
    this.policyVersion = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.integrity = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.autoEnded = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       startAt = Value(startAt);
  static Insertable<DutySession> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<DateTime>? startAt,
    Expression<DateTime>? endAt,
    Expression<String>? endReason,
    Expression<double>? startLat,
    Expression<double>? startLon,
    Expression<double>? startAccuracyM,
    Expression<double>? endLat,
    Expression<double>? endLon,
    Expression<double>? endAccuracyM,
    Expression<String>? policyVersion,
    Expression<String>? deviceId,
    Expression<String>? appVersion,
    Expression<String>? integrity,
    Expression<double>? distanceM,
    Expression<bool>? autoEnded,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (endReason != null) 'end_reason': endReason,
      if (startLat != null) 'start_lat': startLat,
      if (startLon != null) 'start_lon': startLon,
      if (startAccuracyM != null) 'start_accuracy_m': startAccuracyM,
      if (endLat != null) 'end_lat': endLat,
      if (endLon != null) 'end_lon': endLon,
      if (endAccuracyM != null) 'end_accuracy_m': endAccuracyM,
      if (policyVersion != null) 'policy_version': policyVersion,
      if (deviceId != null) 'device_id': deviceId,
      if (appVersion != null) 'app_version': appVersion,
      if (integrity != null) 'integrity': integrity,
      if (distanceM != null) 'distance_m': distanceM,
      if (autoEnded != null) 'auto_ended': autoEnded,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DutySessionsCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<DateTime>? startAt,
    Value<DateTime?>? endAt,
    Value<String?>? endReason,
    Value<double?>? startLat,
    Value<double?>? startLon,
    Value<double?>? startAccuracyM,
    Value<double?>? endLat,
    Value<double?>? endLon,
    Value<double?>? endAccuracyM,
    Value<String?>? policyVersion,
    Value<String?>? deviceId,
    Value<String?>? appVersion,
    Value<String>? integrity,
    Value<double>? distanceM,
    Value<bool>? autoEnded,
    Value<String>? extra,
    Value<int>? rowid,
  }) {
    return DutySessionsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      endReason: endReason ?? this.endReason,
      startLat: startLat ?? this.startLat,
      startLon: startLon ?? this.startLon,
      startAccuracyM: startAccuracyM ?? this.startAccuracyM,
      endLat: endLat ?? this.endLat,
      endLon: endLon ?? this.endLon,
      endAccuracyM: endAccuracyM ?? this.endAccuracyM,
      policyVersion: policyVersion ?? this.policyVersion,
      deviceId: deviceId ?? this.deviceId,
      appVersion: appVersion ?? this.appVersion,
      integrity: integrity ?? this.integrity,
      distanceM: distanceM ?? this.distanceM,
      autoEnded: autoEnded ?? this.autoEnded,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<DateTime>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<DateTime>(endAt.value);
    }
    if (endReason.present) {
      map['end_reason'] = Variable<String>(endReason.value);
    }
    if (startLat.present) {
      map['start_lat'] = Variable<double>(startLat.value);
    }
    if (startLon.present) {
      map['start_lon'] = Variable<double>(startLon.value);
    }
    if (startAccuracyM.present) {
      map['start_accuracy_m'] = Variable<double>(startAccuracyM.value);
    }
    if (endLat.present) {
      map['end_lat'] = Variable<double>(endLat.value);
    }
    if (endLon.present) {
      map['end_lon'] = Variable<double>(endLon.value);
    }
    if (endAccuracyM.present) {
      map['end_accuracy_m'] = Variable<double>(endAccuracyM.value);
    }
    if (policyVersion.present) {
      map['policy_version'] = Variable<String>(policyVersion.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (integrity.present) {
      map['integrity'] = Variable<String>(integrity.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (autoEnded.present) {
      map['auto_ended'] = Variable<bool>(autoEnded.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DutySessionsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('endReason: $endReason, ')
          ..write('startLat: $startLat, ')
          ..write('startLon: $startLon, ')
          ..write('startAccuracyM: $startAccuracyM, ')
          ..write('endLat: $endLat, ')
          ..write('endLon: $endLon, ')
          ..write('endAccuracyM: $endAccuracyM, ')
          ..write('policyVersion: $policyVersion, ')
          ..write('deviceId: $deviceId, ')
          ..write('appVersion: $appVersion, ')
          ..write('integrity: $integrity, ')
          ..write('distanceM: $distanceM, ')
          ..write('autoEnded: $autoEnded, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocationBufferTable extends LocationBuffer
    with TableInfo<$LocationBufferTable, LocationBufferRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocationBufferTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<DateTime> ts = GeneratedColumn<DateTime>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accuracyMMeta = const VerificationMeta(
    'accuracyM',
  );
  @override
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
    'accuracy_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedMpsMeta = const VerificationMeta(
    'speedMps',
  );
  @override
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
    'speed_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bearingMeta = const VerificationMeta(
    'bearing',
  );
  @override
  late final GeneratedColumn<double> bearing = GeneratedColumn<double>(
    'bearing',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _batteryPctMeta = const VerificationMeta(
    'batteryPct',
  );
  @override
  late final GeneratedColumn<int> batteryPct = GeneratedColumn<int>(
    'battery_pct',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isMockMeta = const VerificationMeta('isMock');
  @override
  late final GeneratedColumn<bool> isMock = GeneratedColumn<bool>(
    'is_mock',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_mock" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isRootedMeta = const VerificationMeta(
    'isRooted',
  );
  @override
  late final GeneratedColumn<bool> isRooted = GeneratedColumn<bool>(
    'is_rooted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_rooted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _clockDriftSMeta = const VerificationMeta(
    'clockDriftS',
  );
  @override
  late final GeneratedColumn<int> clockDriftS = GeneratedColumn<int>(
    'clock_drift_s',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _batchIdMeta = const VerificationMeta(
    'batchId',
  );
  @override
  late final GeneratedColumn<String> batchId = GeneratedColumn<String>(
    'batch_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    ts,
    lat,
    lon,
    accuracyM,
    speedMps,
    bearing,
    batteryPct,
    isMock,
    isRooted,
    clockDriftS,
    provider,
    batchId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'location_buffer';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocationBufferRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(
        _accuracyMMeta,
        accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta),
      );
    } else if (isInserting) {
      context.missing(_accuracyMMeta);
    }
    if (data.containsKey('speed_mps')) {
      context.handle(
        _speedMpsMeta,
        speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta),
      );
    }
    if (data.containsKey('bearing')) {
      context.handle(
        _bearingMeta,
        bearing.isAcceptableOrUnknown(data['bearing']!, _bearingMeta),
      );
    }
    if (data.containsKey('battery_pct')) {
      context.handle(
        _batteryPctMeta,
        batteryPct.isAcceptableOrUnknown(data['battery_pct']!, _batteryPctMeta),
      );
    }
    if (data.containsKey('is_mock')) {
      context.handle(
        _isMockMeta,
        isMock.isAcceptableOrUnknown(data['is_mock']!, _isMockMeta),
      );
    }
    if (data.containsKey('is_rooted')) {
      context.handle(
        _isRootedMeta,
        isRooted.isAcceptableOrUnknown(data['is_rooted']!, _isRootedMeta),
      );
    }
    if (data.containsKey('clock_drift_s')) {
      context.handle(
        _clockDriftSMeta,
        clockDriftS.isAcceptableOrUnknown(
          data['clock_drift_s']!,
          _clockDriftSMeta,
        ),
      );
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('batch_id')) {
      context.handle(
        _batchIdMeta,
        batchId.isAcceptableOrUnknown(data['batch_id']!, _batchIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocationBufferRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocationBufferRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ts'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      accuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_m'],
      )!,
      speedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_mps'],
      ),
      bearing: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bearing'],
      ),
      batteryPct: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}battery_pct'],
      ),
      isMock: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_mock'],
      )!,
      isRooted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_rooted'],
      )!,
      clockDriftS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}clock_drift_s'],
      ),
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      ),
      batchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}batch_id'],
      ),
    );
  }

  @override
  $LocationBufferTable createAlias(String alias) {
    return $LocationBufferTable(attachedDatabase, alias);
  }
}

class LocationBufferRow extends DataClass
    implements Insertable<LocationBufferRow> {
  /// Local sequence.
  final int id;

  /// Owning duty session.
  final String sessionId;

  /// Fix time (UTC).
  final DateTime ts;

  /// Latitude.
  final double lat;

  /// Longitude.
  final double lon;

  /// Horizontal accuracy (m).
  final double accuracyM;

  /// Speed (m/s), if the provider gave one.
  final double? speedMps;

  /// Bearing (degrees), if the provider gave one.
  final double? bearing;

  /// Battery level 0-100.
  final int? batteryPct;

  /// The fix came from a mock provider (FA-028).
  final bool isMock;

  /// The device looked rooted when the fix was taken (FA-028).
  final bool isRooted;

  /// Device clock minus server clock (s) at the fix, if known (VV-002).
  final int? clockDriftS;

  /// `fused` | `gps` | `network` | ...
  final String? provider;

  /// The `location_batch` op the point went out in; null while pending.
  final String? batchId;
  const LocationBufferRow({
    required this.id,
    required this.sessionId,
    required this.ts,
    required this.lat,
    required this.lon,
    required this.accuracyM,
    this.speedMps,
    this.bearing,
    this.batteryPct,
    required this.isMock,
    required this.isRooted,
    this.clockDriftS,
    this.provider,
    this.batchId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['ts'] = Variable<DateTime>(ts);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['accuracy_m'] = Variable<double>(accuracyM);
    if (!nullToAbsent || speedMps != null) {
      map['speed_mps'] = Variable<double>(speedMps);
    }
    if (!nullToAbsent || bearing != null) {
      map['bearing'] = Variable<double>(bearing);
    }
    if (!nullToAbsent || batteryPct != null) {
      map['battery_pct'] = Variable<int>(batteryPct);
    }
    map['is_mock'] = Variable<bool>(isMock);
    map['is_rooted'] = Variable<bool>(isRooted);
    if (!nullToAbsent || clockDriftS != null) {
      map['clock_drift_s'] = Variable<int>(clockDriftS);
    }
    if (!nullToAbsent || provider != null) {
      map['provider'] = Variable<String>(provider);
    }
    if (!nullToAbsent || batchId != null) {
      map['batch_id'] = Variable<String>(batchId);
    }
    return map;
  }

  LocationBufferCompanion toCompanion(bool nullToAbsent) {
    return LocationBufferCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      ts: Value(ts),
      lat: Value(lat),
      lon: Value(lon),
      accuracyM: Value(accuracyM),
      speedMps: speedMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMps),
      bearing: bearing == null && nullToAbsent
          ? const Value.absent()
          : Value(bearing),
      batteryPct: batteryPct == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryPct),
      isMock: Value(isMock),
      isRooted: Value(isRooted),
      clockDriftS: clockDriftS == null && nullToAbsent
          ? const Value.absent()
          : Value(clockDriftS),
      provider: provider == null && nullToAbsent
          ? const Value.absent()
          : Value(provider),
      batchId: batchId == null && nullToAbsent
          ? const Value.absent()
          : Value(batchId),
    );
  }

  factory LocationBufferRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocationBufferRow(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      ts: serializer.fromJson<DateTime>(json['ts']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      accuracyM: serializer.fromJson<double>(json['accuracyM']),
      speedMps: serializer.fromJson<double?>(json['speedMps']),
      bearing: serializer.fromJson<double?>(json['bearing']),
      batteryPct: serializer.fromJson<int?>(json['batteryPct']),
      isMock: serializer.fromJson<bool>(json['isMock']),
      isRooted: serializer.fromJson<bool>(json['isRooted']),
      clockDriftS: serializer.fromJson<int?>(json['clockDriftS']),
      provider: serializer.fromJson<String?>(json['provider']),
      batchId: serializer.fromJson<String?>(json['batchId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'ts': serializer.toJson<DateTime>(ts),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'accuracyM': serializer.toJson<double>(accuracyM),
      'speedMps': serializer.toJson<double?>(speedMps),
      'bearing': serializer.toJson<double?>(bearing),
      'batteryPct': serializer.toJson<int?>(batteryPct),
      'isMock': serializer.toJson<bool>(isMock),
      'isRooted': serializer.toJson<bool>(isRooted),
      'clockDriftS': serializer.toJson<int?>(clockDriftS),
      'provider': serializer.toJson<String?>(provider),
      'batchId': serializer.toJson<String?>(batchId),
    };
  }

  LocationBufferRow copyWith({
    int? id,
    String? sessionId,
    DateTime? ts,
    double? lat,
    double? lon,
    double? accuracyM,
    Value<double?> speedMps = const Value.absent(),
    Value<double?> bearing = const Value.absent(),
    Value<int?> batteryPct = const Value.absent(),
    bool? isMock,
    bool? isRooted,
    Value<int?> clockDriftS = const Value.absent(),
    Value<String?> provider = const Value.absent(),
    Value<String?> batchId = const Value.absent(),
  }) => LocationBufferRow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    ts: ts ?? this.ts,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    accuracyM: accuracyM ?? this.accuracyM,
    speedMps: speedMps.present ? speedMps.value : this.speedMps,
    bearing: bearing.present ? bearing.value : this.bearing,
    batteryPct: batteryPct.present ? batteryPct.value : this.batteryPct,
    isMock: isMock ?? this.isMock,
    isRooted: isRooted ?? this.isRooted,
    clockDriftS: clockDriftS.present ? clockDriftS.value : this.clockDriftS,
    provider: provider.present ? provider.value : this.provider,
    batchId: batchId.present ? batchId.value : this.batchId,
  );
  LocationBufferRow copyWithCompanion(LocationBufferCompanion data) {
    return LocationBufferRow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      ts: data.ts.present ? data.ts.value : this.ts,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
      bearing: data.bearing.present ? data.bearing.value : this.bearing,
      batteryPct: data.batteryPct.present
          ? data.batteryPct.value
          : this.batteryPct,
      isMock: data.isMock.present ? data.isMock.value : this.isMock,
      isRooted: data.isRooted.present ? data.isRooted.value : this.isRooted,
      clockDriftS: data.clockDriftS.present
          ? data.clockDriftS.value
          : this.clockDriftS,
      provider: data.provider.present ? data.provider.value : this.provider,
      batchId: data.batchId.present ? data.batchId.value : this.batchId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocationBufferRow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('ts: $ts, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('bearing: $bearing, ')
          ..write('batteryPct: $batteryPct, ')
          ..write('isMock: $isMock, ')
          ..write('isRooted: $isRooted, ')
          ..write('clockDriftS: $clockDriftS, ')
          ..write('provider: $provider, ')
          ..write('batchId: $batchId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    ts,
    lat,
    lon,
    accuracyM,
    speedMps,
    bearing,
    batteryPct,
    isMock,
    isRooted,
    clockDriftS,
    provider,
    batchId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocationBufferRow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.ts == this.ts &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.accuracyM == this.accuracyM &&
          other.speedMps == this.speedMps &&
          other.bearing == this.bearing &&
          other.batteryPct == this.batteryPct &&
          other.isMock == this.isMock &&
          other.isRooted == this.isRooted &&
          other.clockDriftS == this.clockDriftS &&
          other.provider == this.provider &&
          other.batchId == this.batchId);
}

class LocationBufferCompanion extends UpdateCompanion<LocationBufferRow> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<DateTime> ts;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double> accuracyM;
  final Value<double?> speedMps;
  final Value<double?> bearing;
  final Value<int?> batteryPct;
  final Value<bool> isMock;
  final Value<bool> isRooted;
  final Value<int?> clockDriftS;
  final Value<String?> provider;
  final Value<String?> batchId;
  const LocationBufferCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.ts = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.bearing = const Value.absent(),
    this.batteryPct = const Value.absent(),
    this.isMock = const Value.absent(),
    this.isRooted = const Value.absent(),
    this.clockDriftS = const Value.absent(),
    this.provider = const Value.absent(),
    this.batchId = const Value.absent(),
  });
  LocationBufferCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required DateTime ts,
    required double lat,
    required double lon,
    required double accuracyM,
    this.speedMps = const Value.absent(),
    this.bearing = const Value.absent(),
    this.batteryPct = const Value.absent(),
    this.isMock = const Value.absent(),
    this.isRooted = const Value.absent(),
    this.clockDriftS = const Value.absent(),
    this.provider = const Value.absent(),
    this.batchId = const Value.absent(),
  }) : sessionId = Value(sessionId),
       ts = Value(ts),
       lat = Value(lat),
       lon = Value(lon),
       accuracyM = Value(accuracyM);
  static Insertable<LocationBufferRow> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<DateTime>? ts,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? accuracyM,
    Expression<double>? speedMps,
    Expression<double>? bearing,
    Expression<int>? batteryPct,
    Expression<bool>? isMock,
    Expression<bool>? isRooted,
    Expression<int>? clockDriftS,
    Expression<String>? provider,
    Expression<String>? batchId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (ts != null) 'ts': ts,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (speedMps != null) 'speed_mps': speedMps,
      if (bearing != null) 'bearing': bearing,
      if (batteryPct != null) 'battery_pct': batteryPct,
      if (isMock != null) 'is_mock': isMock,
      if (isRooted != null) 'is_rooted': isRooted,
      if (clockDriftS != null) 'clock_drift_s': clockDriftS,
      if (provider != null) 'provider': provider,
      if (batchId != null) 'batch_id': batchId,
    });
  }

  LocationBufferCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<DateTime>? ts,
    Value<double>? lat,
    Value<double>? lon,
    Value<double>? accuracyM,
    Value<double?>? speedMps,
    Value<double?>? bearing,
    Value<int?>? batteryPct,
    Value<bool>? isMock,
    Value<bool>? isRooted,
    Value<int?>? clockDriftS,
    Value<String?>? provider,
    Value<String?>? batchId,
  }) {
    return LocationBufferCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      ts: ts ?? this.ts,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracyM: accuracyM ?? this.accuracyM,
      speedMps: speedMps ?? this.speedMps,
      bearing: bearing ?? this.bearing,
      batteryPct: batteryPct ?? this.batteryPct,
      isMock: isMock ?? this.isMock,
      isRooted: isRooted ?? this.isRooted,
      clockDriftS: clockDriftS ?? this.clockDriftS,
      provider: provider ?? this.provider,
      batchId: batchId ?? this.batchId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (ts.present) {
      map['ts'] = Variable<DateTime>(ts.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    if (bearing.present) {
      map['bearing'] = Variable<double>(bearing.value);
    }
    if (batteryPct.present) {
      map['battery_pct'] = Variable<int>(batteryPct.value);
    }
    if (isMock.present) {
      map['is_mock'] = Variable<bool>(isMock.value);
    }
    if (isRooted.present) {
      map['is_rooted'] = Variable<bool>(isRooted.value);
    }
    if (clockDriftS.present) {
      map['clock_drift_s'] = Variable<int>(clockDriftS.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (batchId.present) {
      map['batch_id'] = Variable<String>(batchId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocationBufferCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('ts: $ts, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('speedMps: $speedMps, ')
          ..write('bearing: $bearing, ')
          ..write('batteryPct: $batteryPct, ')
          ..write('isMock: $isMock, ')
          ..write('isRooted: $isRooted, ')
          ..write('clockDriftS: $clockDriftS, ')
          ..write('provider: $provider, ')
          ..write('batchId: $batchId')
          ..write(')'))
        .toString();
  }
}

class $SyncDocsTable extends SyncDocs with TableInfo<$SyncDocsTable, SyncDoc> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncDocsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entity,
    docId,
    version,
    dirty,
    deleted,
    data,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_docs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncDoc> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity, docId};
  @override
  SyncDoc map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncDoc(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncDocsTable createAlias(String alias) {
    return $SyncDocsTable(attachedDatabase, alias);
  }
}

class SyncDoc extends DataClass implements Insertable<SyncDoc> {
  /// Entity wire name.
  final String entity;

  /// Row id.
  final String docId;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// A queued op still references this row.
  final bool dirty;

  /// Local tombstone.
  final bool deleted;

  /// JSON data.
  final String data;

  /// Last local write (UTC).
  final DateTime updatedAt;
  const SyncDoc({
    required this.entity,
    required this.docId,
    required this.version,
    required this.dirty,
    required this.deleted,
    required this.data,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['doc_id'] = Variable<String>(docId);
    map['version'] = Variable<int>(version);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['data'] = Variable<String>(data);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncDocsCompanion toCompanion(bool nullToAbsent) {
    return SyncDocsCompanion(
      entity: Value(entity),
      docId: Value(docId),
      version: Value(version),
      dirty: Value(dirty),
      deleted: Value(deleted),
      data: Value(data),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncDoc.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncDoc(
      entity: serializer.fromJson<String>(json['entity']),
      docId: serializer.fromJson<String>(json['docId']),
      version: serializer.fromJson<int>(json['version']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      data: serializer.fromJson<String>(json['data']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'docId': serializer.toJson<String>(docId),
      'version': serializer.toJson<int>(version),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'data': serializer.toJson<String>(data),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncDoc copyWith({
    String? entity,
    String? docId,
    int? version,
    bool? dirty,
    bool? deleted,
    String? data,
    DateTime? updatedAt,
  }) => SyncDoc(
    entity: entity ?? this.entity,
    docId: docId ?? this.docId,
    version: version ?? this.version,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    data: data ?? this.data,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncDoc copyWithCompanion(SyncDocsCompanion data) {
    return SyncDoc(
      entity: data.entity.present ? data.entity.value : this.entity,
      docId: data.docId.present ? data.docId.value : this.docId,
      version: data.version.present ? data.version.value : this.version,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      data: data.data.present ? data.data.value : this.data,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncDoc(')
          ..write('entity: $entity, ')
          ..write('docId: $docId, ')
          ..write('version: $version, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(entity, docId, version, dirty, deleted, data, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncDoc &&
          other.entity == this.entity &&
          other.docId == this.docId &&
          other.version == this.version &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.data == this.data &&
          other.updatedAt == this.updatedAt);
}

class SyncDocsCompanion extends UpdateCompanion<SyncDoc> {
  final Value<String> entity;
  final Value<String> docId;
  final Value<int> version;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String> data;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncDocsCompanion({
    this.entity = const Value.absent(),
    this.docId = const Value.absent(),
    this.version = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.data = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncDocsCompanion.insert({
    required String entity,
    required String docId,
    this.version = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required String data,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : entity = Value(entity),
       docId = Value(docId),
       data = Value(data),
       updatedAt = Value(updatedAt);
  static Insertable<SyncDoc> custom({
    Expression<String>? entity,
    Expression<String>? docId,
    Expression<int>? version,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? data,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (docId != null) 'doc_id': docId,
      if (version != null) 'version': version,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (data != null) 'data': data,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncDocsCompanion copyWith({
    Value<String>? entity,
    Value<String>? docId,
    Value<int>? version,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String>? data,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncDocsCompanion(
      entity: entity ?? this.entity,
      docId: docId ?? this.docId,
      version: version ?? this.version,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      data: data ?? this.data,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncDocsCompanion(')
          ..write('entity: $entity, ')
          ..write('docId: $docId, ')
          ..write('version: $version, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('data: $data, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisitsTable extends Visits with TableInfo<$VisitsTable, Visit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _farmerIdMeta = const VerificationMeta(
    'farmerId',
  );
  @override
  late final GeneratedColumn<String> farmerId = GeneratedColumn<String>(
    'farmer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _farmIdMeta = const VerificationMeta('farmId');
  @override
  late final GeneratedColumn<String> farmId = GeneratedColumn<String>(
    'farm_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _villageIdMeta = const VerificationMeta(
    'villageId',
  );
  @override
  late final GeneratedColumn<String> villageId = GeneratedColumn<String>(
    'village_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purposeMeta = const VerificationMeta(
    'purpose',
  );
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
    'purpose',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('advisory'),
  );
  static const VerificationMeta _checkinAtMeta = const VerificationMeta(
    'checkinAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkinAt = GeneratedColumn<DateTime>(
    'checkin_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkinLatMeta = const VerificationMeta(
    'checkinLat',
  );
  @override
  late final GeneratedColumn<double> checkinLat = GeneratedColumn<double>(
    'checkin_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkinLonMeta = const VerificationMeta(
    'checkinLon',
  );
  @override
  late final GeneratedColumn<double> checkinLon = GeneratedColumn<double>(
    'checkin_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkinAccuracyMMeta = const VerificationMeta(
    'checkinAccuracyM',
  );
  @override
  late final GeneratedColumn<double> checkinAccuracyM = GeneratedColumn<double>(
    'checkin_accuracy_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkoutAtMeta = const VerificationMeta(
    'checkoutAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkoutAt = GeneratedColumn<DateTime>(
    'checkout_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkoutLatMeta = const VerificationMeta(
    'checkoutLat',
  );
  @override
  late final GeneratedColumn<double> checkoutLat = GeneratedColumn<double>(
    'checkout_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _checkoutLonMeta = const VerificationMeta(
    'checkoutLon',
  );
  @override
  late final GeneratedColumn<double> checkoutLon = GeneratedColumn<double>(
    'checkout_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _geofenceResultMeta = const VerificationMeta(
    'geofenceResult',
  );
  @override
  late final GeneratedColumn<String> geofenceResult = GeneratedColumn<String>(
    'geofence_result',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _precheckResultMeta = const VerificationMeta(
    'precheckResult',
  );
  @override
  late final GeneratedColumn<String> precheckResult = GeneratedColumn<String>(
    'precheck_result',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _precheckDistanceMMeta = const VerificationMeta(
    'precheckDistanceM',
  );
  @override
  late final GeneratedColumn<double> precheckDistanceM =
      GeneratedColumn<double>(
        'precheck_distance_m',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _precheckTargetMeta = const VerificationMeta(
    'precheckTarget',
  );
  @override
  late final GeneratedColumn<String> precheckTarget = GeneratedColumn<String>(
    'precheck_target',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _precheckRadiusMMeta = const VerificationMeta(
    'precheckRadiusM',
  );
  @override
  late final GeneratedColumn<double> precheckRadiusM = GeneratedColumn<double>(
    'precheck_radius_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _overrideNoteMeta = const VerificationMeta(
    'overrideNote',
  );
  @override
  late final GeneratedColumn<String> overrideNote = GeneratedColumn<String>(
    'override_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _overrideApprovedByMeta =
      const VerificationMeta('overrideApprovedBy');
  @override
  late final GeneratedColumn<String> overrideApprovedBy =
      GeneratedColumn<String>(
        'override_approved_by',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropStageMeta = const VerificationMeta(
    'cropStage',
  );
  @override
  late final GeneratedColumn<String> cropStage = GeneratedColumn<String>(
    'crop_stage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSMeta = const VerificationMeta(
    'durationS',
  );
  @override
  late final GeneratedColumn<int> durationS = GeneratedColumn<int>(
    'duration_s',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('open'),
  );
  static const VerificationMeta _confirmationChannelMeta =
      const VerificationMeta('confirmationChannel');
  @override
  late final GeneratedColumn<String> confirmationChannel =
      GeneratedColumn<String>(
        'confirmation_channel',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('none'),
      );
  static const VerificationMeta _confirmedAtMeta = const VerificationMeta(
    'confirmedAt',
  );
  @override
  late final GeneratedColumn<DateTime> confirmedAt = GeneratedColumn<DateTime>(
    'confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIntegrityMeta = const VerificationMeta(
    'deviceIntegrity',
  );
  @override
  late final GeneratedColumn<String> deviceIntegrity = GeneratedColumn<String>(
    'device_integrity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _integrityIssuesMeta = const VerificationMeta(
    'integrityIssues',
  );
  @override
  late final GeneratedColumn<String> integrityIssues = GeneratedColumn<String>(
    'integrity_issues',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _flagsMeta = const VerificationMeta('flags');
  @override
  late final GeneratedColumn<String> flags = GeneratedColumn<String>(
    'flags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _scoreComponentsMeta = const VerificationMeta(
    'scoreComponents',
  );
  @override
  late final GeneratedColumn<String> scoreComponents = GeneratedColumn<String>(
    'score_components',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientVisitIdMeta = const VerificationMeta(
    'clientVisitId',
  );
  @override
  late final GeneratedColumn<String> clientVisitId = GeneratedColumn<String>(
    'client_visit_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _officerIdMeta = const VerificationMeta(
    'officerId',
  );
  @override
  late final GeneratedColumn<String> officerId = GeneratedColumn<String>(
    'officer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureDetailMeta = const VerificationMeta(
    'failureDetail',
  );
  @override
  late final GeneratedColumn<String> failureDetail = GeneratedColumn<String>(
    'failure_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    farmId,
    villageId,
    purpose,
    checkinAt,
    checkinLat,
    checkinLon,
    checkinAccuracyM,
    checkoutAt,
    checkoutLat,
    checkoutLon,
    geofenceResult,
    precheckResult,
    precheckDistanceM,
    precheckTarget,
    precheckRadiusM,
    overrideNote,
    overrideApprovedBy,
    notes,
    cropStage,
    durationS,
    score,
    status,
    confirmationChannel,
    confirmedAt,
    deviceIntegrity,
    integrityIssues,
    flags,
    scoreComponents,
    clientVisitId,
    officerId,
    failureCode,
    failureDetail,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visits';
  @override
  VerificationContext validateIntegrity(
    Insertable<Visit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('farmer_id')) {
      context.handle(
        _farmerIdMeta,
        farmerId.isAcceptableOrUnknown(data['farmer_id']!, _farmerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmerIdMeta);
    }
    if (data.containsKey('farm_id')) {
      context.handle(
        _farmIdMeta,
        farmId.isAcceptableOrUnknown(data['farm_id']!, _farmIdMeta),
      );
    }
    if (data.containsKey('village_id')) {
      context.handle(
        _villageIdMeta,
        villageId.isAcceptableOrUnknown(data['village_id']!, _villageIdMeta),
      );
    }
    if (data.containsKey('purpose')) {
      context.handle(
        _purposeMeta,
        purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta),
      );
    }
    if (data.containsKey('checkin_at')) {
      context.handle(
        _checkinAtMeta,
        checkinAt.isAcceptableOrUnknown(data['checkin_at']!, _checkinAtMeta),
      );
    } else if (isInserting) {
      context.missing(_checkinAtMeta);
    }
    if (data.containsKey('checkin_lat')) {
      context.handle(
        _checkinLatMeta,
        checkinLat.isAcceptableOrUnknown(data['checkin_lat']!, _checkinLatMeta),
      );
    } else if (isInserting) {
      context.missing(_checkinLatMeta);
    }
    if (data.containsKey('checkin_lon')) {
      context.handle(
        _checkinLonMeta,
        checkinLon.isAcceptableOrUnknown(data['checkin_lon']!, _checkinLonMeta),
      );
    } else if (isInserting) {
      context.missing(_checkinLonMeta);
    }
    if (data.containsKey('checkin_accuracy_m')) {
      context.handle(
        _checkinAccuracyMMeta,
        checkinAccuracyM.isAcceptableOrUnknown(
          data['checkin_accuracy_m']!,
          _checkinAccuracyMMeta,
        ),
      );
    }
    if (data.containsKey('checkout_at')) {
      context.handle(
        _checkoutAtMeta,
        checkoutAt.isAcceptableOrUnknown(data['checkout_at']!, _checkoutAtMeta),
      );
    }
    if (data.containsKey('checkout_lat')) {
      context.handle(
        _checkoutLatMeta,
        checkoutLat.isAcceptableOrUnknown(
          data['checkout_lat']!,
          _checkoutLatMeta,
        ),
      );
    }
    if (data.containsKey('checkout_lon')) {
      context.handle(
        _checkoutLonMeta,
        checkoutLon.isAcceptableOrUnknown(
          data['checkout_lon']!,
          _checkoutLonMeta,
        ),
      );
    }
    if (data.containsKey('geofence_result')) {
      context.handle(
        _geofenceResultMeta,
        geofenceResult.isAcceptableOrUnknown(
          data['geofence_result']!,
          _geofenceResultMeta,
        ),
      );
    }
    if (data.containsKey('precheck_result')) {
      context.handle(
        _precheckResultMeta,
        precheckResult.isAcceptableOrUnknown(
          data['precheck_result']!,
          _precheckResultMeta,
        ),
      );
    }
    if (data.containsKey('precheck_distance_m')) {
      context.handle(
        _precheckDistanceMMeta,
        precheckDistanceM.isAcceptableOrUnknown(
          data['precheck_distance_m']!,
          _precheckDistanceMMeta,
        ),
      );
    }
    if (data.containsKey('precheck_target')) {
      context.handle(
        _precheckTargetMeta,
        precheckTarget.isAcceptableOrUnknown(
          data['precheck_target']!,
          _precheckTargetMeta,
        ),
      );
    }
    if (data.containsKey('precheck_radius_m')) {
      context.handle(
        _precheckRadiusMMeta,
        precheckRadiusM.isAcceptableOrUnknown(
          data['precheck_radius_m']!,
          _precheckRadiusMMeta,
        ),
      );
    }
    if (data.containsKey('override_note')) {
      context.handle(
        _overrideNoteMeta,
        overrideNote.isAcceptableOrUnknown(
          data['override_note']!,
          _overrideNoteMeta,
        ),
      );
    }
    if (data.containsKey('override_approved_by')) {
      context.handle(
        _overrideApprovedByMeta,
        overrideApprovedBy.isAcceptableOrUnknown(
          data['override_approved_by']!,
          _overrideApprovedByMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('crop_stage')) {
      context.handle(
        _cropStageMeta,
        cropStage.isAcceptableOrUnknown(data['crop_stage']!, _cropStageMeta),
      );
    }
    if (data.containsKey('duration_s')) {
      context.handle(
        _durationSMeta,
        durationS.isAcceptableOrUnknown(data['duration_s']!, _durationSMeta),
      );
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('confirmation_channel')) {
      context.handle(
        _confirmationChannelMeta,
        confirmationChannel.isAcceptableOrUnknown(
          data['confirmation_channel']!,
          _confirmationChannelMeta,
        ),
      );
    }
    if (data.containsKey('confirmed_at')) {
      context.handle(
        _confirmedAtMeta,
        confirmedAt.isAcceptableOrUnknown(
          data['confirmed_at']!,
          _confirmedAtMeta,
        ),
      );
    }
    if (data.containsKey('device_integrity')) {
      context.handle(
        _deviceIntegrityMeta,
        deviceIntegrity.isAcceptableOrUnknown(
          data['device_integrity']!,
          _deviceIntegrityMeta,
        ),
      );
    }
    if (data.containsKey('integrity_issues')) {
      context.handle(
        _integrityIssuesMeta,
        integrityIssues.isAcceptableOrUnknown(
          data['integrity_issues']!,
          _integrityIssuesMeta,
        ),
      );
    }
    if (data.containsKey('flags')) {
      context.handle(
        _flagsMeta,
        flags.isAcceptableOrUnknown(data['flags']!, _flagsMeta),
      );
    }
    if (data.containsKey('score_components')) {
      context.handle(
        _scoreComponentsMeta,
        scoreComponents.isAcceptableOrUnknown(
          data['score_components']!,
          _scoreComponentsMeta,
        ),
      );
    }
    if (data.containsKey('client_visit_id')) {
      context.handle(
        _clientVisitIdMeta,
        clientVisitId.isAcceptableOrUnknown(
          data['client_visit_id']!,
          _clientVisitIdMeta,
        ),
      );
    }
    if (data.containsKey('officer_id')) {
      context.handle(
        _officerIdMeta,
        officerId.isAcceptableOrUnknown(data['officer_id']!, _officerIdMeta),
      );
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    if (data.containsKey('failure_detail')) {
      context.handle(
        _failureDetailMeta,
        failureDetail.isAcceptableOrUnknown(
          data['failure_detail']!,
          _failureDetailMeta,
        ),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Visit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Visit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      farmerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farmer_id'],
      )!,
      farmId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farm_id'],
      ),
      villageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}village_id'],
      ),
      purpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purpose'],
      )!,
      checkinAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checkin_at'],
      )!,
      checkinLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}checkin_lat'],
      )!,
      checkinLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}checkin_lon'],
      )!,
      checkinAccuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}checkin_accuracy_m'],
      ),
      checkoutAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checkout_at'],
      ),
      checkoutLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}checkout_lat'],
      ),
      checkoutLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}checkout_lon'],
      ),
      geofenceResult: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}geofence_result'],
      ),
      precheckResult: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}precheck_result'],
      ),
      precheckDistanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}precheck_distance_m'],
      ),
      precheckTarget: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}precheck_target'],
      ),
      precheckRadiusM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}precheck_radius_m'],
      ),
      overrideNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}override_note'],
      ),
      overrideApprovedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}override_approved_by'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      cropStage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop_stage'],
      ),
      durationS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_s'],
      ),
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      confirmationChannel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confirmation_channel'],
      )!,
      confirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}confirmed_at'],
      ),
      deviceIntegrity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_integrity'],
      )!,
      integrityIssues: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}integrity_issues'],
      )!,
      flags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}flags'],
      )!,
      scoreComponents: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}score_components'],
      ),
      clientVisitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_visit_id'],
      ),
      officerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}officer_id'],
      ),
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      failureDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_detail'],
      ),
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      )!,
    );
  }

  @override
  $VisitsTable createAlias(String alias) {
    return $VisitsTable(attachedDatabase, alias);
  }
}

class Visit extends DataClass implements Insertable<Visit> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Farmer visited.
  final String farmerId;

  /// Farm (geofence target), if any.
  final String? farmId;

  /// Meeting-point village, if any.
  final String? villageId;

  /// `advisory` | `scouting` | `demo` | `collection` | `sale` | `meeting`.
  final String purpose;

  /// Check-in time (UTC, device clock).
  final DateTime checkinAt;

  /// Check-in fix latitude.
  final double checkinLat;

  /// Check-in fix longitude.
  final double checkinLon;

  /// Check-in fix accuracy (m).
  final double? checkinAccuracyM;

  /// Check-out time (UTC); null while open.
  final DateTime? checkoutAt;

  /// Check-out fix latitude.
  final double? checkoutLat;

  /// Check-out fix longitude.
  final double? checkoutLon;

  /// Server `geofence_result` (inside | outside | meeting_point | override).
  final String? geofenceResult;

  /// Client pre-check result (inside | meeting_point | outside).
  final String? precheckResult;

  /// Client pre-check distance to the target (m).
  final double? precheckDistanceM;

  /// Client pre-check target (`farm` | `meeting_point`).
  final String? precheckTarget;

  /// Client pre-check radius (m).
  final double? precheckRadiusM;

  /// FA-014 override note (outside the geofence).
  final String? overrideNote;

  /// Cluster head who approved the override, once decided.
  final String? overrideApprovedBy;

  /// FA-015 notes.
  final String? notes;

  /// FA-015 crop stage.
  final String? cropStage;

  /// Server-computed duration (s).
  final int? durationS;

  /// Server VV-004 score; null while open.
  final int? score;

  /// Server VV-005 status (`open` until check-out).
  final String status;

  /// `sms_otp` | `app_push` | `qr` | `none`.
  final String confirmationChannel;

  /// Server-owned confirmation time.
  final DateTime? confirmedAt;

  /// JSON `{is_mock, is_rooted, clock_drift_s}` at check-in (FA-028).
  final String deviceIntegrity;

  /// JSON list of server integrity issues.
  final String integrityIssues;

  /// JSON list of server flags (`under_minimum`).
  final String flags;

  /// JSON `{geofence, confirmation, photo, duration, integrity}` from the
  /// server; null until the server has seen the visit.
  final String? scoreComponents;

  /// The device's own id for replays (defaults to `id`).
  final String? clientVisitId;

  /// Officer (server-assigned).
  final String? officerId;

  /// Problem code of a rejected check-in (`outside_geofence`).
  final String? failureCode;

  /// JSON `{detail, distance_m, target, radius_m}` of the rejection.
  final String? failureDetail;

  /// JSON of server fields this app does not model.
  final String extra;
  const Visit({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    required this.farmerId,
    this.farmId,
    this.villageId,
    required this.purpose,
    required this.checkinAt,
    required this.checkinLat,
    required this.checkinLon,
    this.checkinAccuracyM,
    this.checkoutAt,
    this.checkoutLat,
    this.checkoutLon,
    this.geofenceResult,
    this.precheckResult,
    this.precheckDistanceM,
    this.precheckTarget,
    this.precheckRadiusM,
    this.overrideNote,
    this.overrideApprovedBy,
    this.notes,
    this.cropStage,
    this.durationS,
    this.score,
    required this.status,
    required this.confirmationChannel,
    this.confirmedAt,
    required this.deviceIntegrity,
    required this.integrityIssues,
    required this.flags,
    this.scoreComponents,
    this.clientVisitId,
    this.officerId,
    this.failureCode,
    this.failureDetail,
    required this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['farmer_id'] = Variable<String>(farmerId);
    if (!nullToAbsent || farmId != null) {
      map['farm_id'] = Variable<String>(farmId);
    }
    if (!nullToAbsent || villageId != null) {
      map['village_id'] = Variable<String>(villageId);
    }
    map['purpose'] = Variable<String>(purpose);
    map['checkin_at'] = Variable<DateTime>(checkinAt);
    map['checkin_lat'] = Variable<double>(checkinLat);
    map['checkin_lon'] = Variable<double>(checkinLon);
    if (!nullToAbsent || checkinAccuracyM != null) {
      map['checkin_accuracy_m'] = Variable<double>(checkinAccuracyM);
    }
    if (!nullToAbsent || checkoutAt != null) {
      map['checkout_at'] = Variable<DateTime>(checkoutAt);
    }
    if (!nullToAbsent || checkoutLat != null) {
      map['checkout_lat'] = Variable<double>(checkoutLat);
    }
    if (!nullToAbsent || checkoutLon != null) {
      map['checkout_lon'] = Variable<double>(checkoutLon);
    }
    if (!nullToAbsent || geofenceResult != null) {
      map['geofence_result'] = Variable<String>(geofenceResult);
    }
    if (!nullToAbsent || precheckResult != null) {
      map['precheck_result'] = Variable<String>(precheckResult);
    }
    if (!nullToAbsent || precheckDistanceM != null) {
      map['precheck_distance_m'] = Variable<double>(precheckDistanceM);
    }
    if (!nullToAbsent || precheckTarget != null) {
      map['precheck_target'] = Variable<String>(precheckTarget);
    }
    if (!nullToAbsent || precheckRadiusM != null) {
      map['precheck_radius_m'] = Variable<double>(precheckRadiusM);
    }
    if (!nullToAbsent || overrideNote != null) {
      map['override_note'] = Variable<String>(overrideNote);
    }
    if (!nullToAbsent || overrideApprovedBy != null) {
      map['override_approved_by'] = Variable<String>(overrideApprovedBy);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || cropStage != null) {
      map['crop_stage'] = Variable<String>(cropStage);
    }
    if (!nullToAbsent || durationS != null) {
      map['duration_s'] = Variable<int>(durationS);
    }
    if (!nullToAbsent || score != null) {
      map['score'] = Variable<int>(score);
    }
    map['status'] = Variable<String>(status);
    map['confirmation_channel'] = Variable<String>(confirmationChannel);
    if (!nullToAbsent || confirmedAt != null) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt);
    }
    map['device_integrity'] = Variable<String>(deviceIntegrity);
    map['integrity_issues'] = Variable<String>(integrityIssues);
    map['flags'] = Variable<String>(flags);
    if (!nullToAbsent || scoreComponents != null) {
      map['score_components'] = Variable<String>(scoreComponents);
    }
    if (!nullToAbsent || clientVisitId != null) {
      map['client_visit_id'] = Variable<String>(clientVisitId);
    }
    if (!nullToAbsent || officerId != null) {
      map['officer_id'] = Variable<String>(officerId);
    }
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    if (!nullToAbsent || failureDetail != null) {
      map['failure_detail'] = Variable<String>(failureDetail);
    }
    map['extra'] = Variable<String>(extra);
    return map;
  }

  VisitsCompanion toCompanion(bool nullToAbsent) {
    return VisitsCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      farmerId: Value(farmerId),
      farmId: farmId == null && nullToAbsent
          ? const Value.absent()
          : Value(farmId),
      villageId: villageId == null && nullToAbsent
          ? const Value.absent()
          : Value(villageId),
      purpose: Value(purpose),
      checkinAt: Value(checkinAt),
      checkinLat: Value(checkinLat),
      checkinLon: Value(checkinLon),
      checkinAccuracyM: checkinAccuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(checkinAccuracyM),
      checkoutAt: checkoutAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkoutAt),
      checkoutLat: checkoutLat == null && nullToAbsent
          ? const Value.absent()
          : Value(checkoutLat),
      checkoutLon: checkoutLon == null && nullToAbsent
          ? const Value.absent()
          : Value(checkoutLon),
      geofenceResult: geofenceResult == null && nullToAbsent
          ? const Value.absent()
          : Value(geofenceResult),
      precheckResult: precheckResult == null && nullToAbsent
          ? const Value.absent()
          : Value(precheckResult),
      precheckDistanceM: precheckDistanceM == null && nullToAbsent
          ? const Value.absent()
          : Value(precheckDistanceM),
      precheckTarget: precheckTarget == null && nullToAbsent
          ? const Value.absent()
          : Value(precheckTarget),
      precheckRadiusM: precheckRadiusM == null && nullToAbsent
          ? const Value.absent()
          : Value(precheckRadiusM),
      overrideNote: overrideNote == null && nullToAbsent
          ? const Value.absent()
          : Value(overrideNote),
      overrideApprovedBy: overrideApprovedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(overrideApprovedBy),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      cropStage: cropStage == null && nullToAbsent
          ? const Value.absent()
          : Value(cropStage),
      durationS: durationS == null && nullToAbsent
          ? const Value.absent()
          : Value(durationS),
      score: score == null && nullToAbsent
          ? const Value.absent()
          : Value(score),
      status: Value(status),
      confirmationChannel: Value(confirmationChannel),
      confirmedAt: confirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAt),
      deviceIntegrity: Value(deviceIntegrity),
      integrityIssues: Value(integrityIssues),
      flags: Value(flags),
      scoreComponents: scoreComponents == null && nullToAbsent
          ? const Value.absent()
          : Value(scoreComponents),
      clientVisitId: clientVisitId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientVisitId),
      officerId: officerId == null && nullToAbsent
          ? const Value.absent()
          : Value(officerId),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      failureDetail: failureDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(failureDetail),
      extra: Value(extra),
    );
  }

  factory Visit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Visit(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      farmerId: serializer.fromJson<String>(json['farmerId']),
      farmId: serializer.fromJson<String?>(json['farmId']),
      villageId: serializer.fromJson<String?>(json['villageId']),
      purpose: serializer.fromJson<String>(json['purpose']),
      checkinAt: serializer.fromJson<DateTime>(json['checkinAt']),
      checkinLat: serializer.fromJson<double>(json['checkinLat']),
      checkinLon: serializer.fromJson<double>(json['checkinLon']),
      checkinAccuracyM: serializer.fromJson<double?>(json['checkinAccuracyM']),
      checkoutAt: serializer.fromJson<DateTime?>(json['checkoutAt']),
      checkoutLat: serializer.fromJson<double?>(json['checkoutLat']),
      checkoutLon: serializer.fromJson<double?>(json['checkoutLon']),
      geofenceResult: serializer.fromJson<String?>(json['geofenceResult']),
      precheckResult: serializer.fromJson<String?>(json['precheckResult']),
      precheckDistanceM: serializer.fromJson<double?>(
        json['precheckDistanceM'],
      ),
      precheckTarget: serializer.fromJson<String?>(json['precheckTarget']),
      precheckRadiusM: serializer.fromJson<double?>(json['precheckRadiusM']),
      overrideNote: serializer.fromJson<String?>(json['overrideNote']),
      overrideApprovedBy: serializer.fromJson<String?>(
        json['overrideApprovedBy'],
      ),
      notes: serializer.fromJson<String?>(json['notes']),
      cropStage: serializer.fromJson<String?>(json['cropStage']),
      durationS: serializer.fromJson<int?>(json['durationS']),
      score: serializer.fromJson<int?>(json['score']),
      status: serializer.fromJson<String>(json['status']),
      confirmationChannel: serializer.fromJson<String>(
        json['confirmationChannel'],
      ),
      confirmedAt: serializer.fromJson<DateTime?>(json['confirmedAt']),
      deviceIntegrity: serializer.fromJson<String>(json['deviceIntegrity']),
      integrityIssues: serializer.fromJson<String>(json['integrityIssues']),
      flags: serializer.fromJson<String>(json['flags']),
      scoreComponents: serializer.fromJson<String?>(json['scoreComponents']),
      clientVisitId: serializer.fromJson<String?>(json['clientVisitId']),
      officerId: serializer.fromJson<String?>(json['officerId']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      failureDetail: serializer.fromJson<String?>(json['failureDetail']),
      extra: serializer.fromJson<String>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'farmerId': serializer.toJson<String>(farmerId),
      'farmId': serializer.toJson<String?>(farmId),
      'villageId': serializer.toJson<String?>(villageId),
      'purpose': serializer.toJson<String>(purpose),
      'checkinAt': serializer.toJson<DateTime>(checkinAt),
      'checkinLat': serializer.toJson<double>(checkinLat),
      'checkinLon': serializer.toJson<double>(checkinLon),
      'checkinAccuracyM': serializer.toJson<double?>(checkinAccuracyM),
      'checkoutAt': serializer.toJson<DateTime?>(checkoutAt),
      'checkoutLat': serializer.toJson<double?>(checkoutLat),
      'checkoutLon': serializer.toJson<double?>(checkoutLon),
      'geofenceResult': serializer.toJson<String?>(geofenceResult),
      'precheckResult': serializer.toJson<String?>(precheckResult),
      'precheckDistanceM': serializer.toJson<double?>(precheckDistanceM),
      'precheckTarget': serializer.toJson<String?>(precheckTarget),
      'precheckRadiusM': serializer.toJson<double?>(precheckRadiusM),
      'overrideNote': serializer.toJson<String?>(overrideNote),
      'overrideApprovedBy': serializer.toJson<String?>(overrideApprovedBy),
      'notes': serializer.toJson<String?>(notes),
      'cropStage': serializer.toJson<String?>(cropStage),
      'durationS': serializer.toJson<int?>(durationS),
      'score': serializer.toJson<int?>(score),
      'status': serializer.toJson<String>(status),
      'confirmationChannel': serializer.toJson<String>(confirmationChannel),
      'confirmedAt': serializer.toJson<DateTime?>(confirmedAt),
      'deviceIntegrity': serializer.toJson<String>(deviceIntegrity),
      'integrityIssues': serializer.toJson<String>(integrityIssues),
      'flags': serializer.toJson<String>(flags),
      'scoreComponents': serializer.toJson<String?>(scoreComponents),
      'clientVisitId': serializer.toJson<String?>(clientVisitId),
      'officerId': serializer.toJson<String?>(officerId),
      'failureCode': serializer.toJson<String?>(failureCode),
      'failureDetail': serializer.toJson<String?>(failureDetail),
      'extra': serializer.toJson<String>(extra),
    };
  }

  Visit copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    String? farmerId,
    Value<String?> farmId = const Value.absent(),
    Value<String?> villageId = const Value.absent(),
    String? purpose,
    DateTime? checkinAt,
    double? checkinLat,
    double? checkinLon,
    Value<double?> checkinAccuracyM = const Value.absent(),
    Value<DateTime?> checkoutAt = const Value.absent(),
    Value<double?> checkoutLat = const Value.absent(),
    Value<double?> checkoutLon = const Value.absent(),
    Value<String?> geofenceResult = const Value.absent(),
    Value<String?> precheckResult = const Value.absent(),
    Value<double?> precheckDistanceM = const Value.absent(),
    Value<String?> precheckTarget = const Value.absent(),
    Value<double?> precheckRadiusM = const Value.absent(),
    Value<String?> overrideNote = const Value.absent(),
    Value<String?> overrideApprovedBy = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> cropStage = const Value.absent(),
    Value<int?> durationS = const Value.absent(),
    Value<int?> score = const Value.absent(),
    String? status,
    String? confirmationChannel,
    Value<DateTime?> confirmedAt = const Value.absent(),
    String? deviceIntegrity,
    String? integrityIssues,
    String? flags,
    Value<String?> scoreComponents = const Value.absent(),
    Value<String?> clientVisitId = const Value.absent(),
    Value<String?> officerId = const Value.absent(),
    Value<String?> failureCode = const Value.absent(),
    Value<String?> failureDetail = const Value.absent(),
    String? extra,
  }) => Visit(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    farmerId: farmerId ?? this.farmerId,
    farmId: farmId.present ? farmId.value : this.farmId,
    villageId: villageId.present ? villageId.value : this.villageId,
    purpose: purpose ?? this.purpose,
    checkinAt: checkinAt ?? this.checkinAt,
    checkinLat: checkinLat ?? this.checkinLat,
    checkinLon: checkinLon ?? this.checkinLon,
    checkinAccuracyM: checkinAccuracyM.present
        ? checkinAccuracyM.value
        : this.checkinAccuracyM,
    checkoutAt: checkoutAt.present ? checkoutAt.value : this.checkoutAt,
    checkoutLat: checkoutLat.present ? checkoutLat.value : this.checkoutLat,
    checkoutLon: checkoutLon.present ? checkoutLon.value : this.checkoutLon,
    geofenceResult: geofenceResult.present
        ? geofenceResult.value
        : this.geofenceResult,
    precheckResult: precheckResult.present
        ? precheckResult.value
        : this.precheckResult,
    precheckDistanceM: precheckDistanceM.present
        ? precheckDistanceM.value
        : this.precheckDistanceM,
    precheckTarget: precheckTarget.present
        ? precheckTarget.value
        : this.precheckTarget,
    precheckRadiusM: precheckRadiusM.present
        ? precheckRadiusM.value
        : this.precheckRadiusM,
    overrideNote: overrideNote.present ? overrideNote.value : this.overrideNote,
    overrideApprovedBy: overrideApprovedBy.present
        ? overrideApprovedBy.value
        : this.overrideApprovedBy,
    notes: notes.present ? notes.value : this.notes,
    cropStage: cropStage.present ? cropStage.value : this.cropStage,
    durationS: durationS.present ? durationS.value : this.durationS,
    score: score.present ? score.value : this.score,
    status: status ?? this.status,
    confirmationChannel: confirmationChannel ?? this.confirmationChannel,
    confirmedAt: confirmedAt.present ? confirmedAt.value : this.confirmedAt,
    deviceIntegrity: deviceIntegrity ?? this.deviceIntegrity,
    integrityIssues: integrityIssues ?? this.integrityIssues,
    flags: flags ?? this.flags,
    scoreComponents: scoreComponents.present
        ? scoreComponents.value
        : this.scoreComponents,
    clientVisitId: clientVisitId.present
        ? clientVisitId.value
        : this.clientVisitId,
    officerId: officerId.present ? officerId.value : this.officerId,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    failureDetail: failureDetail.present
        ? failureDetail.value
        : this.failureDetail,
    extra: extra ?? this.extra,
  );
  Visit copyWithCompanion(VisitsCompanion data) {
    return Visit(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      farmerId: data.farmerId.present ? data.farmerId.value : this.farmerId,
      farmId: data.farmId.present ? data.farmId.value : this.farmId,
      villageId: data.villageId.present ? data.villageId.value : this.villageId,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      checkinAt: data.checkinAt.present ? data.checkinAt.value : this.checkinAt,
      checkinLat: data.checkinLat.present
          ? data.checkinLat.value
          : this.checkinLat,
      checkinLon: data.checkinLon.present
          ? data.checkinLon.value
          : this.checkinLon,
      checkinAccuracyM: data.checkinAccuracyM.present
          ? data.checkinAccuracyM.value
          : this.checkinAccuracyM,
      checkoutAt: data.checkoutAt.present
          ? data.checkoutAt.value
          : this.checkoutAt,
      checkoutLat: data.checkoutLat.present
          ? data.checkoutLat.value
          : this.checkoutLat,
      checkoutLon: data.checkoutLon.present
          ? data.checkoutLon.value
          : this.checkoutLon,
      geofenceResult: data.geofenceResult.present
          ? data.geofenceResult.value
          : this.geofenceResult,
      precheckResult: data.precheckResult.present
          ? data.precheckResult.value
          : this.precheckResult,
      precheckDistanceM: data.precheckDistanceM.present
          ? data.precheckDistanceM.value
          : this.precheckDistanceM,
      precheckTarget: data.precheckTarget.present
          ? data.precheckTarget.value
          : this.precheckTarget,
      precheckRadiusM: data.precheckRadiusM.present
          ? data.precheckRadiusM.value
          : this.precheckRadiusM,
      overrideNote: data.overrideNote.present
          ? data.overrideNote.value
          : this.overrideNote,
      overrideApprovedBy: data.overrideApprovedBy.present
          ? data.overrideApprovedBy.value
          : this.overrideApprovedBy,
      notes: data.notes.present ? data.notes.value : this.notes,
      cropStage: data.cropStage.present ? data.cropStage.value : this.cropStage,
      durationS: data.durationS.present ? data.durationS.value : this.durationS,
      score: data.score.present ? data.score.value : this.score,
      status: data.status.present ? data.status.value : this.status,
      confirmationChannel: data.confirmationChannel.present
          ? data.confirmationChannel.value
          : this.confirmationChannel,
      confirmedAt: data.confirmedAt.present
          ? data.confirmedAt.value
          : this.confirmedAt,
      deviceIntegrity: data.deviceIntegrity.present
          ? data.deviceIntegrity.value
          : this.deviceIntegrity,
      integrityIssues: data.integrityIssues.present
          ? data.integrityIssues.value
          : this.integrityIssues,
      flags: data.flags.present ? data.flags.value : this.flags,
      scoreComponents: data.scoreComponents.present
          ? data.scoreComponents.value
          : this.scoreComponents,
      clientVisitId: data.clientVisitId.present
          ? data.clientVisitId.value
          : this.clientVisitId,
      officerId: data.officerId.present ? data.officerId.value : this.officerId,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      failureDetail: data.failureDetail.present
          ? data.failureDetail.value
          : this.failureDetail,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Visit(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('farmId: $farmId, ')
          ..write('villageId: $villageId, ')
          ..write('purpose: $purpose, ')
          ..write('checkinAt: $checkinAt, ')
          ..write('checkinLat: $checkinLat, ')
          ..write('checkinLon: $checkinLon, ')
          ..write('checkinAccuracyM: $checkinAccuracyM, ')
          ..write('checkoutAt: $checkoutAt, ')
          ..write('checkoutLat: $checkoutLat, ')
          ..write('checkoutLon: $checkoutLon, ')
          ..write('geofenceResult: $geofenceResult, ')
          ..write('precheckResult: $precheckResult, ')
          ..write('precheckDistanceM: $precheckDistanceM, ')
          ..write('precheckTarget: $precheckTarget, ')
          ..write('precheckRadiusM: $precheckRadiusM, ')
          ..write('overrideNote: $overrideNote, ')
          ..write('overrideApprovedBy: $overrideApprovedBy, ')
          ..write('notes: $notes, ')
          ..write('cropStage: $cropStage, ')
          ..write('durationS: $durationS, ')
          ..write('score: $score, ')
          ..write('status: $status, ')
          ..write('confirmationChannel: $confirmationChannel, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('deviceIntegrity: $deviceIntegrity, ')
          ..write('integrityIssues: $integrityIssues, ')
          ..write('flags: $flags, ')
          ..write('scoreComponents: $scoreComponents, ')
          ..write('clientVisitId: $clientVisitId, ')
          ..write('officerId: $officerId, ')
          ..write('failureCode: $failureCode, ')
          ..write('failureDetail: $failureDetail, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    farmId,
    villageId,
    purpose,
    checkinAt,
    checkinLat,
    checkinLon,
    checkinAccuracyM,
    checkoutAt,
    checkoutLat,
    checkoutLon,
    geofenceResult,
    precheckResult,
    precheckDistanceM,
    precheckTarget,
    precheckRadiusM,
    overrideNote,
    overrideApprovedBy,
    notes,
    cropStage,
    durationS,
    score,
    status,
    confirmationChannel,
    confirmedAt,
    deviceIntegrity,
    integrityIssues,
    flags,
    scoreComponents,
    clientVisitId,
    officerId,
    failureCode,
    failureDetail,
    extra,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Visit &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.farmerId == this.farmerId &&
          other.farmId == this.farmId &&
          other.villageId == this.villageId &&
          other.purpose == this.purpose &&
          other.checkinAt == this.checkinAt &&
          other.checkinLat == this.checkinLat &&
          other.checkinLon == this.checkinLon &&
          other.checkinAccuracyM == this.checkinAccuracyM &&
          other.checkoutAt == this.checkoutAt &&
          other.checkoutLat == this.checkoutLat &&
          other.checkoutLon == this.checkoutLon &&
          other.geofenceResult == this.geofenceResult &&
          other.precheckResult == this.precheckResult &&
          other.precheckDistanceM == this.precheckDistanceM &&
          other.precheckTarget == this.precheckTarget &&
          other.precheckRadiusM == this.precheckRadiusM &&
          other.overrideNote == this.overrideNote &&
          other.overrideApprovedBy == this.overrideApprovedBy &&
          other.notes == this.notes &&
          other.cropStage == this.cropStage &&
          other.durationS == this.durationS &&
          other.score == this.score &&
          other.status == this.status &&
          other.confirmationChannel == this.confirmationChannel &&
          other.confirmedAt == this.confirmedAt &&
          other.deviceIntegrity == this.deviceIntegrity &&
          other.integrityIssues == this.integrityIssues &&
          other.flags == this.flags &&
          other.scoreComponents == this.scoreComponents &&
          other.clientVisitId == this.clientVisitId &&
          other.officerId == this.officerId &&
          other.failureCode == this.failureCode &&
          other.failureDetail == this.failureDetail &&
          other.extra == this.extra);
}

class VisitsCompanion extends UpdateCompanion<Visit> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String> farmerId;
  final Value<String?> farmId;
  final Value<String?> villageId;
  final Value<String> purpose;
  final Value<DateTime> checkinAt;
  final Value<double> checkinLat;
  final Value<double> checkinLon;
  final Value<double?> checkinAccuracyM;
  final Value<DateTime?> checkoutAt;
  final Value<double?> checkoutLat;
  final Value<double?> checkoutLon;
  final Value<String?> geofenceResult;
  final Value<String?> precheckResult;
  final Value<double?> precheckDistanceM;
  final Value<String?> precheckTarget;
  final Value<double?> precheckRadiusM;
  final Value<String?> overrideNote;
  final Value<String?> overrideApprovedBy;
  final Value<String?> notes;
  final Value<String?> cropStage;
  final Value<int?> durationS;
  final Value<int?> score;
  final Value<String> status;
  final Value<String> confirmationChannel;
  final Value<DateTime?> confirmedAt;
  final Value<String> deviceIntegrity;
  final Value<String> integrityIssues;
  final Value<String> flags;
  final Value<String?> scoreComponents;
  final Value<String?> clientVisitId;
  final Value<String?> officerId;
  final Value<String?> failureCode;
  final Value<String?> failureDetail;
  final Value<String> extra;
  final Value<int> rowid;
  const VisitsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.farmerId = const Value.absent(),
    this.farmId = const Value.absent(),
    this.villageId = const Value.absent(),
    this.purpose = const Value.absent(),
    this.checkinAt = const Value.absent(),
    this.checkinLat = const Value.absent(),
    this.checkinLon = const Value.absent(),
    this.checkinAccuracyM = const Value.absent(),
    this.checkoutAt = const Value.absent(),
    this.checkoutLat = const Value.absent(),
    this.checkoutLon = const Value.absent(),
    this.geofenceResult = const Value.absent(),
    this.precheckResult = const Value.absent(),
    this.precheckDistanceM = const Value.absent(),
    this.precheckTarget = const Value.absent(),
    this.precheckRadiusM = const Value.absent(),
    this.overrideNote = const Value.absent(),
    this.overrideApprovedBy = const Value.absent(),
    this.notes = const Value.absent(),
    this.cropStage = const Value.absent(),
    this.durationS = const Value.absent(),
    this.score = const Value.absent(),
    this.status = const Value.absent(),
    this.confirmationChannel = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.deviceIntegrity = const Value.absent(),
    this.integrityIssues = const Value.absent(),
    this.flags = const Value.absent(),
    this.scoreComponents = const Value.absent(),
    this.clientVisitId = const Value.absent(),
    this.officerId = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.failureDetail = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisitsCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required String farmerId,
    this.farmId = const Value.absent(),
    this.villageId = const Value.absent(),
    this.purpose = const Value.absent(),
    required DateTime checkinAt,
    required double checkinLat,
    required double checkinLon,
    this.checkinAccuracyM = const Value.absent(),
    this.checkoutAt = const Value.absent(),
    this.checkoutLat = const Value.absent(),
    this.checkoutLon = const Value.absent(),
    this.geofenceResult = const Value.absent(),
    this.precheckResult = const Value.absent(),
    this.precheckDistanceM = const Value.absent(),
    this.precheckTarget = const Value.absent(),
    this.precheckRadiusM = const Value.absent(),
    this.overrideNote = const Value.absent(),
    this.overrideApprovedBy = const Value.absent(),
    this.notes = const Value.absent(),
    this.cropStage = const Value.absent(),
    this.durationS = const Value.absent(),
    this.score = const Value.absent(),
    this.status = const Value.absent(),
    this.confirmationChannel = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.deviceIntegrity = const Value.absent(),
    this.integrityIssues = const Value.absent(),
    this.flags = const Value.absent(),
    this.scoreComponents = const Value.absent(),
    this.clientVisitId = const Value.absent(),
    this.officerId = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.failureDetail = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       farmerId = Value(farmerId),
       checkinAt = Value(checkinAt),
       checkinLat = Value(checkinLat),
       checkinLon = Value(checkinLon);
  static Insertable<Visit> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? farmerId,
    Expression<String>? farmId,
    Expression<String>? villageId,
    Expression<String>? purpose,
    Expression<DateTime>? checkinAt,
    Expression<double>? checkinLat,
    Expression<double>? checkinLon,
    Expression<double>? checkinAccuracyM,
    Expression<DateTime>? checkoutAt,
    Expression<double>? checkoutLat,
    Expression<double>? checkoutLon,
    Expression<String>? geofenceResult,
    Expression<String>? precheckResult,
    Expression<double>? precheckDistanceM,
    Expression<String>? precheckTarget,
    Expression<double>? precheckRadiusM,
    Expression<String>? overrideNote,
    Expression<String>? overrideApprovedBy,
    Expression<String>? notes,
    Expression<String>? cropStage,
    Expression<int>? durationS,
    Expression<int>? score,
    Expression<String>? status,
    Expression<String>? confirmationChannel,
    Expression<DateTime>? confirmedAt,
    Expression<String>? deviceIntegrity,
    Expression<String>? integrityIssues,
    Expression<String>? flags,
    Expression<String>? scoreComponents,
    Expression<String>? clientVisitId,
    Expression<String>? officerId,
    Expression<String>? failureCode,
    Expression<String>? failureDetail,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (farmerId != null) 'farmer_id': farmerId,
      if (farmId != null) 'farm_id': farmId,
      if (villageId != null) 'village_id': villageId,
      if (purpose != null) 'purpose': purpose,
      if (checkinAt != null) 'checkin_at': checkinAt,
      if (checkinLat != null) 'checkin_lat': checkinLat,
      if (checkinLon != null) 'checkin_lon': checkinLon,
      if (checkinAccuracyM != null) 'checkin_accuracy_m': checkinAccuracyM,
      if (checkoutAt != null) 'checkout_at': checkoutAt,
      if (checkoutLat != null) 'checkout_lat': checkoutLat,
      if (checkoutLon != null) 'checkout_lon': checkoutLon,
      if (geofenceResult != null) 'geofence_result': geofenceResult,
      if (precheckResult != null) 'precheck_result': precheckResult,
      if (precheckDistanceM != null) 'precheck_distance_m': precheckDistanceM,
      if (precheckTarget != null) 'precheck_target': precheckTarget,
      if (precheckRadiusM != null) 'precheck_radius_m': precheckRadiusM,
      if (overrideNote != null) 'override_note': overrideNote,
      if (overrideApprovedBy != null)
        'override_approved_by': overrideApprovedBy,
      if (notes != null) 'notes': notes,
      if (cropStage != null) 'crop_stage': cropStage,
      if (durationS != null) 'duration_s': durationS,
      if (score != null) 'score': score,
      if (status != null) 'status': status,
      if (confirmationChannel != null)
        'confirmation_channel': confirmationChannel,
      if (confirmedAt != null) 'confirmed_at': confirmedAt,
      if (deviceIntegrity != null) 'device_integrity': deviceIntegrity,
      if (integrityIssues != null) 'integrity_issues': integrityIssues,
      if (flags != null) 'flags': flags,
      if (scoreComponents != null) 'score_components': scoreComponents,
      if (clientVisitId != null) 'client_visit_id': clientVisitId,
      if (officerId != null) 'officer_id': officerId,
      if (failureCode != null) 'failure_code': failureCode,
      if (failureDetail != null) 'failure_detail': failureDetail,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisitsCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String>? farmerId,
    Value<String?>? farmId,
    Value<String?>? villageId,
    Value<String>? purpose,
    Value<DateTime>? checkinAt,
    Value<double>? checkinLat,
    Value<double>? checkinLon,
    Value<double?>? checkinAccuracyM,
    Value<DateTime?>? checkoutAt,
    Value<double?>? checkoutLat,
    Value<double?>? checkoutLon,
    Value<String?>? geofenceResult,
    Value<String?>? precheckResult,
    Value<double?>? precheckDistanceM,
    Value<String?>? precheckTarget,
    Value<double?>? precheckRadiusM,
    Value<String?>? overrideNote,
    Value<String?>? overrideApprovedBy,
    Value<String?>? notes,
    Value<String?>? cropStage,
    Value<int?>? durationS,
    Value<int?>? score,
    Value<String>? status,
    Value<String>? confirmationChannel,
    Value<DateTime?>? confirmedAt,
    Value<String>? deviceIntegrity,
    Value<String>? integrityIssues,
    Value<String>? flags,
    Value<String?>? scoreComponents,
    Value<String?>? clientVisitId,
    Value<String?>? officerId,
    Value<String?>? failureCode,
    Value<String?>? failureDetail,
    Value<String>? extra,
    Value<int>? rowid,
  }) {
    return VisitsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      farmerId: farmerId ?? this.farmerId,
      farmId: farmId ?? this.farmId,
      villageId: villageId ?? this.villageId,
      purpose: purpose ?? this.purpose,
      checkinAt: checkinAt ?? this.checkinAt,
      checkinLat: checkinLat ?? this.checkinLat,
      checkinLon: checkinLon ?? this.checkinLon,
      checkinAccuracyM: checkinAccuracyM ?? this.checkinAccuracyM,
      checkoutAt: checkoutAt ?? this.checkoutAt,
      checkoutLat: checkoutLat ?? this.checkoutLat,
      checkoutLon: checkoutLon ?? this.checkoutLon,
      geofenceResult: geofenceResult ?? this.geofenceResult,
      precheckResult: precheckResult ?? this.precheckResult,
      precheckDistanceM: precheckDistanceM ?? this.precheckDistanceM,
      precheckTarget: precheckTarget ?? this.precheckTarget,
      precheckRadiusM: precheckRadiusM ?? this.precheckRadiusM,
      overrideNote: overrideNote ?? this.overrideNote,
      overrideApprovedBy: overrideApprovedBy ?? this.overrideApprovedBy,
      notes: notes ?? this.notes,
      cropStage: cropStage ?? this.cropStage,
      durationS: durationS ?? this.durationS,
      score: score ?? this.score,
      status: status ?? this.status,
      confirmationChannel: confirmationChannel ?? this.confirmationChannel,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      deviceIntegrity: deviceIntegrity ?? this.deviceIntegrity,
      integrityIssues: integrityIssues ?? this.integrityIssues,
      flags: flags ?? this.flags,
      scoreComponents: scoreComponents ?? this.scoreComponents,
      clientVisitId: clientVisitId ?? this.clientVisitId,
      officerId: officerId ?? this.officerId,
      failureCode: failureCode ?? this.failureCode,
      failureDetail: failureDetail ?? this.failureDetail,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (farmerId.present) {
      map['farmer_id'] = Variable<String>(farmerId.value);
    }
    if (farmId.present) {
      map['farm_id'] = Variable<String>(farmId.value);
    }
    if (villageId.present) {
      map['village_id'] = Variable<String>(villageId.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (checkinAt.present) {
      map['checkin_at'] = Variable<DateTime>(checkinAt.value);
    }
    if (checkinLat.present) {
      map['checkin_lat'] = Variable<double>(checkinLat.value);
    }
    if (checkinLon.present) {
      map['checkin_lon'] = Variable<double>(checkinLon.value);
    }
    if (checkinAccuracyM.present) {
      map['checkin_accuracy_m'] = Variable<double>(checkinAccuracyM.value);
    }
    if (checkoutAt.present) {
      map['checkout_at'] = Variable<DateTime>(checkoutAt.value);
    }
    if (checkoutLat.present) {
      map['checkout_lat'] = Variable<double>(checkoutLat.value);
    }
    if (checkoutLon.present) {
      map['checkout_lon'] = Variable<double>(checkoutLon.value);
    }
    if (geofenceResult.present) {
      map['geofence_result'] = Variable<String>(geofenceResult.value);
    }
    if (precheckResult.present) {
      map['precheck_result'] = Variable<String>(precheckResult.value);
    }
    if (precheckDistanceM.present) {
      map['precheck_distance_m'] = Variable<double>(precheckDistanceM.value);
    }
    if (precheckTarget.present) {
      map['precheck_target'] = Variable<String>(precheckTarget.value);
    }
    if (precheckRadiusM.present) {
      map['precheck_radius_m'] = Variable<double>(precheckRadiusM.value);
    }
    if (overrideNote.present) {
      map['override_note'] = Variable<String>(overrideNote.value);
    }
    if (overrideApprovedBy.present) {
      map['override_approved_by'] = Variable<String>(overrideApprovedBy.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (cropStage.present) {
      map['crop_stage'] = Variable<String>(cropStage.value);
    }
    if (durationS.present) {
      map['duration_s'] = Variable<int>(durationS.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (confirmationChannel.present) {
      map['confirmation_channel'] = Variable<String>(confirmationChannel.value);
    }
    if (confirmedAt.present) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt.value);
    }
    if (deviceIntegrity.present) {
      map['device_integrity'] = Variable<String>(deviceIntegrity.value);
    }
    if (integrityIssues.present) {
      map['integrity_issues'] = Variable<String>(integrityIssues.value);
    }
    if (flags.present) {
      map['flags'] = Variable<String>(flags.value);
    }
    if (scoreComponents.present) {
      map['score_components'] = Variable<String>(scoreComponents.value);
    }
    if (clientVisitId.present) {
      map['client_visit_id'] = Variable<String>(clientVisitId.value);
    }
    if (officerId.present) {
      map['officer_id'] = Variable<String>(officerId.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (failureDetail.present) {
      map['failure_detail'] = Variable<String>(failureDetail.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisitsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('farmId: $farmId, ')
          ..write('villageId: $villageId, ')
          ..write('purpose: $purpose, ')
          ..write('checkinAt: $checkinAt, ')
          ..write('checkinLat: $checkinLat, ')
          ..write('checkinLon: $checkinLon, ')
          ..write('checkinAccuracyM: $checkinAccuracyM, ')
          ..write('checkoutAt: $checkoutAt, ')
          ..write('checkoutLat: $checkoutLat, ')
          ..write('checkoutLon: $checkoutLon, ')
          ..write('geofenceResult: $geofenceResult, ')
          ..write('precheckResult: $precheckResult, ')
          ..write('precheckDistanceM: $precheckDistanceM, ')
          ..write('precheckTarget: $precheckTarget, ')
          ..write('precheckRadiusM: $precheckRadiusM, ')
          ..write('overrideNote: $overrideNote, ')
          ..write('overrideApprovedBy: $overrideApprovedBy, ')
          ..write('notes: $notes, ')
          ..write('cropStage: $cropStage, ')
          ..write('durationS: $durationS, ')
          ..write('score: $score, ')
          ..write('status: $status, ')
          ..write('confirmationChannel: $confirmationChannel, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('deviceIntegrity: $deviceIntegrity, ')
          ..write('integrityIssues: $integrityIssues, ')
          ..write('flags: $flags, ')
          ..write('scoreComponents: $scoreComponents, ')
          ..write('clientVisitId: $clientVisitId, ')
          ..write('officerId: $officerId, ')
          ..write('failureCode: $failureCode, ')
          ..write('failureDetail: $failureDetail, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisitPhotosTable extends VisitPhotos
    with TableInfo<$VisitPhotosTable, VisitPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisitPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _visitIdMeta = const VerificationMeta(
    'visitId',
  );
  @override
  late final GeneratedColumn<String> visitId = GeneratedColumn<String>(
    'visit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blobUriMeta = const VerificationMeta(
    'blobUri',
  );
  @override
  late final GeneratedColumn<String> blobUri = GeneratedColumn<String>(
    'blob_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _phashMeta = const VerificationMeta('phash');
  @override
  late final GeneratedColumn<String> phash = GeneratedColumn<String>(
    'phash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exifTimeMeta = const VerificationMeta(
    'exifTime',
  );
  @override
  late final GeneratedColumn<DateTime> exifTime = GeneratedColumn<DateTime>(
    'exif_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exifLatMeta = const VerificationMeta(
    'exifLat',
  );
  @override
  late final GeneratedColumn<double> exifLat = GeneratedColumn<double>(
    'exif_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exifLonMeta = const VerificationMeta(
    'exifLon',
  );
  @override
  late final GeneratedColumn<double> exifLon = GeneratedColumn<double>(
    'exif_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takenInAppMeta = const VerificationMeta(
    'takenInApp',
  );
  @override
  late final GeneratedColumn<bool> takenInApp = GeneratedColumn<bool>(
    'taken_in_app',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("taken_in_app" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _deviceTimeMeta = const VerificationMeta(
    'deviceTime',
  );
  @override
  late final GeneratedColumn<DateTime> deviceTime = GeneratedColumn<DateTime>(
    'device_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverTimeMeta = const VerificationMeta(
    'serverTime',
  );
  @override
  late final GeneratedColumn<DateTime> serverTime = GeneratedColumn<DateTime>(
    'server_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _photoFlagsMeta = const VerificationMeta(
    'photoFlags',
  );
  @override
  late final GeneratedColumn<String> photoFlags = GeneratedColumn<String>(
    'photo_flags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    visitId,
    blobUri,
    sha256,
    phash,
    exifTime,
    exifLat,
    exifLon,
    takenInApp,
    deviceTime,
    serverTime,
    photoFlags,
    localPath,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visit_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisitPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('visit_id')) {
      context.handle(
        _visitIdMeta,
        visitId.isAcceptableOrUnknown(data['visit_id']!, _visitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_visitIdMeta);
    }
    if (data.containsKey('blob_uri')) {
      context.handle(
        _blobUriMeta,
        blobUri.isAcceptableOrUnknown(data['blob_uri']!, _blobUriMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('phash')) {
      context.handle(
        _phashMeta,
        phash.isAcceptableOrUnknown(data['phash']!, _phashMeta),
      );
    }
    if (data.containsKey('exif_time')) {
      context.handle(
        _exifTimeMeta,
        exifTime.isAcceptableOrUnknown(data['exif_time']!, _exifTimeMeta),
      );
    }
    if (data.containsKey('exif_lat')) {
      context.handle(
        _exifLatMeta,
        exifLat.isAcceptableOrUnknown(data['exif_lat']!, _exifLatMeta),
      );
    }
    if (data.containsKey('exif_lon')) {
      context.handle(
        _exifLonMeta,
        exifLon.isAcceptableOrUnknown(data['exif_lon']!, _exifLonMeta),
      );
    }
    if (data.containsKey('taken_in_app')) {
      context.handle(
        _takenInAppMeta,
        takenInApp.isAcceptableOrUnknown(
          data['taken_in_app']!,
          _takenInAppMeta,
        ),
      );
    }
    if (data.containsKey('device_time')) {
      context.handle(
        _deviceTimeMeta,
        deviceTime.isAcceptableOrUnknown(data['device_time']!, _deviceTimeMeta),
      );
    }
    if (data.containsKey('server_time')) {
      context.handle(
        _serverTimeMeta,
        serverTime.isAcceptableOrUnknown(data['server_time']!, _serverTimeMeta),
      );
    }
    if (data.containsKey('photo_flags')) {
      context.handle(
        _photoFlagsMeta,
        photoFlags.isAcceptableOrUnknown(data['photo_flags']!, _photoFlagsMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisitPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisitPhoto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      visitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}visit_id'],
      )!,
      blobUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blob_uri'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      phash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phash'],
      ),
      exifTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}exif_time'],
      ),
      exifLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}exif_lat'],
      ),
      exifLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}exif_lon'],
      ),
      takenInApp: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}taken_in_app'],
      )!,
      deviceTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}device_time'],
      ),
      serverTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_time'],
      ),
      photoFlags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}photo_flags'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      )!,
    );
  }

  @override
  $VisitPhotosTable createAlias(String alias) {
    return $VisitPhotosTable(attachedDatabase, alias);
  }
}

class VisitPhoto extends DataClass implements Insertable<VisitPhoto> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Owning visit.
  final String visitId;

  /// Server blob URI, or the `upload:<id>` placeholder while queued.
  final String blobUri;

  /// Hex SHA-256 of the processed JPEG.
  final String? sha256;

  /// Server perceptual hash.
  final String? phash;

  /// EXIF capture time (UTC).
  final DateTime? exifTime;

  /// EXIF GPS latitude.
  final double? exifLat;

  /// EXIF GPS longitude.
  final double? exifLon;

  /// Always true on this device (no gallery path exists).
  final bool takenInApp;

  /// Device time at capture (UTC).
  final DateTime? deviceTime;

  /// Server receive time.
  final DateTime? serverTime;

  /// JSON list of VA-E08 flags from the server.
  final String photoFlags;

  /// Local file of the processed photo (thumbnail).
  final String? localPath;

  /// JSON of server fields this app does not model.
  final String extra;
  const VisitPhoto({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    required this.visitId,
    required this.blobUri,
    this.sha256,
    this.phash,
    this.exifTime,
    this.exifLat,
    this.exifLon,
    required this.takenInApp,
    this.deviceTime,
    this.serverTime,
    required this.photoFlags,
    this.localPath,
    required this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['visit_id'] = Variable<String>(visitId);
    map['blob_uri'] = Variable<String>(blobUri);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    if (!nullToAbsent || phash != null) {
      map['phash'] = Variable<String>(phash);
    }
    if (!nullToAbsent || exifTime != null) {
      map['exif_time'] = Variable<DateTime>(exifTime);
    }
    if (!nullToAbsent || exifLat != null) {
      map['exif_lat'] = Variable<double>(exifLat);
    }
    if (!nullToAbsent || exifLon != null) {
      map['exif_lon'] = Variable<double>(exifLon);
    }
    map['taken_in_app'] = Variable<bool>(takenInApp);
    if (!nullToAbsent || deviceTime != null) {
      map['device_time'] = Variable<DateTime>(deviceTime);
    }
    if (!nullToAbsent || serverTime != null) {
      map['server_time'] = Variable<DateTime>(serverTime);
    }
    map['photo_flags'] = Variable<String>(photoFlags);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    map['extra'] = Variable<String>(extra);
    return map;
  }

  VisitPhotosCompanion toCompanion(bool nullToAbsent) {
    return VisitPhotosCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      visitId: Value(visitId),
      blobUri: Value(blobUri),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      phash: phash == null && nullToAbsent
          ? const Value.absent()
          : Value(phash),
      exifTime: exifTime == null && nullToAbsent
          ? const Value.absent()
          : Value(exifTime),
      exifLat: exifLat == null && nullToAbsent
          ? const Value.absent()
          : Value(exifLat),
      exifLon: exifLon == null && nullToAbsent
          ? const Value.absent()
          : Value(exifLon),
      takenInApp: Value(takenInApp),
      deviceTime: deviceTime == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceTime),
      serverTime: serverTime == null && nullToAbsent
          ? const Value.absent()
          : Value(serverTime),
      photoFlags: Value(photoFlags),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      extra: Value(extra),
    );
  }

  factory VisitPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisitPhoto(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      visitId: serializer.fromJson<String>(json['visitId']),
      blobUri: serializer.fromJson<String>(json['blobUri']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      phash: serializer.fromJson<String?>(json['phash']),
      exifTime: serializer.fromJson<DateTime?>(json['exifTime']),
      exifLat: serializer.fromJson<double?>(json['exifLat']),
      exifLon: serializer.fromJson<double?>(json['exifLon']),
      takenInApp: serializer.fromJson<bool>(json['takenInApp']),
      deviceTime: serializer.fromJson<DateTime?>(json['deviceTime']),
      serverTime: serializer.fromJson<DateTime?>(json['serverTime']),
      photoFlags: serializer.fromJson<String>(json['photoFlags']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      extra: serializer.fromJson<String>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'visitId': serializer.toJson<String>(visitId),
      'blobUri': serializer.toJson<String>(blobUri),
      'sha256': serializer.toJson<String?>(sha256),
      'phash': serializer.toJson<String?>(phash),
      'exifTime': serializer.toJson<DateTime?>(exifTime),
      'exifLat': serializer.toJson<double?>(exifLat),
      'exifLon': serializer.toJson<double?>(exifLon),
      'takenInApp': serializer.toJson<bool>(takenInApp),
      'deviceTime': serializer.toJson<DateTime?>(deviceTime),
      'serverTime': serializer.toJson<DateTime?>(serverTime),
      'photoFlags': serializer.toJson<String>(photoFlags),
      'localPath': serializer.toJson<String?>(localPath),
      'extra': serializer.toJson<String>(extra),
    };
  }

  VisitPhoto copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    String? visitId,
    String? blobUri,
    Value<String?> sha256 = const Value.absent(),
    Value<String?> phash = const Value.absent(),
    Value<DateTime?> exifTime = const Value.absent(),
    Value<double?> exifLat = const Value.absent(),
    Value<double?> exifLon = const Value.absent(),
    bool? takenInApp,
    Value<DateTime?> deviceTime = const Value.absent(),
    Value<DateTime?> serverTime = const Value.absent(),
    String? photoFlags,
    Value<String?> localPath = const Value.absent(),
    String? extra,
  }) => VisitPhoto(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    visitId: visitId ?? this.visitId,
    blobUri: blobUri ?? this.blobUri,
    sha256: sha256.present ? sha256.value : this.sha256,
    phash: phash.present ? phash.value : this.phash,
    exifTime: exifTime.present ? exifTime.value : this.exifTime,
    exifLat: exifLat.present ? exifLat.value : this.exifLat,
    exifLon: exifLon.present ? exifLon.value : this.exifLon,
    takenInApp: takenInApp ?? this.takenInApp,
    deviceTime: deviceTime.present ? deviceTime.value : this.deviceTime,
    serverTime: serverTime.present ? serverTime.value : this.serverTime,
    photoFlags: photoFlags ?? this.photoFlags,
    localPath: localPath.present ? localPath.value : this.localPath,
    extra: extra ?? this.extra,
  );
  VisitPhoto copyWithCompanion(VisitPhotosCompanion data) {
    return VisitPhoto(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      visitId: data.visitId.present ? data.visitId.value : this.visitId,
      blobUri: data.blobUri.present ? data.blobUri.value : this.blobUri,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      phash: data.phash.present ? data.phash.value : this.phash,
      exifTime: data.exifTime.present ? data.exifTime.value : this.exifTime,
      exifLat: data.exifLat.present ? data.exifLat.value : this.exifLat,
      exifLon: data.exifLon.present ? data.exifLon.value : this.exifLon,
      takenInApp: data.takenInApp.present
          ? data.takenInApp.value
          : this.takenInApp,
      deviceTime: data.deviceTime.present
          ? data.deviceTime.value
          : this.deviceTime,
      serverTime: data.serverTime.present
          ? data.serverTime.value
          : this.serverTime,
      photoFlags: data.photoFlags.present
          ? data.photoFlags.value
          : this.photoFlags,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisitPhoto(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('visitId: $visitId, ')
          ..write('blobUri: $blobUri, ')
          ..write('sha256: $sha256, ')
          ..write('phash: $phash, ')
          ..write('exifTime: $exifTime, ')
          ..write('exifLat: $exifLat, ')
          ..write('exifLon: $exifLon, ')
          ..write('takenInApp: $takenInApp, ')
          ..write('deviceTime: $deviceTime, ')
          ..write('serverTime: $serverTime, ')
          ..write('photoFlags: $photoFlags, ')
          ..write('localPath: $localPath, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    visitId,
    blobUri,
    sha256,
    phash,
    exifTime,
    exifLat,
    exifLon,
    takenInApp,
    deviceTime,
    serverTime,
    photoFlags,
    localPath,
    extra,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisitPhoto &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.visitId == this.visitId &&
          other.blobUri == this.blobUri &&
          other.sha256 == this.sha256 &&
          other.phash == this.phash &&
          other.exifTime == this.exifTime &&
          other.exifLat == this.exifLat &&
          other.exifLon == this.exifLon &&
          other.takenInApp == this.takenInApp &&
          other.deviceTime == this.deviceTime &&
          other.serverTime == this.serverTime &&
          other.photoFlags == this.photoFlags &&
          other.localPath == this.localPath &&
          other.extra == this.extra);
}

class VisitPhotosCompanion extends UpdateCompanion<VisitPhoto> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String> visitId;
  final Value<String> blobUri;
  final Value<String?> sha256;
  final Value<String?> phash;
  final Value<DateTime?> exifTime;
  final Value<double?> exifLat;
  final Value<double?> exifLon;
  final Value<bool> takenInApp;
  final Value<DateTime?> deviceTime;
  final Value<DateTime?> serverTime;
  final Value<String> photoFlags;
  final Value<String?> localPath;
  final Value<String> extra;
  final Value<int> rowid;
  const VisitPhotosCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.visitId = const Value.absent(),
    this.blobUri = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.phash = const Value.absent(),
    this.exifTime = const Value.absent(),
    this.exifLat = const Value.absent(),
    this.exifLon = const Value.absent(),
    this.takenInApp = const Value.absent(),
    this.deviceTime = const Value.absent(),
    this.serverTime = const Value.absent(),
    this.photoFlags = const Value.absent(),
    this.localPath = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisitPhotosCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required String visitId,
    this.blobUri = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.phash = const Value.absent(),
    this.exifTime = const Value.absent(),
    this.exifLat = const Value.absent(),
    this.exifLon = const Value.absent(),
    this.takenInApp = const Value.absent(),
    this.deviceTime = const Value.absent(),
    this.serverTime = const Value.absent(),
    this.photoFlags = const Value.absent(),
    this.localPath = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       visitId = Value(visitId);
  static Insertable<VisitPhoto> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? visitId,
    Expression<String>? blobUri,
    Expression<String>? sha256,
    Expression<String>? phash,
    Expression<DateTime>? exifTime,
    Expression<double>? exifLat,
    Expression<double>? exifLon,
    Expression<bool>? takenInApp,
    Expression<DateTime>? deviceTime,
    Expression<DateTime>? serverTime,
    Expression<String>? photoFlags,
    Expression<String>? localPath,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (visitId != null) 'visit_id': visitId,
      if (blobUri != null) 'blob_uri': blobUri,
      if (sha256 != null) 'sha256': sha256,
      if (phash != null) 'phash': phash,
      if (exifTime != null) 'exif_time': exifTime,
      if (exifLat != null) 'exif_lat': exifLat,
      if (exifLon != null) 'exif_lon': exifLon,
      if (takenInApp != null) 'taken_in_app': takenInApp,
      if (deviceTime != null) 'device_time': deviceTime,
      if (serverTime != null) 'server_time': serverTime,
      if (photoFlags != null) 'photo_flags': photoFlags,
      if (localPath != null) 'local_path': localPath,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisitPhotosCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String>? visitId,
    Value<String>? blobUri,
    Value<String?>? sha256,
    Value<String?>? phash,
    Value<DateTime?>? exifTime,
    Value<double?>? exifLat,
    Value<double?>? exifLon,
    Value<bool>? takenInApp,
    Value<DateTime?>? deviceTime,
    Value<DateTime?>? serverTime,
    Value<String>? photoFlags,
    Value<String?>? localPath,
    Value<String>? extra,
    Value<int>? rowid,
  }) {
    return VisitPhotosCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      visitId: visitId ?? this.visitId,
      blobUri: blobUri ?? this.blobUri,
      sha256: sha256 ?? this.sha256,
      phash: phash ?? this.phash,
      exifTime: exifTime ?? this.exifTime,
      exifLat: exifLat ?? this.exifLat,
      exifLon: exifLon ?? this.exifLon,
      takenInApp: takenInApp ?? this.takenInApp,
      deviceTime: deviceTime ?? this.deviceTime,
      serverTime: serverTime ?? this.serverTime,
      photoFlags: photoFlags ?? this.photoFlags,
      localPath: localPath ?? this.localPath,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (visitId.present) {
      map['visit_id'] = Variable<String>(visitId.value);
    }
    if (blobUri.present) {
      map['blob_uri'] = Variable<String>(blobUri.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (phash.present) {
      map['phash'] = Variable<String>(phash.value);
    }
    if (exifTime.present) {
      map['exif_time'] = Variable<DateTime>(exifTime.value);
    }
    if (exifLat.present) {
      map['exif_lat'] = Variable<double>(exifLat.value);
    }
    if (exifLon.present) {
      map['exif_lon'] = Variable<double>(exifLon.value);
    }
    if (takenInApp.present) {
      map['taken_in_app'] = Variable<bool>(takenInApp.value);
    }
    if (deviceTime.present) {
      map['device_time'] = Variable<DateTime>(deviceTime.value);
    }
    if (serverTime.present) {
      map['server_time'] = Variable<DateTime>(serverTime.value);
    }
    if (photoFlags.present) {
      map['photo_flags'] = Variable<String>(photoFlags.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisitPhotosCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('visitId: $visitId, ')
          ..write('blobUri: $blobUri, ')
          ..write('sha256: $sha256, ')
          ..write('phash: $phash, ')
          ..write('exifTime: $exifTime, ')
          ..write('exifLat: $exifLat, ')
          ..write('exifLon: $exifLon, ')
          ..write('takenInApp: $takenInApp, ')
          ..write('deviceTime: $deviceTime, ')
          ..write('serverTime: $serverTime, ')
          ..write('photoFlags: $photoFlags, ')
          ..write('localPath: $localPath, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisitConfirmationsTable extends VisitConfirmations
    with TableInfo<$VisitConfirmationsTable, VisitConfirmation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisitConfirmationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _visitIdMeta = const VerificationMeta(
    'visitId',
  );
  @override
  late final GeneratedColumn<String> visitId = GeneratedColumn<String>(
    'visit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _requestedAtMeta = const VerificationMeta(
    'requestedAt',
  );
  @override
  late final GeneratedColumn<DateTime> requestedAt = GeneratedColumn<DateTime>(
    'requested_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confirmedAtMeta = const VerificationMeta(
    'confirmedAt',
  );
  @override
  late final GeneratedColumn<DateTime> confirmedAt = GeneratedColumn<DateTime>(
    'confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _farmerPhoneLast4Meta = const VerificationMeta(
    'farmerPhoneLast4',
  );
  @override
  late final GeneratedColumn<String> farmerPhoneLast4 = GeneratedColumn<String>(
    'farmer_phone_last4',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
    'token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    visitId,
    channel,
    status,
    requestedAt,
    expiresAt,
    confirmedAt,
    farmerPhoneLast4,
    rating,
    token,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visit_confirmations';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisitConfirmation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('visit_id')) {
      context.handle(
        _visitIdMeta,
        visitId.isAcceptableOrUnknown(data['visit_id']!, _visitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_visitIdMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('requested_at')) {
      context.handle(
        _requestedAtMeta,
        requestedAt.isAcceptableOrUnknown(
          data['requested_at']!,
          _requestedAtMeta,
        ),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('confirmed_at')) {
      context.handle(
        _confirmedAtMeta,
        confirmedAt.isAcceptableOrUnknown(
          data['confirmed_at']!,
          _confirmedAtMeta,
        ),
      );
    }
    if (data.containsKey('farmer_phone_last4')) {
      context.handle(
        _farmerPhoneLast4Meta,
        farmerPhoneLast4.isAcceptableOrUnknown(
          data['farmer_phone_last4']!,
          _farmerPhoneLast4Meta,
        ),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('token')) {
      context.handle(
        _tokenMeta,
        token.isAcceptableOrUnknown(data['token']!, _tokenMeta),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisitConfirmation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisitConfirmation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      visitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}visit_id'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      requestedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}requested_at'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      confirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}confirmed_at'],
      ),
      farmerPhoneLast4: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farmer_phone_last4'],
      ),
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
      token: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token'],
      ),
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      )!,
    );
  }

  @override
  $VisitConfirmationsTable createAlias(String alias) {
    return $VisitConfirmationsTable(attachedDatabase, alias);
  }
}

class VisitConfirmation extends DataClass
    implements Insertable<VisitConfirmation> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Owning visit.
  final String visitId;

  /// `sms_otp` | `app_push` | `qr`.
  final String channel;

  /// `pending` | `confirmed` | `expired` (server) | `queued` (local:
  /// requested offline, sent when online).
  final String status;

  /// When the request was made.
  final DateTime? requestedAt;

  /// When the code / token lapses.
  final DateTime? expiresAt;

  /// Server-owned confirmation time.
  final DateTime? confirmedAt;

  /// Last four digits of the farmer phone the OTP went to.
  final String? farmerPhoneLast4;

  /// FM-011 rating, once the farmer gave one.
  final int? rating;

  /// Signed QR token to render (local only; never sent back).
  final String? token;

  /// JSON of server fields this app does not model.
  final String extra;
  const VisitConfirmation({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    required this.visitId,
    required this.channel,
    required this.status,
    this.requestedAt,
    this.expiresAt,
    this.confirmedAt,
    this.farmerPhoneLast4,
    this.rating,
    this.token,
    required this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    map['visit_id'] = Variable<String>(visitId);
    map['channel'] = Variable<String>(channel);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || requestedAt != null) {
      map['requested_at'] = Variable<DateTime>(requestedAt);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || confirmedAt != null) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt);
    }
    if (!nullToAbsent || farmerPhoneLast4 != null) {
      map['farmer_phone_last4'] = Variable<String>(farmerPhoneLast4);
    }
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    if (!nullToAbsent || token != null) {
      map['token'] = Variable<String>(token);
    }
    map['extra'] = Variable<String>(extra);
    return map;
  }

  VisitConfirmationsCompanion toCompanion(bool nullToAbsent) {
    return VisitConfirmationsCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      visitId: Value(visitId),
      channel: Value(channel),
      status: Value(status),
      requestedAt: requestedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(requestedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      confirmedAt: confirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(confirmedAt),
      farmerPhoneLast4: farmerPhoneLast4 == null && nullToAbsent
          ? const Value.absent()
          : Value(farmerPhoneLast4),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      token: token == null && nullToAbsent
          ? const Value.absent()
          : Value(token),
      extra: Value(extra),
    );
  }

  factory VisitConfirmation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisitConfirmation(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      visitId: serializer.fromJson<String>(json['visitId']),
      channel: serializer.fromJson<String>(json['channel']),
      status: serializer.fromJson<String>(json['status']),
      requestedAt: serializer.fromJson<DateTime?>(json['requestedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      confirmedAt: serializer.fromJson<DateTime?>(json['confirmedAt']),
      farmerPhoneLast4: serializer.fromJson<String?>(json['farmerPhoneLast4']),
      rating: serializer.fromJson<int?>(json['rating']),
      token: serializer.fromJson<String?>(json['token']),
      extra: serializer.fromJson<String>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'visitId': serializer.toJson<String>(visitId),
      'channel': serializer.toJson<String>(channel),
      'status': serializer.toJson<String>(status),
      'requestedAt': serializer.toJson<DateTime?>(requestedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'confirmedAt': serializer.toJson<DateTime?>(confirmedAt),
      'farmerPhoneLast4': serializer.toJson<String?>(farmerPhoneLast4),
      'rating': serializer.toJson<int?>(rating),
      'token': serializer.toJson<String?>(token),
      'extra': serializer.toJson<String>(extra),
    };
  }

  VisitConfirmation copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    String? visitId,
    String? channel,
    String? status,
    Value<DateTime?> requestedAt = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<DateTime?> confirmedAt = const Value.absent(),
    Value<String?> farmerPhoneLast4 = const Value.absent(),
    Value<int?> rating = const Value.absent(),
    Value<String?> token = const Value.absent(),
    String? extra,
  }) => VisitConfirmation(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    visitId: visitId ?? this.visitId,
    channel: channel ?? this.channel,
    status: status ?? this.status,
    requestedAt: requestedAt.present ? requestedAt.value : this.requestedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    confirmedAt: confirmedAt.present ? confirmedAt.value : this.confirmedAt,
    farmerPhoneLast4: farmerPhoneLast4.present
        ? farmerPhoneLast4.value
        : this.farmerPhoneLast4,
    rating: rating.present ? rating.value : this.rating,
    token: token.present ? token.value : this.token,
    extra: extra ?? this.extra,
  );
  VisitConfirmation copyWithCompanion(VisitConfirmationsCompanion data) {
    return VisitConfirmation(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      visitId: data.visitId.present ? data.visitId.value : this.visitId,
      channel: data.channel.present ? data.channel.value : this.channel,
      status: data.status.present ? data.status.value : this.status,
      requestedAt: data.requestedAt.present
          ? data.requestedAt.value
          : this.requestedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      confirmedAt: data.confirmedAt.present
          ? data.confirmedAt.value
          : this.confirmedAt,
      farmerPhoneLast4: data.farmerPhoneLast4.present
          ? data.farmerPhoneLast4.value
          : this.farmerPhoneLast4,
      rating: data.rating.present ? data.rating.value : this.rating,
      token: data.token.present ? data.token.value : this.token,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisitConfirmation(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('visitId: $visitId, ')
          ..write('channel: $channel, ')
          ..write('status: $status, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('farmerPhoneLast4: $farmerPhoneLast4, ')
          ..write('rating: $rating, ')
          ..write('token: $token, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    visitId,
    channel,
    status,
    requestedAt,
    expiresAt,
    confirmedAt,
    farmerPhoneLast4,
    rating,
    token,
    extra,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisitConfirmation &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.visitId == this.visitId &&
          other.channel == this.channel &&
          other.status == this.status &&
          other.requestedAt == this.requestedAt &&
          other.expiresAt == this.expiresAt &&
          other.confirmedAt == this.confirmedAt &&
          other.farmerPhoneLast4 == this.farmerPhoneLast4 &&
          other.rating == this.rating &&
          other.token == this.token &&
          other.extra == this.extra);
}

class VisitConfirmationsCompanion extends UpdateCompanion<VisitConfirmation> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String> visitId;
  final Value<String> channel;
  final Value<String> status;
  final Value<DateTime?> requestedAt;
  final Value<DateTime?> expiresAt;
  final Value<DateTime?> confirmedAt;
  final Value<String?> farmerPhoneLast4;
  final Value<int?> rating;
  final Value<String?> token;
  final Value<String> extra;
  final Value<int> rowid;
  const VisitConfirmationsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.visitId = const Value.absent(),
    this.channel = const Value.absent(),
    this.status = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.farmerPhoneLast4 = const Value.absent(),
    this.rating = const Value.absent(),
    this.token = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisitConfirmationsCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    required String visitId,
    required String channel,
    this.status = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.confirmedAt = const Value.absent(),
    this.farmerPhoneLast4 = const Value.absent(),
    this.rating = const Value.absent(),
    this.token = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       visitId = Value(visitId),
       channel = Value(channel);
  static Insertable<VisitConfirmation> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? visitId,
    Expression<String>? channel,
    Expression<String>? status,
    Expression<DateTime>? requestedAt,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? confirmedAt,
    Expression<String>? farmerPhoneLast4,
    Expression<int>? rating,
    Expression<String>? token,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (visitId != null) 'visit_id': visitId,
      if (channel != null) 'channel': channel,
      if (status != null) 'status': status,
      if (requestedAt != null) 'requested_at': requestedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (confirmedAt != null) 'confirmed_at': confirmedAt,
      if (farmerPhoneLast4 != null) 'farmer_phone_last4': farmerPhoneLast4,
      if (rating != null) 'rating': rating,
      if (token != null) 'token': token,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisitConfirmationsCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String>? visitId,
    Value<String>? channel,
    Value<String>? status,
    Value<DateTime?>? requestedAt,
    Value<DateTime?>? expiresAt,
    Value<DateTime?>? confirmedAt,
    Value<String?>? farmerPhoneLast4,
    Value<int?>? rating,
    Value<String?>? token,
    Value<String>? extra,
    Value<int>? rowid,
  }) {
    return VisitConfirmationsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      visitId: visitId ?? this.visitId,
      channel: channel ?? this.channel,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      farmerPhoneLast4: farmerPhoneLast4 ?? this.farmerPhoneLast4,
      rating: rating ?? this.rating,
      token: token ?? this.token,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (visitId.present) {
      map['visit_id'] = Variable<String>(visitId.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (requestedAt.present) {
      map['requested_at'] = Variable<DateTime>(requestedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (confirmedAt.present) {
      map['confirmed_at'] = Variable<DateTime>(confirmedAt.value);
    }
    if (farmerPhoneLast4.present) {
      map['farmer_phone_last4'] = Variable<String>(farmerPhoneLast4.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisitConfirmationsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('visitId: $visitId, ')
          ..write('channel: $channel, ')
          ..write('status: $status, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('confirmedAt: $confirmedAt, ')
          ..write('farmerPhoneLast4: $farmerPhoneLast4, ')
          ..write('rating: $rating, ')
          ..write('token: $token, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogProductsTable extends CatalogProducts
    with TableInfo<$CatalogProductsTable, CatalogProductRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _ownBrandMeta = const VerificationMeta(
    'ownBrand',
  );
  @override
  late final GeneratedColumn<bool> ownBrand = GeneratedColumn<bool>(
    'own_brand',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("own_brand" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('other'),
  );
  static const VerificationMeta _activeIngredientMeta = const VerificationMeta(
    'activeIngredient',
  );
  @override
  late final GeneratedColumn<String> activeIngredient = GeneratedColumn<String>(
    'active_ingredient',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formulationMeta = const VerificationMeta(
    'formulation',
  );
  @override
  late final GeneratedColumn<String> formulation = GeneratedColumn<String>(
    'formulation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _namesMeta = const VerificationMeta('names');
  @override
  late final GeneratedColumn<String> names = GeneratedColumn<String>(
    'names',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _imageUriMeta = const VerificationMeta(
    'imageUri',
  );
  @override
  late final GeneratedColumn<String> imageUri = GeneratedColumn<String>(
    'image_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gstRateBpMeta = const VerificationMeta(
    'gstRateBp',
  );
  @override
  late final GeneratedColumn<int> gstRateBp = GeneratedColumn<int>(
    'gst_rate_bp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    brand,
    ownBrand,
    category,
    activeIngredient,
    formulation,
    names,
    imageUri,
    gstRateBp,
    active,
    searchText,
    version,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_products';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogProductRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('own_brand')) {
      context.handle(
        _ownBrandMeta,
        ownBrand.isAcceptableOrUnknown(data['own_brand']!, _ownBrandMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('active_ingredient')) {
      context.handle(
        _activeIngredientMeta,
        activeIngredient.isAcceptableOrUnknown(
          data['active_ingredient']!,
          _activeIngredientMeta,
        ),
      );
    }
    if (data.containsKey('formulation')) {
      context.handle(
        _formulationMeta,
        formulation.isAcceptableOrUnknown(
          data['formulation']!,
          _formulationMeta,
        ),
      );
    }
    if (data.containsKey('names')) {
      context.handle(
        _namesMeta,
        names.isAcceptableOrUnknown(data['names']!, _namesMeta),
      );
    }
    if (data.containsKey('image_uri')) {
      context.handle(
        _imageUriMeta,
        imageUri.isAcceptableOrUnknown(data['image_uri']!, _imageUriMeta),
      );
    }
    if (data.containsKey('gst_rate_bp')) {
      context.handle(
        _gstRateBpMeta,
        gstRateBp.isAcceptableOrUnknown(data['gst_rate_bp']!, _gstRateBpMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CatalogProductRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogProductRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      )!,
      ownBrand: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}own_brand'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      activeIngredient: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_ingredient'],
      ),
      formulation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}formulation'],
      ),
      names: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}names'],
      )!,
      imageUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_uri'],
      ),
      gstRateBp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gst_rate_bp'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CatalogProductsTable createAlias(String alias) {
    return $CatalogProductsTable(attachedDatabase, alias);
  }
}

class CatalogProductRow extends DataClass
    implements Insertable<CatalogProductRow> {
  /// Server id.
  final String id;

  /// Product name.
  final String name;

  /// Brand.
  final String brand;

  /// Tenant's own brand (OwnBrandBadge).
  final bool ownBrand;

  /// `seed` | `fertiliser` | `pesticide` | ... (`ProductCategory`).
  final String category;

  /// Active ingredient (search).
  final String? activeIngredient;

  /// Formulation.
  final String? formulation;

  /// JSON `{lang: name}` of localised names.
  final String names;

  /// Image URI.
  final String? imageUri;

  /// GST rate in basis points (estimates only; the server computes tax).
  final int gstRateBp;

  /// Active in the catalogue.
  final bool active;

  /// Lower-cased name, brand, ingredient and localised names (search).
  final String searchText;

  /// Server row version.
  final int version;

  /// When the row was pulled (UTC).
  final DateTime fetchedAt;
  const CatalogProductRow({
    required this.id,
    required this.name,
    required this.brand,
    required this.ownBrand,
    required this.category,
    this.activeIngredient,
    this.formulation,
    required this.names,
    this.imageUri,
    required this.gstRateBp,
    required this.active,
    required this.searchText,
    required this.version,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['brand'] = Variable<String>(brand);
    map['own_brand'] = Variable<bool>(ownBrand);
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || activeIngredient != null) {
      map['active_ingredient'] = Variable<String>(activeIngredient);
    }
    if (!nullToAbsent || formulation != null) {
      map['formulation'] = Variable<String>(formulation);
    }
    map['names'] = Variable<String>(names);
    if (!nullToAbsent || imageUri != null) {
      map['image_uri'] = Variable<String>(imageUri);
    }
    map['gst_rate_bp'] = Variable<int>(gstRateBp);
    map['active'] = Variable<bool>(active);
    map['search_text'] = Variable<String>(searchText);
    map['version'] = Variable<int>(version);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CatalogProductsCompanion toCompanion(bool nullToAbsent) {
    return CatalogProductsCompanion(
      id: Value(id),
      name: Value(name),
      brand: Value(brand),
      ownBrand: Value(ownBrand),
      category: Value(category),
      activeIngredient: activeIngredient == null && nullToAbsent
          ? const Value.absent()
          : Value(activeIngredient),
      formulation: formulation == null && nullToAbsent
          ? const Value.absent()
          : Value(formulation),
      names: Value(names),
      imageUri: imageUri == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUri),
      gstRateBp: Value(gstRateBp),
      active: Value(active),
      searchText: Value(searchText),
      version: Value(version),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CatalogProductRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogProductRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      brand: serializer.fromJson<String>(json['brand']),
      ownBrand: serializer.fromJson<bool>(json['ownBrand']),
      category: serializer.fromJson<String>(json['category']),
      activeIngredient: serializer.fromJson<String?>(json['activeIngredient']),
      formulation: serializer.fromJson<String?>(json['formulation']),
      names: serializer.fromJson<String>(json['names']),
      imageUri: serializer.fromJson<String?>(json['imageUri']),
      gstRateBp: serializer.fromJson<int>(json['gstRateBp']),
      active: serializer.fromJson<bool>(json['active']),
      searchText: serializer.fromJson<String>(json['searchText']),
      version: serializer.fromJson<int>(json['version']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'brand': serializer.toJson<String>(brand),
      'ownBrand': serializer.toJson<bool>(ownBrand),
      'category': serializer.toJson<String>(category),
      'activeIngredient': serializer.toJson<String?>(activeIngredient),
      'formulation': serializer.toJson<String?>(formulation),
      'names': serializer.toJson<String>(names),
      'imageUri': serializer.toJson<String?>(imageUri),
      'gstRateBp': serializer.toJson<int>(gstRateBp),
      'active': serializer.toJson<bool>(active),
      'searchText': serializer.toJson<String>(searchText),
      'version': serializer.toJson<int>(version),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CatalogProductRow copyWith({
    String? id,
    String? name,
    String? brand,
    bool? ownBrand,
    String? category,
    Value<String?> activeIngredient = const Value.absent(),
    Value<String?> formulation = const Value.absent(),
    String? names,
    Value<String?> imageUri = const Value.absent(),
    int? gstRateBp,
    bool? active,
    String? searchText,
    int? version,
    DateTime? fetchedAt,
  }) => CatalogProductRow(
    id: id ?? this.id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    ownBrand: ownBrand ?? this.ownBrand,
    category: category ?? this.category,
    activeIngredient: activeIngredient.present
        ? activeIngredient.value
        : this.activeIngredient,
    formulation: formulation.present ? formulation.value : this.formulation,
    names: names ?? this.names,
    imageUri: imageUri.present ? imageUri.value : this.imageUri,
    gstRateBp: gstRateBp ?? this.gstRateBp,
    active: active ?? this.active,
    searchText: searchText ?? this.searchText,
    version: version ?? this.version,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CatalogProductRow copyWithCompanion(CatalogProductsCompanion data) {
    return CatalogProductRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      brand: data.brand.present ? data.brand.value : this.brand,
      ownBrand: data.ownBrand.present ? data.ownBrand.value : this.ownBrand,
      category: data.category.present ? data.category.value : this.category,
      activeIngredient: data.activeIngredient.present
          ? data.activeIngredient.value
          : this.activeIngredient,
      formulation: data.formulation.present
          ? data.formulation.value
          : this.formulation,
      names: data.names.present ? data.names.value : this.names,
      imageUri: data.imageUri.present ? data.imageUri.value : this.imageUri,
      gstRateBp: data.gstRateBp.present ? data.gstRateBp.value : this.gstRateBp,
      active: data.active.present ? data.active.value : this.active,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
      version: data.version.present ? data.version.value : this.version,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogProductRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('ownBrand: $ownBrand, ')
          ..write('category: $category, ')
          ..write('activeIngredient: $activeIngredient, ')
          ..write('formulation: $formulation, ')
          ..write('names: $names, ')
          ..write('imageUri: $imageUri, ')
          ..write('gstRateBp: $gstRateBp, ')
          ..write('active: $active, ')
          ..write('searchText: $searchText, ')
          ..write('version: $version, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    brand,
    ownBrand,
    category,
    activeIngredient,
    formulation,
    names,
    imageUri,
    gstRateBp,
    active,
    searchText,
    version,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogProductRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.brand == this.brand &&
          other.ownBrand == this.ownBrand &&
          other.category == this.category &&
          other.activeIngredient == this.activeIngredient &&
          other.formulation == this.formulation &&
          other.names == this.names &&
          other.imageUri == this.imageUri &&
          other.gstRateBp == this.gstRateBp &&
          other.active == this.active &&
          other.searchText == this.searchText &&
          other.version == this.version &&
          other.fetchedAt == this.fetchedAt);
}

class CatalogProductsCompanion extends UpdateCompanion<CatalogProductRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> brand;
  final Value<bool> ownBrand;
  final Value<String> category;
  final Value<String?> activeIngredient;
  final Value<String?> formulation;
  final Value<String> names;
  final Value<String?> imageUri;
  final Value<int> gstRateBp;
  final Value<bool> active;
  final Value<String> searchText;
  final Value<int> version;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CatalogProductsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.brand = const Value.absent(),
    this.ownBrand = const Value.absent(),
    this.category = const Value.absent(),
    this.activeIngredient = const Value.absent(),
    this.formulation = const Value.absent(),
    this.names = const Value.absent(),
    this.imageUri = const Value.absent(),
    this.gstRateBp = const Value.absent(),
    this.active = const Value.absent(),
    this.searchText = const Value.absent(),
    this.version = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogProductsCompanion.insert({
    required String id,
    required String name,
    this.brand = const Value.absent(),
    this.ownBrand = const Value.absent(),
    this.category = const Value.absent(),
    this.activeIngredient = const Value.absent(),
    this.formulation = const Value.absent(),
    this.names = const Value.absent(),
    this.imageUri = const Value.absent(),
    this.gstRateBp = const Value.absent(),
    this.active = const Value.absent(),
    this.searchText = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       fetchedAt = Value(fetchedAt);
  static Insertable<CatalogProductRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? brand,
    Expression<bool>? ownBrand,
    Expression<String>? category,
    Expression<String>? activeIngredient,
    Expression<String>? formulation,
    Expression<String>? names,
    Expression<String>? imageUri,
    Expression<int>? gstRateBp,
    Expression<bool>? active,
    Expression<String>? searchText,
    Expression<int>? version,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (brand != null) 'brand': brand,
      if (ownBrand != null) 'own_brand': ownBrand,
      if (category != null) 'category': category,
      if (activeIngredient != null) 'active_ingredient': activeIngredient,
      if (formulation != null) 'formulation': formulation,
      if (names != null) 'names': names,
      if (imageUri != null) 'image_uri': imageUri,
      if (gstRateBp != null) 'gst_rate_bp': gstRateBp,
      if (active != null) 'active': active,
      if (searchText != null) 'search_text': searchText,
      if (version != null) 'version': version,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogProductsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? brand,
    Value<bool>? ownBrand,
    Value<String>? category,
    Value<String?>? activeIngredient,
    Value<String?>? formulation,
    Value<String>? names,
    Value<String?>? imageUri,
    Value<int>? gstRateBp,
    Value<bool>? active,
    Value<String>? searchText,
    Value<int>? version,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CatalogProductsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      ownBrand: ownBrand ?? this.ownBrand,
      category: category ?? this.category,
      activeIngredient: activeIngredient ?? this.activeIngredient,
      formulation: formulation ?? this.formulation,
      names: names ?? this.names,
      imageUri: imageUri ?? this.imageUri,
      gstRateBp: gstRateBp ?? this.gstRateBp,
      active: active ?? this.active,
      searchText: searchText ?? this.searchText,
      version: version ?? this.version,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (ownBrand.present) {
      map['own_brand'] = Variable<bool>(ownBrand.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (activeIngredient.present) {
      map['active_ingredient'] = Variable<String>(activeIngredient.value);
    }
    if (formulation.present) {
      map['formulation'] = Variable<String>(formulation.value);
    }
    if (names.present) {
      map['names'] = Variable<String>(names.value);
    }
    if (imageUri.present) {
      map['image_uri'] = Variable<String>(imageUri.value);
    }
    if (gstRateBp.present) {
      map['gst_rate_bp'] = Variable<int>(gstRateBp.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('brand: $brand, ')
          ..write('ownBrand: $ownBrand, ')
          ..write('category: $category, ')
          ..write('activeIngredient: $activeIngredient, ')
          ..write('formulation: $formulation, ')
          ..write('names: $names, ')
          ..write('imageUri: $imageUri, ')
          ..write('gstRateBp: $gstRateBp, ')
          ..write('active: $active, ')
          ..write('searchText: $searchText, ')
          ..write('version: $version, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogSkusTable extends CatalogSkus
    with TableInfo<$CatalogSkusTable, CatalogSkuRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogSkusTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packLabelMeta = const VerificationMeta(
    'packLabel',
  );
  @override
  late final GeneratedColumn<String> packLabel = GeneratedColumn<String>(
    'pack_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mrpPaiseMeta = const VerificationMeta(
    'mrpPaise',
  );
  @override
  late final GeneratedColumn<int> mrpPaise = GeneratedColumn<int>(
    'mrp_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    productId,
    packLabel,
    barcode,
    mrpPaise,
    active,
    version,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_skus';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogSkuRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('pack_label')) {
      context.handle(
        _packLabelMeta,
        packLabel.isAcceptableOrUnknown(data['pack_label']!, _packLabelMeta),
      );
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('mrp_paise')) {
      context.handle(
        _mrpPaiseMeta,
        mrpPaise.isAcceptableOrUnknown(data['mrp_paise']!, _mrpPaiseMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CatalogSkuRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogSkuRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      packLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_label'],
      )!,
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      mrpPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}mrp_paise'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CatalogSkusTable createAlias(String alias) {
    return $CatalogSkusTable(attachedDatabase, alias);
  }
}

class CatalogSkuRow extends DataClass implements Insertable<CatalogSkuRow> {
  /// Server id.
  final String id;

  /// Owning product.
  final String productId;

  /// Pack label, e.g. `250 ml`.
  final String packLabel;

  /// Barcode.
  final String? barcode;

  /// MRP in paise.
  final int mrpPaise;

  /// Active.
  final bool active;

  /// Server row version.
  final int version;

  /// When the row was pulled (UTC).
  final DateTime fetchedAt;
  const CatalogSkuRow({
    required this.id,
    required this.productId,
    required this.packLabel,
    this.barcode,
    required this.mrpPaise,
    required this.active,
    required this.version,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['pack_label'] = Variable<String>(packLabel);
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    map['mrp_paise'] = Variable<int>(mrpPaise);
    map['active'] = Variable<bool>(active);
    map['version'] = Variable<int>(version);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CatalogSkusCompanion toCompanion(bool nullToAbsent) {
    return CatalogSkusCompanion(
      id: Value(id),
      productId: Value(productId),
      packLabel: Value(packLabel),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      mrpPaise: Value(mrpPaise),
      active: Value(active),
      version: Value(version),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CatalogSkuRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogSkuRow(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      packLabel: serializer.fromJson<String>(json['packLabel']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      mrpPaise: serializer.fromJson<int>(json['mrpPaise']),
      active: serializer.fromJson<bool>(json['active']),
      version: serializer.fromJson<int>(json['version']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'packLabel': serializer.toJson<String>(packLabel),
      'barcode': serializer.toJson<String?>(barcode),
      'mrpPaise': serializer.toJson<int>(mrpPaise),
      'active': serializer.toJson<bool>(active),
      'version': serializer.toJson<int>(version),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CatalogSkuRow copyWith({
    String? id,
    String? productId,
    String? packLabel,
    Value<String?> barcode = const Value.absent(),
    int? mrpPaise,
    bool? active,
    int? version,
    DateTime? fetchedAt,
  }) => CatalogSkuRow(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    packLabel: packLabel ?? this.packLabel,
    barcode: barcode.present ? barcode.value : this.barcode,
    mrpPaise: mrpPaise ?? this.mrpPaise,
    active: active ?? this.active,
    version: version ?? this.version,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CatalogSkuRow copyWithCompanion(CatalogSkusCompanion data) {
    return CatalogSkuRow(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      packLabel: data.packLabel.present ? data.packLabel.value : this.packLabel,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      mrpPaise: data.mrpPaise.present ? data.mrpPaise.value : this.mrpPaise,
      active: data.active.present ? data.active.value : this.active,
      version: data.version.present ? data.version.value : this.version,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogSkuRow(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('packLabel: $packLabel, ')
          ..write('barcode: $barcode, ')
          ..write('mrpPaise: $mrpPaise, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    packLabel,
    barcode,
    mrpPaise,
    active,
    version,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogSkuRow &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.packLabel == this.packLabel &&
          other.barcode == this.barcode &&
          other.mrpPaise == this.mrpPaise &&
          other.active == this.active &&
          other.version == this.version &&
          other.fetchedAt == this.fetchedAt);
}

class CatalogSkusCompanion extends UpdateCompanion<CatalogSkuRow> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> packLabel;
  final Value<String?> barcode;
  final Value<int> mrpPaise;
  final Value<bool> active;
  final Value<int> version;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CatalogSkusCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.packLabel = const Value.absent(),
    this.barcode = const Value.absent(),
    this.mrpPaise = const Value.absent(),
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogSkusCompanion.insert({
    required String id,
    required String productId,
    this.packLabel = const Value.absent(),
    this.barcode = const Value.absent(),
    this.mrpPaise = const Value.absent(),
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       productId = Value(productId),
       fetchedAt = Value(fetchedAt);
  static Insertable<CatalogSkuRow> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? packLabel,
    Expression<String>? barcode,
    Expression<int>? mrpPaise,
    Expression<bool>? active,
    Expression<int>? version,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (packLabel != null) 'pack_label': packLabel,
      if (barcode != null) 'barcode': barcode,
      if (mrpPaise != null) 'mrp_paise': mrpPaise,
      if (active != null) 'active': active,
      if (version != null) 'version': version,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogSkusCompanion copyWith({
    Value<String>? id,
    Value<String>? productId,
    Value<String>? packLabel,
    Value<String?>? barcode,
    Value<int>? mrpPaise,
    Value<bool>? active,
    Value<int>? version,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CatalogSkusCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      packLabel: packLabel ?? this.packLabel,
      barcode: barcode ?? this.barcode,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      active: active ?? this.active,
      version: version ?? this.version,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (packLabel.present) {
      map['pack_label'] = Variable<String>(packLabel.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (mrpPaise.present) {
      map['mrp_paise'] = Variable<int>(mrpPaise.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogSkusCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('packLabel: $packLabel, ')
          ..write('barcode: $barcode, ')
          ..write('mrpPaise: $mrpPaise, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogPricesTable extends CatalogPrices
    with TableInfo<$CatalogPricesTable, CatalogPriceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogPricesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuIdMeta = const VerificationMeta('skuId');
  @override
  late final GeneratedColumn<String> skuId = GeneratedColumn<String>(
    'sku_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pricePaiseMeta = const VerificationMeta(
    'pricePaise',
  );
  @override
  late final GeneratedColumn<int> pricePaise = GeneratedColumn<int>(
    'price_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [storeId, skuId, pricePaise, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_prices';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogPriceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('sku_id')) {
      context.handle(
        _skuIdMeta,
        skuId.isAcceptableOrUnknown(data['sku_id']!, _skuIdMeta),
      );
    } else if (isInserting) {
      context.missing(_skuIdMeta);
    }
    if (data.containsKey('price_paise')) {
      context.handle(
        _pricePaiseMeta,
        pricePaise.isAcceptableOrUnknown(data['price_paise']!, _pricePaiseMeta),
      );
    } else if (isInserting) {
      context.missing(_pricePaiseMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {storeId, skuId};
  @override
  CatalogPriceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogPriceRow(
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      skuId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku_id'],
      )!,
      pricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_paise'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CatalogPricesTable createAlias(String alias) {
    return $CatalogPricesTable(attachedDatabase, alias);
  }
}

class CatalogPriceRow extends DataClass implements Insertable<CatalogPriceRow> {
  /// Store.
  final String storeId;

  /// SKU.
  final String skuId;

  /// Price in paise.
  final int pricePaise;

  /// When the price was pulled (UTC).
  final DateTime fetchedAt;
  const CatalogPriceRow({
    required this.storeId,
    required this.skuId,
    required this.pricePaise,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['store_id'] = Variable<String>(storeId);
    map['sku_id'] = Variable<String>(skuId);
    map['price_paise'] = Variable<int>(pricePaise);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CatalogPricesCompanion toCompanion(bool nullToAbsent) {
    return CatalogPricesCompanion(
      storeId: Value(storeId),
      skuId: Value(skuId),
      pricePaise: Value(pricePaise),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CatalogPriceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogPriceRow(
      storeId: serializer.fromJson<String>(json['storeId']),
      skuId: serializer.fromJson<String>(json['skuId']),
      pricePaise: serializer.fromJson<int>(json['pricePaise']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'storeId': serializer.toJson<String>(storeId),
      'skuId': serializer.toJson<String>(skuId),
      'pricePaise': serializer.toJson<int>(pricePaise),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CatalogPriceRow copyWith({
    String? storeId,
    String? skuId,
    int? pricePaise,
    DateTime? fetchedAt,
  }) => CatalogPriceRow(
    storeId: storeId ?? this.storeId,
    skuId: skuId ?? this.skuId,
    pricePaise: pricePaise ?? this.pricePaise,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  CatalogPriceRow copyWithCompanion(CatalogPricesCompanion data) {
    return CatalogPriceRow(
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      skuId: data.skuId.present ? data.skuId.value : this.skuId,
      pricePaise: data.pricePaise.present
          ? data.pricePaise.value
          : this.pricePaise,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogPriceRow(')
          ..write('storeId: $storeId, ')
          ..write('skuId: $skuId, ')
          ..write('pricePaise: $pricePaise, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(storeId, skuId, pricePaise, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogPriceRow &&
          other.storeId == this.storeId &&
          other.skuId == this.skuId &&
          other.pricePaise == this.pricePaise &&
          other.fetchedAt == this.fetchedAt);
}

class CatalogPricesCompanion extends UpdateCompanion<CatalogPriceRow> {
  final Value<String> storeId;
  final Value<String> skuId;
  final Value<int> pricePaise;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CatalogPricesCompanion({
    this.storeId = const Value.absent(),
    this.skuId = const Value.absent(),
    this.pricePaise = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogPricesCompanion.insert({
    required String storeId,
    required String skuId,
    required int pricePaise,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : storeId = Value(storeId),
       skuId = Value(skuId),
       pricePaise = Value(pricePaise),
       fetchedAt = Value(fetchedAt);
  static Insertable<CatalogPriceRow> custom({
    Expression<String>? storeId,
    Expression<String>? skuId,
    Expression<int>? pricePaise,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (storeId != null) 'store_id': storeId,
      if (skuId != null) 'sku_id': skuId,
      if (pricePaise != null) 'price_paise': pricePaise,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogPricesCompanion copyWith({
    Value<String>? storeId,
    Value<String>? skuId,
    Value<int>? pricePaise,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CatalogPricesCompanion(
      storeId: storeId ?? this.storeId,
      skuId: skuId ?? this.skuId,
      pricePaise: pricePaise ?? this.pricePaise,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (skuId.present) {
      map['sku_id'] = Variable<String>(skuId.value);
    }
    if (pricePaise.present) {
      map['price_paise'] = Variable<int>(pricePaise.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogPricesCompanion(')
          ..write('storeId: $storeId, ')
          ..write('skuId: $skuId, ')
          ..write('pricePaise: $pricePaise, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockSnapshotsTable extends StockSnapshots
    with TableInfo<$StockSnapshotsTable, StockSnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuIdMeta = const VerificationMeta('skuId');
  @override
  late final GeneratedColumn<String> skuId = GeneratedColumn<String>(
    'sku_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _onHandMeta = const VerificationMeta('onHand');
  @override
  late final GeneratedColumn<double> onHand = GeneratedColumn<double>(
    'on_hand',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _availableMeta = const VerificationMeta(
    'available',
  );
  @override
  late final GeneratedColumn<double> available = GeneratedColumn<double>(
    'available',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _asOfMeta = const VerificationMeta('asOf');
  @override
  late final GeneratedColumn<DateTime> asOf = GeneratedColumn<DateTime>(
    'as_of',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    storeId,
    skuId,
    onHand,
    available,
    asOf,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<StockSnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_storeIdMeta);
    }
    if (data.containsKey('sku_id')) {
      context.handle(
        _skuIdMeta,
        skuId.isAcceptableOrUnknown(data['sku_id']!, _skuIdMeta),
      );
    } else if (isInserting) {
      context.missing(_skuIdMeta);
    }
    if (data.containsKey('on_hand')) {
      context.handle(
        _onHandMeta,
        onHand.isAcceptableOrUnknown(data['on_hand']!, _onHandMeta),
      );
    }
    if (data.containsKey('available')) {
      context.handle(
        _availableMeta,
        available.isAcceptableOrUnknown(data['available']!, _availableMeta),
      );
    }
    if (data.containsKey('as_of')) {
      context.handle(
        _asOfMeta,
        asOf.isAcceptableOrUnknown(data['as_of']!, _asOfMeta),
      );
    } else if (isInserting) {
      context.missing(_asOfMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {storeId, skuId};
  @override
  StockSnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockSnapshotRow(
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      )!,
      skuId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku_id'],
      )!,
      onHand: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}on_hand'],
      ),
      available: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}available'],
      ),
      asOf: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}as_of'],
      )!,
    );
  }

  @override
  $StockSnapshotsTable createAlias(String alias) {
    return $StockSnapshotsTable(attachedDatabase, alias);
  }
}

class StockSnapshotRow extends DataClass
    implements Insertable<StockSnapshotRow> {
  /// Store.
  final String storeId;

  /// SKU.
  final String skuId;

  /// On hand (ledger sum), if known.
  final double? onHand;

  /// Available to order (on hand − reserved), if known.
  final double? available;

  /// When the numbers were true (UTC).
  final DateTime asOf;
  const StockSnapshotRow({
    required this.storeId,
    required this.skuId,
    this.onHand,
    this.available,
    required this.asOf,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['store_id'] = Variable<String>(storeId);
    map['sku_id'] = Variable<String>(skuId);
    if (!nullToAbsent || onHand != null) {
      map['on_hand'] = Variable<double>(onHand);
    }
    if (!nullToAbsent || available != null) {
      map['available'] = Variable<double>(available);
    }
    map['as_of'] = Variable<DateTime>(asOf);
    return map;
  }

  StockSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return StockSnapshotsCompanion(
      storeId: Value(storeId),
      skuId: Value(skuId),
      onHand: onHand == null && nullToAbsent
          ? const Value.absent()
          : Value(onHand),
      available: available == null && nullToAbsent
          ? const Value.absent()
          : Value(available),
      asOf: Value(asOf),
    );
  }

  factory StockSnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockSnapshotRow(
      storeId: serializer.fromJson<String>(json['storeId']),
      skuId: serializer.fromJson<String>(json['skuId']),
      onHand: serializer.fromJson<double?>(json['onHand']),
      available: serializer.fromJson<double?>(json['available']),
      asOf: serializer.fromJson<DateTime>(json['asOf']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'storeId': serializer.toJson<String>(storeId),
      'skuId': serializer.toJson<String>(skuId),
      'onHand': serializer.toJson<double?>(onHand),
      'available': serializer.toJson<double?>(available),
      'asOf': serializer.toJson<DateTime>(asOf),
    };
  }

  StockSnapshotRow copyWith({
    String? storeId,
    String? skuId,
    Value<double?> onHand = const Value.absent(),
    Value<double?> available = const Value.absent(),
    DateTime? asOf,
  }) => StockSnapshotRow(
    storeId: storeId ?? this.storeId,
    skuId: skuId ?? this.skuId,
    onHand: onHand.present ? onHand.value : this.onHand,
    available: available.present ? available.value : this.available,
    asOf: asOf ?? this.asOf,
  );
  StockSnapshotRow copyWithCompanion(StockSnapshotsCompanion data) {
    return StockSnapshotRow(
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      skuId: data.skuId.present ? data.skuId.value : this.skuId,
      onHand: data.onHand.present ? data.onHand.value : this.onHand,
      available: data.available.present ? data.available.value : this.available,
      asOf: data.asOf.present ? data.asOf.value : this.asOf,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockSnapshotRow(')
          ..write('storeId: $storeId, ')
          ..write('skuId: $skuId, ')
          ..write('onHand: $onHand, ')
          ..write('available: $available, ')
          ..write('asOf: $asOf')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(storeId, skuId, onHand, available, asOf);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockSnapshotRow &&
          other.storeId == this.storeId &&
          other.skuId == this.skuId &&
          other.onHand == this.onHand &&
          other.available == this.available &&
          other.asOf == this.asOf);
}

class StockSnapshotsCompanion extends UpdateCompanion<StockSnapshotRow> {
  final Value<String> storeId;
  final Value<String> skuId;
  final Value<double?> onHand;
  final Value<double?> available;
  final Value<DateTime> asOf;
  final Value<int> rowid;
  const StockSnapshotsCompanion({
    this.storeId = const Value.absent(),
    this.skuId = const Value.absent(),
    this.onHand = const Value.absent(),
    this.available = const Value.absent(),
    this.asOf = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockSnapshotsCompanion.insert({
    required String storeId,
    required String skuId,
    this.onHand = const Value.absent(),
    this.available = const Value.absent(),
    required DateTime asOf,
    this.rowid = const Value.absent(),
  }) : storeId = Value(storeId),
       skuId = Value(skuId),
       asOf = Value(asOf);
  static Insertable<StockSnapshotRow> custom({
    Expression<String>? storeId,
    Expression<String>? skuId,
    Expression<double>? onHand,
    Expression<double>? available,
    Expression<DateTime>? asOf,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (storeId != null) 'store_id': storeId,
      if (skuId != null) 'sku_id': skuId,
      if (onHand != null) 'on_hand': onHand,
      if (available != null) 'available': available,
      if (asOf != null) 'as_of': asOf,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockSnapshotsCompanion copyWith({
    Value<String>? storeId,
    Value<String>? skuId,
    Value<double?>? onHand,
    Value<double?>? available,
    Value<DateTime>? asOf,
    Value<int>? rowid,
  }) {
    return StockSnapshotsCompanion(
      storeId: storeId ?? this.storeId,
      skuId: skuId ?? this.skuId,
      onHand: onHand ?? this.onHand,
      available: available ?? this.available,
      asOf: asOf ?? this.asOf,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (skuId.present) {
      map['sku_id'] = Variable<String>(skuId.value);
    }
    if (onHand.present) {
      map['on_hand'] = Variable<double>(onHand.value);
    }
    if (available.present) {
      map['available'] = Variable<double>(available.value);
    }
    if (asOf.present) {
      map['as_of'] = Variable<DateTime>(asOf.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockSnapshotsCompanion(')
          ..write('storeId: $storeId, ')
          ..write('skuId: $skuId, ')
          ..write('onHand: $onHand, ')
          ..write('available: $available, ')
          ..write('asOf: $asOf, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogStoresTable extends CatalogStores
    with TableInfo<$CatalogStoresTable, CatalogStoreRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogStoresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _districtMeta = const VerificationMeta(
    'district',
  );
  @override
  late final GeneratedColumn<String> district = GeneratedColumn<String>(
    'district',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _catalogRefreshedAtMeta =
      const VerificationMeta('catalogRefreshedAt');
  @override
  late final GeneratedColumn<DateTime> catalogRefreshedAt =
      GeneratedColumn<DateTime>(
        'catalog_refreshed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    code,
    name,
    district,
    catalogRefreshedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_stores';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogStoreRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('district')) {
      context.handle(
        _districtMeta,
        district.isAcceptableOrUnknown(data['district']!, _districtMeta),
      );
    }
    if (data.containsKey('catalog_refreshed_at')) {
      context.handle(
        _catalogRefreshedAtMeta,
        catalogRefreshedAt.isAcceptableOrUnknown(
          data['catalog_refreshed_at']!,
          _catalogRefreshedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CatalogStoreRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogStoreRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      district: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}district'],
      )!,
      catalogRefreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}catalog_refreshed_at'],
      ),
    );
  }

  @override
  $CatalogStoresTable createAlias(String alias) {
    return $CatalogStoresTable(attachedDatabase, alias);
  }
}

class CatalogStoreRow extends DataClass implements Insertable<CatalogStoreRow> {
  /// Server id.
  final String id;

  /// Store code.
  final String code;

  /// Store name.
  final String name;

  /// District.
  final String district;

  /// Last complete catalogue refresh for this store (UTC).
  final DateTime? catalogRefreshedAt;
  const CatalogStoreRow({
    required this.id,
    required this.code,
    required this.name,
    required this.district,
    this.catalogRefreshedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['district'] = Variable<String>(district);
    if (!nullToAbsent || catalogRefreshedAt != null) {
      map['catalog_refreshed_at'] = Variable<DateTime>(catalogRefreshedAt);
    }
    return map;
  }

  CatalogStoresCompanion toCompanion(bool nullToAbsent) {
    return CatalogStoresCompanion(
      id: Value(id),
      code: Value(code),
      name: Value(name),
      district: Value(district),
      catalogRefreshedAt: catalogRefreshedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(catalogRefreshedAt),
    );
  }

  factory CatalogStoreRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogStoreRow(
      id: serializer.fromJson<String>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      district: serializer.fromJson<String>(json['district']),
      catalogRefreshedAt: serializer.fromJson<DateTime?>(
        json['catalogRefreshedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'district': serializer.toJson<String>(district),
      'catalogRefreshedAt': serializer.toJson<DateTime?>(catalogRefreshedAt),
    };
  }

  CatalogStoreRow copyWith({
    String? id,
    String? code,
    String? name,
    String? district,
    Value<DateTime?> catalogRefreshedAt = const Value.absent(),
  }) => CatalogStoreRow(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    district: district ?? this.district,
    catalogRefreshedAt: catalogRefreshedAt.present
        ? catalogRefreshedAt.value
        : this.catalogRefreshedAt,
  );
  CatalogStoreRow copyWithCompanion(CatalogStoresCompanion data) {
    return CatalogStoreRow(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      district: data.district.present ? data.district.value : this.district,
      catalogRefreshedAt: data.catalogRefreshedAt.present
          ? data.catalogRefreshedAt.value
          : this.catalogRefreshedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogStoreRow(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('district: $district, ')
          ..write('catalogRefreshedAt: $catalogRefreshedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, code, name, district, catalogRefreshedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogStoreRow &&
          other.id == this.id &&
          other.code == this.code &&
          other.name == this.name &&
          other.district == this.district &&
          other.catalogRefreshedAt == this.catalogRefreshedAt);
}

class CatalogStoresCompanion extends UpdateCompanion<CatalogStoreRow> {
  final Value<String> id;
  final Value<String> code;
  final Value<String> name;
  final Value<String> district;
  final Value<DateTime?> catalogRefreshedAt;
  final Value<int> rowid;
  const CatalogStoresCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.district = const Value.absent(),
    this.catalogRefreshedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogStoresCompanion.insert({
    required String id,
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.district = const Value.absent(),
    this.catalogRefreshedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<CatalogStoreRow> custom({
    Expression<String>? id,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? district,
    Expression<DateTime>? catalogRefreshedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (district != null) 'district': district,
      if (catalogRefreshedAt != null)
        'catalog_refreshed_at': catalogRefreshedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogStoresCompanion copyWith({
    Value<String>? id,
    Value<String>? code,
    Value<String>? name,
    Value<String>? district,
    Value<DateTime?>? catalogRefreshedAt,
    Value<int>? rowid,
  }) {
    return CatalogStoresCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      district: district ?? this.district,
      catalogRefreshedAt: catalogRefreshedAt ?? this.catalogRefreshedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (district.present) {
      map['district'] = Variable<String>(district.value);
    }
    if (catalogRefreshedAt.present) {
      map['catalog_refreshed_at'] = Variable<DateTime>(
        catalogRefreshedAt.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogStoresCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('district: $district, ')
          ..write('catalogRefreshedAt: $catalogRefreshedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OrdersTable extends Orders with TableInfo<$OrdersTable, OrderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _farmerIdMeta = const VerificationMeta(
    'farmerId',
  );
  @override
  late final GeneratedColumn<String> farmerId = GeneratedColumn<String>(
    'farmer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('placed'),
  );
  static const VerificationMeta _fulfilmentMeta = const VerificationMeta(
    'fulfilment',
  );
  @override
  late final GeneratedColumn<String> fulfilment = GeneratedColumn<String>(
    'fulfilment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pickup'),
  );
  static const VerificationMeta _paymentModeMeta = const VerificationMeta(
    'paymentMode',
  );
  @override
  late final GeneratedColumn<String> paymentMode = GeneratedColumn<String>(
    'payment_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subtotalPaiseMeta = const VerificationMeta(
    'subtotalPaise',
  );
  @override
  late final GeneratedColumn<int> subtotalPaise = GeneratedColumn<int>(
    'subtotal_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _taxPaiseMeta = const VerificationMeta(
    'taxPaise',
  );
  @override
  late final GeneratedColumn<int> taxPaise = GeneratedColumn<int>(
    'tax_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalPaiseMeta = const VerificationMeta(
    'totalPaise',
  );
  @override
  late final GeneratedColumn<int> totalPaise = GeneratedColumn<int>(
    'total_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedTotalPaiseMeta =
      const VerificationMeta('estimatedTotalPaise');
  @override
  late final GeneratedColumn<int> estimatedTotalPaise = GeneratedColumn<int>(
    'estimated_total_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _placedAtMeta = const VerificationMeta(
    'placedAt',
  );
  @override
  late final GeneratedColumn<DateTime> placedAt = GeneratedColumn<DateTime>(
    'placed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _invoiceNoMeta = const VerificationMeta(
    'invoiceNo',
  );
  @override
  late final GeneratedColumn<String> invoiceNo = GeneratedColumn<String>(
    'invoice_no',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _invoiceIdMeta = const VerificationMeta(
    'invoiceId',
  );
  @override
  late final GeneratedColumn<String> invoiceId = GeneratedColumn<String>(
    'invoice_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventsMeta = const VerificationMeta('events');
  @override
  late final GeneratedColumn<String> events = GeneratedColumn<String>(
    'events',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    storeId,
    status,
    fulfilment,
    paymentMode,
    subtotalPaise,
    taxPaise,
    totalPaise,
    estimatedTotalPaise,
    placedAt,
    invoiceNo,
    invoiceId,
    notes,
    events,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'orders';
  @override
  VerificationContext validateIntegrity(
    Insertable<OrderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('farmer_id')) {
      context.handle(
        _farmerIdMeta,
        farmerId.isAcceptableOrUnknown(data['farmer_id']!, _farmerIdMeta),
      );
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('fulfilment')) {
      context.handle(
        _fulfilmentMeta,
        fulfilment.isAcceptableOrUnknown(data['fulfilment']!, _fulfilmentMeta),
      );
    }
    if (data.containsKey('payment_mode')) {
      context.handle(
        _paymentModeMeta,
        paymentMode.isAcceptableOrUnknown(
          data['payment_mode']!,
          _paymentModeMeta,
        ),
      );
    }
    if (data.containsKey('subtotal_paise')) {
      context.handle(
        _subtotalPaiseMeta,
        subtotalPaise.isAcceptableOrUnknown(
          data['subtotal_paise']!,
          _subtotalPaiseMeta,
        ),
      );
    }
    if (data.containsKey('tax_paise')) {
      context.handle(
        _taxPaiseMeta,
        taxPaise.isAcceptableOrUnknown(data['tax_paise']!, _taxPaiseMeta),
      );
    }
    if (data.containsKey('total_paise')) {
      context.handle(
        _totalPaiseMeta,
        totalPaise.isAcceptableOrUnknown(data['total_paise']!, _totalPaiseMeta),
      );
    }
    if (data.containsKey('estimated_total_paise')) {
      context.handle(
        _estimatedTotalPaiseMeta,
        estimatedTotalPaise.isAcceptableOrUnknown(
          data['estimated_total_paise']!,
          _estimatedTotalPaiseMeta,
        ),
      );
    }
    if (data.containsKey('placed_at')) {
      context.handle(
        _placedAtMeta,
        placedAt.isAcceptableOrUnknown(data['placed_at']!, _placedAtMeta),
      );
    }
    if (data.containsKey('invoice_no')) {
      context.handle(
        _invoiceNoMeta,
        invoiceNo.isAcceptableOrUnknown(data['invoice_no']!, _invoiceNoMeta),
      );
    }
    if (data.containsKey('invoice_id')) {
      context.handle(
        _invoiceIdMeta,
        invoiceId.isAcceptableOrUnknown(data['invoice_id']!, _invoiceIdMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('events')) {
      context.handle(
        _eventsMeta,
        events.isAcceptableOrUnknown(data['events']!, _eventsMeta),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      farmerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farmer_id'],
      ),
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      fulfilment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fulfilment'],
      )!,
      paymentMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_mode'],
      ),
      subtotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subtotal_paise'],
      ),
      taxPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tax_paise'],
      ),
      totalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_paise'],
      ),
      estimatedTotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_total_paise'],
      )!,
      placedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}placed_at'],
      ),
      invoiceNo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invoice_no'],
      ),
      invoiceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}invoice_id'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      events: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}events'],
      )!,
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      )!,
    );
  }

  @override
  $OrdersTable createAlias(String alias) {
    return $OrdersTable(attachedDatabase, alias);
  }
}

class OrderRow extends DataClass implements Insertable<OrderRow> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Farmer the order is for.
  final String? farmerId;

  /// Store the order goes to.
  final String? storeId;

  /// Server status (`placed` until the server says otherwise).
  final String status;

  /// `pickup` | `delivery`.
  final String fulfilment;

  /// Payment mode chosen at placing, if any.
  final String? paymentMode;

  /// Server subtotal (paise).
  final int? subtotalPaise;

  /// Server tax (paise).
  final int? taxPaise;

  /// Server total (paise).
  final int? totalPaise;

  /// Device estimate from cached prices (paise); display only.
  final int estimatedTotalPaise;

  /// When the order was placed (server) or captured (device), UTC.
  final DateTime? placedAt;

  /// GST invoice number once issued.
  final String? invoiceNo;

  /// Invoice id once the server exposes it (A57 share).
  final String? invoiceId;

  /// Notes.
  final String? notes;

  /// JSON list of `{from_status, to_status, created_at}` (ST-005 history).
  final String events;

  /// JSON of server fields this app does not model.
  final String extra;
  const OrderRow({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    this.farmerId,
    this.storeId,
    required this.status,
    required this.fulfilment,
    this.paymentMode,
    this.subtotalPaise,
    this.taxPaise,
    this.totalPaise,
    required this.estimatedTotalPaise,
    this.placedAt,
    this.invoiceNo,
    this.invoiceId,
    this.notes,
    required this.events,
    required this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || farmerId != null) {
      map['farmer_id'] = Variable<String>(farmerId);
    }
    if (!nullToAbsent || storeId != null) {
      map['store_id'] = Variable<String>(storeId);
    }
    map['status'] = Variable<String>(status);
    map['fulfilment'] = Variable<String>(fulfilment);
    if (!nullToAbsent || paymentMode != null) {
      map['payment_mode'] = Variable<String>(paymentMode);
    }
    if (!nullToAbsent || subtotalPaise != null) {
      map['subtotal_paise'] = Variable<int>(subtotalPaise);
    }
    if (!nullToAbsent || taxPaise != null) {
      map['tax_paise'] = Variable<int>(taxPaise);
    }
    if (!nullToAbsent || totalPaise != null) {
      map['total_paise'] = Variable<int>(totalPaise);
    }
    map['estimated_total_paise'] = Variable<int>(estimatedTotalPaise);
    if (!nullToAbsent || placedAt != null) {
      map['placed_at'] = Variable<DateTime>(placedAt);
    }
    if (!nullToAbsent || invoiceNo != null) {
      map['invoice_no'] = Variable<String>(invoiceNo);
    }
    if (!nullToAbsent || invoiceId != null) {
      map['invoice_id'] = Variable<String>(invoiceId);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['events'] = Variable<String>(events);
    map['extra'] = Variable<String>(extra);
    return map;
  }

  OrdersCompanion toCompanion(bool nullToAbsent) {
    return OrdersCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      farmerId: farmerId == null && nullToAbsent
          ? const Value.absent()
          : Value(farmerId),
      storeId: storeId == null && nullToAbsent
          ? const Value.absent()
          : Value(storeId),
      status: Value(status),
      fulfilment: Value(fulfilment),
      paymentMode: paymentMode == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentMode),
      subtotalPaise: subtotalPaise == null && nullToAbsent
          ? const Value.absent()
          : Value(subtotalPaise),
      taxPaise: taxPaise == null && nullToAbsent
          ? const Value.absent()
          : Value(taxPaise),
      totalPaise: totalPaise == null && nullToAbsent
          ? const Value.absent()
          : Value(totalPaise),
      estimatedTotalPaise: Value(estimatedTotalPaise),
      placedAt: placedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(placedAt),
      invoiceNo: invoiceNo == null && nullToAbsent
          ? const Value.absent()
          : Value(invoiceNo),
      invoiceId: invoiceId == null && nullToAbsent
          ? const Value.absent()
          : Value(invoiceId),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      events: Value(events),
      extra: Value(extra),
    );
  }

  factory OrderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderRow(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      farmerId: serializer.fromJson<String?>(json['farmerId']),
      storeId: serializer.fromJson<String?>(json['storeId']),
      status: serializer.fromJson<String>(json['status']),
      fulfilment: serializer.fromJson<String>(json['fulfilment']),
      paymentMode: serializer.fromJson<String?>(json['paymentMode']),
      subtotalPaise: serializer.fromJson<int?>(json['subtotalPaise']),
      taxPaise: serializer.fromJson<int?>(json['taxPaise']),
      totalPaise: serializer.fromJson<int?>(json['totalPaise']),
      estimatedTotalPaise: serializer.fromJson<int>(
        json['estimatedTotalPaise'],
      ),
      placedAt: serializer.fromJson<DateTime?>(json['placedAt']),
      invoiceNo: serializer.fromJson<String?>(json['invoiceNo']),
      invoiceId: serializer.fromJson<String?>(json['invoiceId']),
      notes: serializer.fromJson<String?>(json['notes']),
      events: serializer.fromJson<String>(json['events']),
      extra: serializer.fromJson<String>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'farmerId': serializer.toJson<String?>(farmerId),
      'storeId': serializer.toJson<String?>(storeId),
      'status': serializer.toJson<String>(status),
      'fulfilment': serializer.toJson<String>(fulfilment),
      'paymentMode': serializer.toJson<String?>(paymentMode),
      'subtotalPaise': serializer.toJson<int?>(subtotalPaise),
      'taxPaise': serializer.toJson<int?>(taxPaise),
      'totalPaise': serializer.toJson<int?>(totalPaise),
      'estimatedTotalPaise': serializer.toJson<int>(estimatedTotalPaise),
      'placedAt': serializer.toJson<DateTime?>(placedAt),
      'invoiceNo': serializer.toJson<String?>(invoiceNo),
      'invoiceId': serializer.toJson<String?>(invoiceId),
      'notes': serializer.toJson<String?>(notes),
      'events': serializer.toJson<String>(events),
      'extra': serializer.toJson<String>(extra),
    };
  }

  OrderRow copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    Value<String?> farmerId = const Value.absent(),
    Value<String?> storeId = const Value.absent(),
    String? status,
    String? fulfilment,
    Value<String?> paymentMode = const Value.absent(),
    Value<int?> subtotalPaise = const Value.absent(),
    Value<int?> taxPaise = const Value.absent(),
    Value<int?> totalPaise = const Value.absent(),
    int? estimatedTotalPaise,
    Value<DateTime?> placedAt = const Value.absent(),
    Value<String?> invoiceNo = const Value.absent(),
    Value<String?> invoiceId = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    String? events,
    String? extra,
  }) => OrderRow(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    farmerId: farmerId.present ? farmerId.value : this.farmerId,
    storeId: storeId.present ? storeId.value : this.storeId,
    status: status ?? this.status,
    fulfilment: fulfilment ?? this.fulfilment,
    paymentMode: paymentMode.present ? paymentMode.value : this.paymentMode,
    subtotalPaise: subtotalPaise.present
        ? subtotalPaise.value
        : this.subtotalPaise,
    taxPaise: taxPaise.present ? taxPaise.value : this.taxPaise,
    totalPaise: totalPaise.present ? totalPaise.value : this.totalPaise,
    estimatedTotalPaise: estimatedTotalPaise ?? this.estimatedTotalPaise,
    placedAt: placedAt.present ? placedAt.value : this.placedAt,
    invoiceNo: invoiceNo.present ? invoiceNo.value : this.invoiceNo,
    invoiceId: invoiceId.present ? invoiceId.value : this.invoiceId,
    notes: notes.present ? notes.value : this.notes,
    events: events ?? this.events,
    extra: extra ?? this.extra,
  );
  OrderRow copyWithCompanion(OrdersCompanion data) {
    return OrderRow(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      farmerId: data.farmerId.present ? data.farmerId.value : this.farmerId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      status: data.status.present ? data.status.value : this.status,
      fulfilment: data.fulfilment.present
          ? data.fulfilment.value
          : this.fulfilment,
      paymentMode: data.paymentMode.present
          ? data.paymentMode.value
          : this.paymentMode,
      subtotalPaise: data.subtotalPaise.present
          ? data.subtotalPaise.value
          : this.subtotalPaise,
      taxPaise: data.taxPaise.present ? data.taxPaise.value : this.taxPaise,
      totalPaise: data.totalPaise.present
          ? data.totalPaise.value
          : this.totalPaise,
      estimatedTotalPaise: data.estimatedTotalPaise.present
          ? data.estimatedTotalPaise.value
          : this.estimatedTotalPaise,
      placedAt: data.placedAt.present ? data.placedAt.value : this.placedAt,
      invoiceNo: data.invoiceNo.present ? data.invoiceNo.value : this.invoiceNo,
      invoiceId: data.invoiceId.present ? data.invoiceId.value : this.invoiceId,
      notes: data.notes.present ? data.notes.value : this.notes,
      events: data.events.present ? data.events.value : this.events,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderRow(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('storeId: $storeId, ')
          ..write('status: $status, ')
          ..write('fulfilment: $fulfilment, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('subtotalPaise: $subtotalPaise, ')
          ..write('taxPaise: $taxPaise, ')
          ..write('totalPaise: $totalPaise, ')
          ..write('estimatedTotalPaise: $estimatedTotalPaise, ')
          ..write('placedAt: $placedAt, ')
          ..write('invoiceNo: $invoiceNo, ')
          ..write('invoiceId: $invoiceId, ')
          ..write('notes: $notes, ')
          ..write('events: $events, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    farmerId,
    storeId,
    status,
    fulfilment,
    paymentMode,
    subtotalPaise,
    taxPaise,
    totalPaise,
    estimatedTotalPaise,
    placedAt,
    invoiceNo,
    invoiceId,
    notes,
    events,
    extra,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderRow &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.farmerId == this.farmerId &&
          other.storeId == this.storeId &&
          other.status == this.status &&
          other.fulfilment == this.fulfilment &&
          other.paymentMode == this.paymentMode &&
          other.subtotalPaise == this.subtotalPaise &&
          other.taxPaise == this.taxPaise &&
          other.totalPaise == this.totalPaise &&
          other.estimatedTotalPaise == this.estimatedTotalPaise &&
          other.placedAt == this.placedAt &&
          other.invoiceNo == this.invoiceNo &&
          other.invoiceId == this.invoiceId &&
          other.notes == this.notes &&
          other.events == this.events &&
          other.extra == this.extra);
}

class OrdersCompanion extends UpdateCompanion<OrderRow> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String?> farmerId;
  final Value<String?> storeId;
  final Value<String> status;
  final Value<String> fulfilment;
  final Value<String?> paymentMode;
  final Value<int?> subtotalPaise;
  final Value<int?> taxPaise;
  final Value<int?> totalPaise;
  final Value<int> estimatedTotalPaise;
  final Value<DateTime?> placedAt;
  final Value<String?> invoiceNo;
  final Value<String?> invoiceId;
  final Value<String?> notes;
  final Value<String> events;
  final Value<String> extra;
  final Value<int> rowid;
  const OrdersCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.farmerId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.status = const Value.absent(),
    this.fulfilment = const Value.absent(),
    this.paymentMode = const Value.absent(),
    this.subtotalPaise = const Value.absent(),
    this.taxPaise = const Value.absent(),
    this.totalPaise = const Value.absent(),
    this.estimatedTotalPaise = const Value.absent(),
    this.placedAt = const Value.absent(),
    this.invoiceNo = const Value.absent(),
    this.invoiceId = const Value.absent(),
    this.notes = const Value.absent(),
    this.events = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrdersCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.farmerId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.status = const Value.absent(),
    this.fulfilment = const Value.absent(),
    this.paymentMode = const Value.absent(),
    this.subtotalPaise = const Value.absent(),
    this.taxPaise = const Value.absent(),
    this.totalPaise = const Value.absent(),
    this.estimatedTotalPaise = const Value.absent(),
    this.placedAt = const Value.absent(),
    this.invoiceNo = const Value.absent(),
    this.invoiceId = const Value.absent(),
    this.notes = const Value.absent(),
    this.events = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt);
  static Insertable<OrderRow> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? farmerId,
    Expression<String>? storeId,
    Expression<String>? status,
    Expression<String>? fulfilment,
    Expression<String>? paymentMode,
    Expression<int>? subtotalPaise,
    Expression<int>? taxPaise,
    Expression<int>? totalPaise,
    Expression<int>? estimatedTotalPaise,
    Expression<DateTime>? placedAt,
    Expression<String>? invoiceNo,
    Expression<String>? invoiceId,
    Expression<String>? notes,
    Expression<String>? events,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (farmerId != null) 'farmer_id': farmerId,
      if (storeId != null) 'store_id': storeId,
      if (status != null) 'status': status,
      if (fulfilment != null) 'fulfilment': fulfilment,
      if (paymentMode != null) 'payment_mode': paymentMode,
      if (subtotalPaise != null) 'subtotal_paise': subtotalPaise,
      if (taxPaise != null) 'tax_paise': taxPaise,
      if (totalPaise != null) 'total_paise': totalPaise,
      if (estimatedTotalPaise != null)
        'estimated_total_paise': estimatedTotalPaise,
      if (placedAt != null) 'placed_at': placedAt,
      if (invoiceNo != null) 'invoice_no': invoiceNo,
      if (invoiceId != null) 'invoice_id': invoiceId,
      if (notes != null) 'notes': notes,
      if (events != null) 'events': events,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrdersCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String?>? farmerId,
    Value<String?>? storeId,
    Value<String>? status,
    Value<String>? fulfilment,
    Value<String?>? paymentMode,
    Value<int?>? subtotalPaise,
    Value<int?>? taxPaise,
    Value<int?>? totalPaise,
    Value<int>? estimatedTotalPaise,
    Value<DateTime?>? placedAt,
    Value<String?>? invoiceNo,
    Value<String?>? invoiceId,
    Value<String?>? notes,
    Value<String>? events,
    Value<String>? extra,
    Value<int>? rowid,
  }) {
    return OrdersCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      farmerId: farmerId ?? this.farmerId,
      storeId: storeId ?? this.storeId,
      status: status ?? this.status,
      fulfilment: fulfilment ?? this.fulfilment,
      paymentMode: paymentMode ?? this.paymentMode,
      subtotalPaise: subtotalPaise ?? this.subtotalPaise,
      taxPaise: taxPaise ?? this.taxPaise,
      totalPaise: totalPaise ?? this.totalPaise,
      estimatedTotalPaise: estimatedTotalPaise ?? this.estimatedTotalPaise,
      placedAt: placedAt ?? this.placedAt,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      invoiceId: invoiceId ?? this.invoiceId,
      notes: notes ?? this.notes,
      events: events ?? this.events,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (farmerId.present) {
      map['farmer_id'] = Variable<String>(farmerId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (fulfilment.present) {
      map['fulfilment'] = Variable<String>(fulfilment.value);
    }
    if (paymentMode.present) {
      map['payment_mode'] = Variable<String>(paymentMode.value);
    }
    if (subtotalPaise.present) {
      map['subtotal_paise'] = Variable<int>(subtotalPaise.value);
    }
    if (taxPaise.present) {
      map['tax_paise'] = Variable<int>(taxPaise.value);
    }
    if (totalPaise.present) {
      map['total_paise'] = Variable<int>(totalPaise.value);
    }
    if (estimatedTotalPaise.present) {
      map['estimated_total_paise'] = Variable<int>(estimatedTotalPaise.value);
    }
    if (placedAt.present) {
      map['placed_at'] = Variable<DateTime>(placedAt.value);
    }
    if (invoiceNo.present) {
      map['invoice_no'] = Variable<String>(invoiceNo.value);
    }
    if (invoiceId.present) {
      map['invoice_id'] = Variable<String>(invoiceId.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (events.present) {
      map['events'] = Variable<String>(events.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrdersCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('farmerId: $farmerId, ')
          ..write('storeId: $storeId, ')
          ..write('status: $status, ')
          ..write('fulfilment: $fulfilment, ')
          ..write('paymentMode: $paymentMode, ')
          ..write('subtotalPaise: $subtotalPaise, ')
          ..write('taxPaise: $taxPaise, ')
          ..write('totalPaise: $totalPaise, ')
          ..write('estimatedTotalPaise: $estimatedTotalPaise, ')
          ..write('placedAt: $placedAt, ')
          ..write('invoiceNo: $invoiceNo, ')
          ..write('invoiceId: $invoiceId, ')
          ..write('notes: $notes, ')
          ..write('events: $events, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OrderLinesTable extends OrderLines
    with TableInfo<$OrderLinesTable, OrderLineRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuIdMeta = const VerificationMeta('skuId');
  @override
  late final GeneratedColumn<String> skuId = GeneratedColumn<String>(
    'sku_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<double> qty = GeneratedColumn<double>(
    'qty',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitPricePaiseMeta = const VerificationMeta(
    'unitPricePaise',
  );
  @override
  late final GeneratedColumn<int> unitPricePaise = GeneratedColumn<int>(
    'unit_price_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lineTotalPaiseMeta = const VerificationMeta(
    'lineTotalPaise',
  );
  @override
  late final GeneratedColumn<int> lineTotalPaise = GeneratedColumn<int>(
    'line_total_paise',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedUnitPricePaiseMeta =
      const VerificationMeta('estimatedUnitPricePaise');
  @override
  late final GeneratedColumn<int> estimatedUnitPricePaise =
      GeneratedColumn<int>(
        'estimated_unit_price_paise',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _productNameMeta = const VerificationMeta(
    'productName',
  );
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
    'product_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _packLabelMeta = const VerificationMeta(
    'packLabel',
  );
  @override
  late final GeneratedColumn<String> packLabel = GeneratedColumn<String>(
    'pack_label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _labelClaimIdMeta = const VerificationMeta(
    'labelClaimId',
  );
  @override
  late final GeneratedColumn<String> labelClaimId = GeneratedColumn<String>(
    'label_claim_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orderId,
    skuId,
    qty,
    unitPricePaise,
    lineTotalPaise,
    estimatedUnitPricePaise,
    productName,
    packLabel,
    labelClaimId,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<OrderLineRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('sku_id')) {
      context.handle(
        _skuIdMeta,
        skuId.isAcceptableOrUnknown(data['sku_id']!, _skuIdMeta),
      );
    } else if (isInserting) {
      context.missing(_skuIdMeta);
    }
    if (data.containsKey('qty')) {
      context.handle(
        _qtyMeta,
        qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta),
      );
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    if (data.containsKey('unit_price_paise')) {
      context.handle(
        _unitPricePaiseMeta,
        unitPricePaise.isAcceptableOrUnknown(
          data['unit_price_paise']!,
          _unitPricePaiseMeta,
        ),
      );
    }
    if (data.containsKey('line_total_paise')) {
      context.handle(
        _lineTotalPaiseMeta,
        lineTotalPaise.isAcceptableOrUnknown(
          data['line_total_paise']!,
          _lineTotalPaiseMeta,
        ),
      );
    }
    if (data.containsKey('estimated_unit_price_paise')) {
      context.handle(
        _estimatedUnitPricePaiseMeta,
        estimatedUnitPricePaise.isAcceptableOrUnknown(
          data['estimated_unit_price_paise']!,
          _estimatedUnitPricePaiseMeta,
        ),
      );
    }
    if (data.containsKey('product_name')) {
      context.handle(
        _productNameMeta,
        productName.isAcceptableOrUnknown(
          data['product_name']!,
          _productNameMeta,
        ),
      );
    }
    if (data.containsKey('pack_label')) {
      context.handle(
        _packLabelMeta,
        packLabel.isAcceptableOrUnknown(data['pack_label']!, _packLabelMeta),
      );
    }
    if (data.containsKey('label_claim_id')) {
      context.handle(
        _labelClaimIdMeta,
        labelClaimId.isAcceptableOrUnknown(
          data['label_claim_id']!,
          _labelClaimIdMeta,
        ),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderLineRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderLineRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_id'],
      )!,
      skuId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku_id'],
      )!,
      qty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}qty'],
      )!,
      unitPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price_paise'],
      ),
      lineTotalPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_total_paise'],
      ),
      estimatedUnitPricePaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_unit_price_paise'],
      )!,
      productName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_name'],
      )!,
      packLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_label'],
      )!,
      labelClaimId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label_claim_id'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $OrderLinesTable createAlias(String alias) {
    return $OrderLinesTable(attachedDatabase, alias);
  }
}

class OrderLineRow extends DataClass implements Insertable<OrderLineRow> {
  /// Line id (device id until applied, then the server's).
  final String id;

  /// Owning order.
  final String orderId;

  /// SKU.
  final String skuId;

  /// Quantity.
  final double qty;

  /// Server unit price (paise).
  final int? unitPricePaise;

  /// Server line total incl. tax (paise).
  final int? lineTotalPaise;

  /// Device estimate of the unit price (paise).
  final int estimatedUnitPricePaise;

  /// Product name at capture (display).
  final String productName;

  /// Pack label at capture (display).
  final String packLabel;

  /// DX-007 claim the SKU was recommended under, if any.
  final String? labelClaimId;

  /// Position in the order.
  final int position;
  const OrderLineRow({
    required this.id,
    required this.orderId,
    required this.skuId,
    required this.qty,
    this.unitPricePaise,
    this.lineTotalPaise,
    required this.estimatedUnitPricePaise,
    required this.productName,
    required this.packLabel,
    this.labelClaimId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['order_id'] = Variable<String>(orderId);
    map['sku_id'] = Variable<String>(skuId);
    map['qty'] = Variable<double>(qty);
    if (!nullToAbsent || unitPricePaise != null) {
      map['unit_price_paise'] = Variable<int>(unitPricePaise);
    }
    if (!nullToAbsent || lineTotalPaise != null) {
      map['line_total_paise'] = Variable<int>(lineTotalPaise);
    }
    map['estimated_unit_price_paise'] = Variable<int>(estimatedUnitPricePaise);
    map['product_name'] = Variable<String>(productName);
    map['pack_label'] = Variable<String>(packLabel);
    if (!nullToAbsent || labelClaimId != null) {
      map['label_claim_id'] = Variable<String>(labelClaimId);
    }
    map['position'] = Variable<int>(position);
    return map;
  }

  OrderLinesCompanion toCompanion(bool nullToAbsent) {
    return OrderLinesCompanion(
      id: Value(id),
      orderId: Value(orderId),
      skuId: Value(skuId),
      qty: Value(qty),
      unitPricePaise: unitPricePaise == null && nullToAbsent
          ? const Value.absent()
          : Value(unitPricePaise),
      lineTotalPaise: lineTotalPaise == null && nullToAbsent
          ? const Value.absent()
          : Value(lineTotalPaise),
      estimatedUnitPricePaise: Value(estimatedUnitPricePaise),
      productName: Value(productName),
      packLabel: Value(packLabel),
      labelClaimId: labelClaimId == null && nullToAbsent
          ? const Value.absent()
          : Value(labelClaimId),
      position: Value(position),
    );
  }

  factory OrderLineRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderLineRow(
      id: serializer.fromJson<String>(json['id']),
      orderId: serializer.fromJson<String>(json['orderId']),
      skuId: serializer.fromJson<String>(json['skuId']),
      qty: serializer.fromJson<double>(json['qty']),
      unitPricePaise: serializer.fromJson<int?>(json['unitPricePaise']),
      lineTotalPaise: serializer.fromJson<int?>(json['lineTotalPaise']),
      estimatedUnitPricePaise: serializer.fromJson<int>(
        json['estimatedUnitPricePaise'],
      ),
      productName: serializer.fromJson<String>(json['productName']),
      packLabel: serializer.fromJson<String>(json['packLabel']),
      labelClaimId: serializer.fromJson<String?>(json['labelClaimId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orderId': serializer.toJson<String>(orderId),
      'skuId': serializer.toJson<String>(skuId),
      'qty': serializer.toJson<double>(qty),
      'unitPricePaise': serializer.toJson<int?>(unitPricePaise),
      'lineTotalPaise': serializer.toJson<int?>(lineTotalPaise),
      'estimatedUnitPricePaise': serializer.toJson<int>(
        estimatedUnitPricePaise,
      ),
      'productName': serializer.toJson<String>(productName),
      'packLabel': serializer.toJson<String>(packLabel),
      'labelClaimId': serializer.toJson<String?>(labelClaimId),
      'position': serializer.toJson<int>(position),
    };
  }

  OrderLineRow copyWith({
    String? id,
    String? orderId,
    String? skuId,
    double? qty,
    Value<int?> unitPricePaise = const Value.absent(),
    Value<int?> lineTotalPaise = const Value.absent(),
    int? estimatedUnitPricePaise,
    String? productName,
    String? packLabel,
    Value<String?> labelClaimId = const Value.absent(),
    int? position,
  }) => OrderLineRow(
    id: id ?? this.id,
    orderId: orderId ?? this.orderId,
    skuId: skuId ?? this.skuId,
    qty: qty ?? this.qty,
    unitPricePaise: unitPricePaise.present
        ? unitPricePaise.value
        : this.unitPricePaise,
    lineTotalPaise: lineTotalPaise.present
        ? lineTotalPaise.value
        : this.lineTotalPaise,
    estimatedUnitPricePaise:
        estimatedUnitPricePaise ?? this.estimatedUnitPricePaise,
    productName: productName ?? this.productName,
    packLabel: packLabel ?? this.packLabel,
    labelClaimId: labelClaimId.present ? labelClaimId.value : this.labelClaimId,
    position: position ?? this.position,
  );
  OrderLineRow copyWithCompanion(OrderLinesCompanion data) {
    return OrderLineRow(
      id: data.id.present ? data.id.value : this.id,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      skuId: data.skuId.present ? data.skuId.value : this.skuId,
      qty: data.qty.present ? data.qty.value : this.qty,
      unitPricePaise: data.unitPricePaise.present
          ? data.unitPricePaise.value
          : this.unitPricePaise,
      lineTotalPaise: data.lineTotalPaise.present
          ? data.lineTotalPaise.value
          : this.lineTotalPaise,
      estimatedUnitPricePaise: data.estimatedUnitPricePaise.present
          ? data.estimatedUnitPricePaise.value
          : this.estimatedUnitPricePaise,
      productName: data.productName.present
          ? data.productName.value
          : this.productName,
      packLabel: data.packLabel.present ? data.packLabel.value : this.packLabel,
      labelClaimId: data.labelClaimId.present
          ? data.labelClaimId.value
          : this.labelClaimId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderLineRow(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('skuId: $skuId, ')
          ..write('qty: $qty, ')
          ..write('unitPricePaise: $unitPricePaise, ')
          ..write('lineTotalPaise: $lineTotalPaise, ')
          ..write('estimatedUnitPricePaise: $estimatedUnitPricePaise, ')
          ..write('productName: $productName, ')
          ..write('packLabel: $packLabel, ')
          ..write('labelClaimId: $labelClaimId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orderId,
    skuId,
    qty,
    unitPricePaise,
    lineTotalPaise,
    estimatedUnitPricePaise,
    productName,
    packLabel,
    labelClaimId,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderLineRow &&
          other.id == this.id &&
          other.orderId == this.orderId &&
          other.skuId == this.skuId &&
          other.qty == this.qty &&
          other.unitPricePaise == this.unitPricePaise &&
          other.lineTotalPaise == this.lineTotalPaise &&
          other.estimatedUnitPricePaise == this.estimatedUnitPricePaise &&
          other.productName == this.productName &&
          other.packLabel == this.packLabel &&
          other.labelClaimId == this.labelClaimId &&
          other.position == this.position);
}

class OrderLinesCompanion extends UpdateCompanion<OrderLineRow> {
  final Value<String> id;
  final Value<String> orderId;
  final Value<String> skuId;
  final Value<double> qty;
  final Value<int?> unitPricePaise;
  final Value<int?> lineTotalPaise;
  final Value<int> estimatedUnitPricePaise;
  final Value<String> productName;
  final Value<String> packLabel;
  final Value<String?> labelClaimId;
  final Value<int> position;
  final Value<int> rowid;
  const OrderLinesCompanion({
    this.id = const Value.absent(),
    this.orderId = const Value.absent(),
    this.skuId = const Value.absent(),
    this.qty = const Value.absent(),
    this.unitPricePaise = const Value.absent(),
    this.lineTotalPaise = const Value.absent(),
    this.estimatedUnitPricePaise = const Value.absent(),
    this.productName = const Value.absent(),
    this.packLabel = const Value.absent(),
    this.labelClaimId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrderLinesCompanion.insert({
    required String id,
    required String orderId,
    required String skuId,
    required double qty,
    this.unitPricePaise = const Value.absent(),
    this.lineTotalPaise = const Value.absent(),
    this.estimatedUnitPricePaise = const Value.absent(),
    this.productName = const Value.absent(),
    this.packLabel = const Value.absent(),
    this.labelClaimId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orderId = Value(orderId),
       skuId = Value(skuId),
       qty = Value(qty);
  static Insertable<OrderLineRow> custom({
    Expression<String>? id,
    Expression<String>? orderId,
    Expression<String>? skuId,
    Expression<double>? qty,
    Expression<int>? unitPricePaise,
    Expression<int>? lineTotalPaise,
    Expression<int>? estimatedUnitPricePaise,
    Expression<String>? productName,
    Expression<String>? packLabel,
    Expression<String>? labelClaimId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (skuId != null) 'sku_id': skuId,
      if (qty != null) 'qty': qty,
      if (unitPricePaise != null) 'unit_price_paise': unitPricePaise,
      if (lineTotalPaise != null) 'line_total_paise': lineTotalPaise,
      if (estimatedUnitPricePaise != null)
        'estimated_unit_price_paise': estimatedUnitPricePaise,
      if (productName != null) 'product_name': productName,
      if (packLabel != null) 'pack_label': packLabel,
      if (labelClaimId != null) 'label_claim_id': labelClaimId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrderLinesCompanion copyWith({
    Value<String>? id,
    Value<String>? orderId,
    Value<String>? skuId,
    Value<double>? qty,
    Value<int?>? unitPricePaise,
    Value<int?>? lineTotalPaise,
    Value<int>? estimatedUnitPricePaise,
    Value<String>? productName,
    Value<String>? packLabel,
    Value<String?>? labelClaimId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return OrderLinesCompanion(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      skuId: skuId ?? this.skuId,
      qty: qty ?? this.qty,
      unitPricePaise: unitPricePaise ?? this.unitPricePaise,
      lineTotalPaise: lineTotalPaise ?? this.lineTotalPaise,
      estimatedUnitPricePaise:
          estimatedUnitPricePaise ?? this.estimatedUnitPricePaise,
      productName: productName ?? this.productName,
      packLabel: packLabel ?? this.packLabel,
      labelClaimId: labelClaimId ?? this.labelClaimId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (skuId.present) {
      map['sku_id'] = Variable<String>(skuId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<double>(qty.value);
    }
    if (unitPricePaise.present) {
      map['unit_price_paise'] = Variable<int>(unitPricePaise.value);
    }
    if (lineTotalPaise.present) {
      map['line_total_paise'] = Variable<int>(lineTotalPaise.value);
    }
    if (estimatedUnitPricePaise.present) {
      map['estimated_unit_price_paise'] = Variable<int>(
        estimatedUnitPricePaise.value,
      );
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (packLabel.present) {
      map['pack_label'] = Variable<String>(packLabel.value);
    }
    if (labelClaimId.present) {
      map['label_claim_id'] = Variable<String>(labelClaimId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderLinesCompanion(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('skuId: $skuId, ')
          ..write('qty: $qty, ')
          ..write('unitPricePaise: $unitPricePaise, ')
          ..write('lineTotalPaise: $lineTotalPaise, ')
          ..write('estimatedUnitPricePaise: $estimatedUnitPricePaise, ')
          ..write('productName: $productName, ')
          ..write('packLabel: $packLabel, ')
          ..write('labelClaimId: $labelClaimId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PaymentsTable extends Payments
    with TableInfo<$PaymentsTable, PaymentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<String> orderId = GeneratedColumn<String>(
    'order_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _farmerIdMeta = const VerificationMeta(
    'farmerId',
  );
  @override
  late final GeneratedColumn<String> farmerId = GeneratedColumn<String>(
    'farmer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _storeIdMeta = const VerificationMeta(
    'storeId',
  );
  @override
  late final GeneratedColumn<String> storeId = GeneratedColumn<String>(
    'store_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountPaiseMeta = const VerificationMeta(
    'amountPaise',
  );
  @override
  late final GeneratedColumn<int> amountPaise = GeneratedColumn<int>(
    'amount_paise',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _receiptUriMeta = const VerificationMeta(
    'receiptUri',
  );
  @override
  late final GeneratedColumn<String> receiptUri = GeneratedColumn<String>(
    'receipt_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptPathMeta = const VerificationMeta(
    'receiptPath',
  );
  @override
  late final GeneratedColumn<String> receiptPath = GeneratedColumn<String>(
    'receipt_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _collectedByMeta = const VerificationMeta(
    'collectedBy',
  );
  @override
  late final GeneratedColumn<String> collectedBy = GeneratedColumn<String>(
    'collected_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _collectedAtMeta = const VerificationMeta(
    'collectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> collectedAt = GeneratedColumn<DateTime>(
    'collected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paidAtMeta = const VerificationMeta('paidAt');
  @override
  late final GeneratedColumn<DateTime> paidAt = GeneratedColumn<DateTime>(
    'paid_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shortUrlMeta = const VerificationMeta(
    'shortUrl',
  );
  @override
  late final GeneratedColumn<String> shortUrl = GeneratedColumn<String>(
    'short_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sentViaMeta = const VerificationMeta(
    'sentVia',
  );
  @override
  late final GeneratedColumn<String> sentVia = GeneratedColumn<String>(
    'sent_via',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _qrPayloadMeta = const VerificationMeta(
    'qrPayload',
  );
  @override
  late final GeneratedColumn<String> qrPayload = GeneratedColumn<String>(
    'qr_payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    orderId,
    farmerId,
    storeId,
    mode,
    amountPaise,
    status,
    receiptUri,
    receiptPath,
    collectedBy,
    collectedAt,
    paidAt,
    expiresAt,
    shortUrl,
    sentVia,
    qrPayload,
    failureReason,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<PaymentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    }
    if (data.containsKey('farmer_id')) {
      context.handle(
        _farmerIdMeta,
        farmerId.isAcceptableOrUnknown(data['farmer_id']!, _farmerIdMeta),
      );
    }
    if (data.containsKey('store_id')) {
      context.handle(
        _storeIdMeta,
        storeId.isAcceptableOrUnknown(data['store_id']!, _storeIdMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('amount_paise')) {
      context.handle(
        _amountPaiseMeta,
        amountPaise.isAcceptableOrUnknown(
          data['amount_paise']!,
          _amountPaiseMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('receipt_uri')) {
      context.handle(
        _receiptUriMeta,
        receiptUri.isAcceptableOrUnknown(data['receipt_uri']!, _receiptUriMeta),
      );
    }
    if (data.containsKey('receipt_path')) {
      context.handle(
        _receiptPathMeta,
        receiptPath.isAcceptableOrUnknown(
          data['receipt_path']!,
          _receiptPathMeta,
        ),
      );
    }
    if (data.containsKey('collected_by')) {
      context.handle(
        _collectedByMeta,
        collectedBy.isAcceptableOrUnknown(
          data['collected_by']!,
          _collectedByMeta,
        ),
      );
    }
    if (data.containsKey('collected_at')) {
      context.handle(
        _collectedAtMeta,
        collectedAt.isAcceptableOrUnknown(
          data['collected_at']!,
          _collectedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectedAtMeta);
    }
    if (data.containsKey('paid_at')) {
      context.handle(
        _paidAtMeta,
        paidAt.isAcceptableOrUnknown(data['paid_at']!, _paidAtMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('short_url')) {
      context.handle(
        _shortUrlMeta,
        shortUrl.isAcceptableOrUnknown(data['short_url']!, _shortUrlMeta),
      );
    }
    if (data.containsKey('sent_via')) {
      context.handle(
        _sentViaMeta,
        sentVia.isAcceptableOrUnknown(data['sent_via']!, _sentViaMeta),
      );
    }
    if (data.containsKey('qr_payload')) {
      context.handle(
        _qrPayloadMeta,
        qrPayload.isAcceptableOrUnknown(data['qr_payload']!, _qrPayloadMeta),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PaymentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PaymentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_id'],
      ),
      farmerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farmer_id'],
      ),
      storeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}store_id'],
      ),
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      amountPaise: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_paise'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      receiptUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_uri'],
      ),
      receiptPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_path'],
      ),
      collectedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collected_by'],
      ),
      collectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}collected_at'],
      )!,
      paidAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paid_at'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      shortUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}short_url'],
      ),
      sentVia: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sent_via'],
      ),
      qrPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}qr_payload'],
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      )!,
    );
  }

  @override
  $PaymentsTable createAlias(String alias) {
    return $PaymentsTable(attachedDatabase, alias);
  }
}

class PaymentRow extends DataClass implements Insertable<PaymentRow> {
  /// Client-generated uuid, also the server id.
  final String id;

  /// Server row version; 0 while the create is still queued.
  final int version;

  /// Last local write (UTC).
  final DateTime updatedAt;

  /// A queued op still references this row.
  final bool dirty;

  /// Deleted locally; removed once the server confirms.
  final bool deleted;

  /// Order paid for (null for khata dues).
  final String? orderId;

  /// Farmer.
  final String? farmerId;

  /// Store.
  final String? storeId;

  /// `upi_qr` | `payment_link` | `cash` | `card_terminal` | `credit`.
  final String mode;

  /// Amount (paise): the device's expectation until the server answers.
  final int amountPaise;

  /// `queued` (device only) | `created` | `pending` |
  /// `pending_reconciliation` | `paid` | `failed` | `refunded` |
  /// `reconciled`.
  final String status;

  /// Cash receipt blob URI (or `upload:<id>` while queued).
  final String? receiptUri;

  /// Local file of the receipt photo.
  final String? receiptPath;

  /// Collecting user (server).
  final String? collectedBy;

  /// When the officer collected / requested it (UTC).
  final DateTime collectedAt;

  /// When the server marked it paid (UTC).
  final DateTime? paidAt;

  /// UPI QR / link expiry (UTC).
  final DateTime? expiresAt;

  /// Payment link URL.
  final String? shortUrl;

  /// `sms` | `whatsapp` (payment link).
  final String? sentVia;

  /// UPI QR payload (A53, while waiting).
  final String? qrPayload;

  /// Provider failure reason.
  final String? failureReason;

  /// JSON of server fields this app does not model.
  final String extra;
  const PaymentRow({
    required this.id,
    required this.version,
    required this.updatedAt,
    required this.dirty,
    required this.deleted,
    this.orderId,
    this.farmerId,
    this.storeId,
    required this.mode,
    required this.amountPaise,
    required this.status,
    this.receiptUri,
    this.receiptPath,
    this.collectedBy,
    required this.collectedAt,
    this.paidAt,
    this.expiresAt,
    this.shortUrl,
    this.sentVia,
    this.qrPayload,
    this.failureReason,
    required this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || orderId != null) {
      map['order_id'] = Variable<String>(orderId);
    }
    if (!nullToAbsent || farmerId != null) {
      map['farmer_id'] = Variable<String>(farmerId);
    }
    if (!nullToAbsent || storeId != null) {
      map['store_id'] = Variable<String>(storeId);
    }
    map['mode'] = Variable<String>(mode);
    map['amount_paise'] = Variable<int>(amountPaise);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || receiptUri != null) {
      map['receipt_uri'] = Variable<String>(receiptUri);
    }
    if (!nullToAbsent || receiptPath != null) {
      map['receipt_path'] = Variable<String>(receiptPath);
    }
    if (!nullToAbsent || collectedBy != null) {
      map['collected_by'] = Variable<String>(collectedBy);
    }
    map['collected_at'] = Variable<DateTime>(collectedAt);
    if (!nullToAbsent || paidAt != null) {
      map['paid_at'] = Variable<DateTime>(paidAt);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || shortUrl != null) {
      map['short_url'] = Variable<String>(shortUrl);
    }
    if (!nullToAbsent || sentVia != null) {
      map['sent_via'] = Variable<String>(sentVia);
    }
    if (!nullToAbsent || qrPayload != null) {
      map['qr_payload'] = Variable<String>(qrPayload);
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    map['extra'] = Variable<String>(extra);
    return map;
  }

  PaymentsCompanion toCompanion(bool nullToAbsent) {
    return PaymentsCompanion(
      id: Value(id),
      version: Value(version),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
      deleted: Value(deleted),
      orderId: orderId == null && nullToAbsent
          ? const Value.absent()
          : Value(orderId),
      farmerId: farmerId == null && nullToAbsent
          ? const Value.absent()
          : Value(farmerId),
      storeId: storeId == null && nullToAbsent
          ? const Value.absent()
          : Value(storeId),
      mode: Value(mode),
      amountPaise: Value(amountPaise),
      status: Value(status),
      receiptUri: receiptUri == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptUri),
      receiptPath: receiptPath == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptPath),
      collectedBy: collectedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(collectedBy),
      collectedAt: Value(collectedAt),
      paidAt: paidAt == null && nullToAbsent
          ? const Value.absent()
          : Value(paidAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      shortUrl: shortUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(shortUrl),
      sentVia: sentVia == null && nullToAbsent
          ? const Value.absent()
          : Value(sentVia),
      qrPayload: qrPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(qrPayload),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      extra: Value(extra),
    );
  }

  factory PaymentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PaymentRow(
      id: serializer.fromJson<String>(json['id']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      orderId: serializer.fromJson<String?>(json['orderId']),
      farmerId: serializer.fromJson<String?>(json['farmerId']),
      storeId: serializer.fromJson<String?>(json['storeId']),
      mode: serializer.fromJson<String>(json['mode']),
      amountPaise: serializer.fromJson<int>(json['amountPaise']),
      status: serializer.fromJson<String>(json['status']),
      receiptUri: serializer.fromJson<String?>(json['receiptUri']),
      receiptPath: serializer.fromJson<String?>(json['receiptPath']),
      collectedBy: serializer.fromJson<String?>(json['collectedBy']),
      collectedAt: serializer.fromJson<DateTime>(json['collectedAt']),
      paidAt: serializer.fromJson<DateTime?>(json['paidAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      shortUrl: serializer.fromJson<String?>(json['shortUrl']),
      sentVia: serializer.fromJson<String?>(json['sentVia']),
      qrPayload: serializer.fromJson<String?>(json['qrPayload']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      extra: serializer.fromJson<String>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
      'deleted': serializer.toJson<bool>(deleted),
      'orderId': serializer.toJson<String?>(orderId),
      'farmerId': serializer.toJson<String?>(farmerId),
      'storeId': serializer.toJson<String?>(storeId),
      'mode': serializer.toJson<String>(mode),
      'amountPaise': serializer.toJson<int>(amountPaise),
      'status': serializer.toJson<String>(status),
      'receiptUri': serializer.toJson<String?>(receiptUri),
      'receiptPath': serializer.toJson<String?>(receiptPath),
      'collectedBy': serializer.toJson<String?>(collectedBy),
      'collectedAt': serializer.toJson<DateTime>(collectedAt),
      'paidAt': serializer.toJson<DateTime?>(paidAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'shortUrl': serializer.toJson<String?>(shortUrl),
      'sentVia': serializer.toJson<String?>(sentVia),
      'qrPayload': serializer.toJson<String?>(qrPayload),
      'failureReason': serializer.toJson<String?>(failureReason),
      'extra': serializer.toJson<String>(extra),
    };
  }

  PaymentRow copyWith({
    String? id,
    int? version,
    DateTime? updatedAt,
    bool? dirty,
    bool? deleted,
    Value<String?> orderId = const Value.absent(),
    Value<String?> farmerId = const Value.absent(),
    Value<String?> storeId = const Value.absent(),
    String? mode,
    int? amountPaise,
    String? status,
    Value<String?> receiptUri = const Value.absent(),
    Value<String?> receiptPath = const Value.absent(),
    Value<String?> collectedBy = const Value.absent(),
    DateTime? collectedAt,
    Value<DateTime?> paidAt = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<String?> shortUrl = const Value.absent(),
    Value<String?> sentVia = const Value.absent(),
    Value<String?> qrPayload = const Value.absent(),
    Value<String?> failureReason = const Value.absent(),
    String? extra,
  }) => PaymentRow(
    id: id ?? this.id,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    orderId: orderId.present ? orderId.value : this.orderId,
    farmerId: farmerId.present ? farmerId.value : this.farmerId,
    storeId: storeId.present ? storeId.value : this.storeId,
    mode: mode ?? this.mode,
    amountPaise: amountPaise ?? this.amountPaise,
    status: status ?? this.status,
    receiptUri: receiptUri.present ? receiptUri.value : this.receiptUri,
    receiptPath: receiptPath.present ? receiptPath.value : this.receiptPath,
    collectedBy: collectedBy.present ? collectedBy.value : this.collectedBy,
    collectedAt: collectedAt ?? this.collectedAt,
    paidAt: paidAt.present ? paidAt.value : this.paidAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    shortUrl: shortUrl.present ? shortUrl.value : this.shortUrl,
    sentVia: sentVia.present ? sentVia.value : this.sentVia,
    qrPayload: qrPayload.present ? qrPayload.value : this.qrPayload,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    extra: extra ?? this.extra,
  );
  PaymentRow copyWithCompanion(PaymentsCompanion data) {
    return PaymentRow(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      farmerId: data.farmerId.present ? data.farmerId.value : this.farmerId,
      storeId: data.storeId.present ? data.storeId.value : this.storeId,
      mode: data.mode.present ? data.mode.value : this.mode,
      amountPaise: data.amountPaise.present
          ? data.amountPaise.value
          : this.amountPaise,
      status: data.status.present ? data.status.value : this.status,
      receiptUri: data.receiptUri.present
          ? data.receiptUri.value
          : this.receiptUri,
      receiptPath: data.receiptPath.present
          ? data.receiptPath.value
          : this.receiptPath,
      collectedBy: data.collectedBy.present
          ? data.collectedBy.value
          : this.collectedBy,
      collectedAt: data.collectedAt.present
          ? data.collectedAt.value
          : this.collectedAt,
      paidAt: data.paidAt.present ? data.paidAt.value : this.paidAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      shortUrl: data.shortUrl.present ? data.shortUrl.value : this.shortUrl,
      sentVia: data.sentVia.present ? data.sentVia.value : this.sentVia,
      qrPayload: data.qrPayload.present ? data.qrPayload.value : this.qrPayload,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PaymentRow(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('orderId: $orderId, ')
          ..write('farmerId: $farmerId, ')
          ..write('storeId: $storeId, ')
          ..write('mode: $mode, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('status: $status, ')
          ..write('receiptUri: $receiptUri, ')
          ..write('receiptPath: $receiptPath, ')
          ..write('collectedBy: $collectedBy, ')
          ..write('collectedAt: $collectedAt, ')
          ..write('paidAt: $paidAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('shortUrl: $shortUrl, ')
          ..write('sentVia: $sentVia, ')
          ..write('qrPayload: $qrPayload, ')
          ..write('failureReason: $failureReason, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    version,
    updatedAt,
    dirty,
    deleted,
    orderId,
    farmerId,
    storeId,
    mode,
    amountPaise,
    status,
    receiptUri,
    receiptPath,
    collectedBy,
    collectedAt,
    paidAt,
    expiresAt,
    shortUrl,
    sentVia,
    qrPayload,
    failureReason,
    extra,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaymentRow &&
          other.id == this.id &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty &&
          other.deleted == this.deleted &&
          other.orderId == this.orderId &&
          other.farmerId == this.farmerId &&
          other.storeId == this.storeId &&
          other.mode == this.mode &&
          other.amountPaise == this.amountPaise &&
          other.status == this.status &&
          other.receiptUri == this.receiptUri &&
          other.receiptPath == this.receiptPath &&
          other.collectedBy == this.collectedBy &&
          other.collectedAt == this.collectedAt &&
          other.paidAt == this.paidAt &&
          other.expiresAt == this.expiresAt &&
          other.shortUrl == this.shortUrl &&
          other.sentVia == this.sentVia &&
          other.qrPayload == this.qrPayload &&
          other.failureReason == this.failureReason &&
          other.extra == this.extra);
}

class PaymentsCompanion extends UpdateCompanion<PaymentRow> {
  final Value<String> id;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<bool> dirty;
  final Value<bool> deleted;
  final Value<String?> orderId;
  final Value<String?> farmerId;
  final Value<String?> storeId;
  final Value<String> mode;
  final Value<int> amountPaise;
  final Value<String> status;
  final Value<String?> receiptUri;
  final Value<String?> receiptPath;
  final Value<String?> collectedBy;
  final Value<DateTime> collectedAt;
  final Value<DateTime?> paidAt;
  final Value<DateTime?> expiresAt;
  final Value<String?> shortUrl;
  final Value<String?> sentVia;
  final Value<String?> qrPayload;
  final Value<String?> failureReason;
  final Value<String> extra;
  final Value<int> rowid;
  const PaymentsCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.orderId = const Value.absent(),
    this.farmerId = const Value.absent(),
    this.storeId = const Value.absent(),
    this.mode = const Value.absent(),
    this.amountPaise = const Value.absent(),
    this.status = const Value.absent(),
    this.receiptUri = const Value.absent(),
    this.receiptPath = const Value.absent(),
    this.collectedBy = const Value.absent(),
    this.collectedAt = const Value.absent(),
    this.paidAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.shortUrl = const Value.absent(),
    this.sentVia = const Value.absent(),
    this.qrPayload = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PaymentsCompanion.insert({
    required String id,
    this.version = const Value.absent(),
    required DateTime updatedAt,
    this.dirty = const Value.absent(),
    this.deleted = const Value.absent(),
    this.orderId = const Value.absent(),
    this.farmerId = const Value.absent(),
    this.storeId = const Value.absent(),
    required String mode,
    this.amountPaise = const Value.absent(),
    this.status = const Value.absent(),
    this.receiptUri = const Value.absent(),
    this.receiptPath = const Value.absent(),
    this.collectedBy = const Value.absent(),
    required DateTime collectedAt,
    this.paidAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.shortUrl = const Value.absent(),
    this.sentVia = const Value.absent(),
    this.qrPayload = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt),
       mode = Value(mode),
       collectedAt = Value(collectedAt);
  static Insertable<PaymentRow> custom({
    Expression<String>? id,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<bool>? dirty,
    Expression<bool>? deleted,
    Expression<String>? orderId,
    Expression<String>? farmerId,
    Expression<String>? storeId,
    Expression<String>? mode,
    Expression<int>? amountPaise,
    Expression<String>? status,
    Expression<String>? receiptUri,
    Expression<String>? receiptPath,
    Expression<String>? collectedBy,
    Expression<DateTime>? collectedAt,
    Expression<DateTime>? paidAt,
    Expression<DateTime>? expiresAt,
    Expression<String>? shortUrl,
    Expression<String>? sentVia,
    Expression<String>? qrPayload,
    Expression<String>? failureReason,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (deleted != null) 'deleted': deleted,
      if (orderId != null) 'order_id': orderId,
      if (farmerId != null) 'farmer_id': farmerId,
      if (storeId != null) 'store_id': storeId,
      if (mode != null) 'mode': mode,
      if (amountPaise != null) 'amount_paise': amountPaise,
      if (status != null) 'status': status,
      if (receiptUri != null) 'receipt_uri': receiptUri,
      if (receiptPath != null) 'receipt_path': receiptPath,
      if (collectedBy != null) 'collected_by': collectedBy,
      if (collectedAt != null) 'collected_at': collectedAt,
      if (paidAt != null) 'paid_at': paidAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (shortUrl != null) 'short_url': shortUrl,
      if (sentVia != null) 'sent_via': sentVia,
      if (qrPayload != null) 'qr_payload': qrPayload,
      if (failureReason != null) 'failure_reason': failureReason,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PaymentsCompanion copyWith({
    Value<String>? id,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<bool>? dirty,
    Value<bool>? deleted,
    Value<String?>? orderId,
    Value<String?>? farmerId,
    Value<String?>? storeId,
    Value<String>? mode,
    Value<int>? amountPaise,
    Value<String>? status,
    Value<String?>? receiptUri,
    Value<String?>? receiptPath,
    Value<String?>? collectedBy,
    Value<DateTime>? collectedAt,
    Value<DateTime?>? paidAt,
    Value<DateTime?>? expiresAt,
    Value<String?>? shortUrl,
    Value<String?>? sentVia,
    Value<String?>? qrPayload,
    Value<String?>? failureReason,
    Value<String>? extra,
    Value<int>? rowid,
  }) {
    return PaymentsCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      deleted: deleted ?? this.deleted,
      orderId: orderId ?? this.orderId,
      farmerId: farmerId ?? this.farmerId,
      storeId: storeId ?? this.storeId,
      mode: mode ?? this.mode,
      amountPaise: amountPaise ?? this.amountPaise,
      status: status ?? this.status,
      receiptUri: receiptUri ?? this.receiptUri,
      receiptPath: receiptPath ?? this.receiptPath,
      collectedBy: collectedBy ?? this.collectedBy,
      collectedAt: collectedAt ?? this.collectedAt,
      paidAt: paidAt ?? this.paidAt,
      expiresAt: expiresAt ?? this.expiresAt,
      shortUrl: shortUrl ?? this.shortUrl,
      sentVia: sentVia ?? this.sentVia,
      qrPayload: qrPayload ?? this.qrPayload,
      failureReason: failureReason ?? this.failureReason,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<String>(orderId.value);
    }
    if (farmerId.present) {
      map['farmer_id'] = Variable<String>(farmerId.value);
    }
    if (storeId.present) {
      map['store_id'] = Variable<String>(storeId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (amountPaise.present) {
      map['amount_paise'] = Variable<int>(amountPaise.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (receiptUri.present) {
      map['receipt_uri'] = Variable<String>(receiptUri.value);
    }
    if (receiptPath.present) {
      map['receipt_path'] = Variable<String>(receiptPath.value);
    }
    if (collectedBy.present) {
      map['collected_by'] = Variable<String>(collectedBy.value);
    }
    if (collectedAt.present) {
      map['collected_at'] = Variable<DateTime>(collectedAt.value);
    }
    if (paidAt.present) {
      map['paid_at'] = Variable<DateTime>(paidAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (shortUrl.present) {
      map['short_url'] = Variable<String>(shortUrl.value);
    }
    if (sentVia.present) {
      map['sent_via'] = Variable<String>(sentVia.value);
    }
    if (qrPayload.present) {
      map['qr_payload'] = Variable<String>(qrPayload.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentsCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('deleted: $deleted, ')
          ..write('orderId: $orderId, ')
          ..write('farmerId: $farmerId, ')
          ..write('storeId: $storeId, ')
          ..write('mode: $mode, ')
          ..write('amountPaise: $amountPaise, ')
          ..write('status: $status, ')
          ..write('receiptUri: $receiptUri, ')
          ..write('receiptPath: $receiptPath, ')
          ..write('collectedBy: $collectedBy, ')
          ..write('collectedAt: $collectedAt, ')
          ..write('paidAt: $paidAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('shortUrl: $shortUrl, ')
          ..write('sentVia: $sentVia, ')
          ..write('qrPayload: $qrPayload, ')
          ..write('failureReason: $failureReason, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KhataSnapshotsTable extends KhataSnapshots
    with TableInfo<$KhataSnapshotsTable, KhataSnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KhataSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _farmerIdMeta = const VerificationMeta(
    'farmerId',
  );
  @override
  late final GeneratedColumn<String> farmerId = GeneratedColumn<String>(
    'farmer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [farmerId, data, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'khata_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<KhataSnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('farmer_id')) {
      context.handle(
        _farmerIdMeta,
        farmerId.isAcceptableOrUnknown(data['farmer_id']!, _farmerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_farmerIdMeta);
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    } else if (isInserting) {
      context.missing(_dataMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {farmerId};
  @override
  KhataSnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KhataSnapshotRow(
      farmerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}farmer_id'],
      )!,
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $KhataSnapshotsTable createAlias(String alias) {
    return $KhataSnapshotsTable(attachedDatabase, alias);
  }
}

class KhataSnapshotRow extends DataClass
    implements Insertable<KhataSnapshotRow> {
  /// Farmer.
  final String farmerId;

  /// The merged `KhataOut` JSON (all entries).
  final String data;

  /// When it was fetched (UTC).
  final DateTime fetchedAt;
  const KhataSnapshotRow({
    required this.farmerId,
    required this.data,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['farmer_id'] = Variable<String>(farmerId);
    map['data'] = Variable<String>(data);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  KhataSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return KhataSnapshotsCompanion(
      farmerId: Value(farmerId),
      data: Value(data),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory KhataSnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KhataSnapshotRow(
      farmerId: serializer.fromJson<String>(json['farmerId']),
      data: serializer.fromJson<String>(json['data']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'farmerId': serializer.toJson<String>(farmerId),
      'data': serializer.toJson<String>(data),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  KhataSnapshotRow copyWith({
    String? farmerId,
    String? data,
    DateTime? fetchedAt,
  }) => KhataSnapshotRow(
    farmerId: farmerId ?? this.farmerId,
    data: data ?? this.data,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  KhataSnapshotRow copyWithCompanion(KhataSnapshotsCompanion data) {
    return KhataSnapshotRow(
      farmerId: data.farmerId.present ? data.farmerId.value : this.farmerId,
      data: data.data.present ? data.data.value : this.data,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KhataSnapshotRow(')
          ..write('farmerId: $farmerId, ')
          ..write('data: $data, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(farmerId, data, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KhataSnapshotRow &&
          other.farmerId == this.farmerId &&
          other.data == this.data &&
          other.fetchedAt == this.fetchedAt);
}

class KhataSnapshotsCompanion extends UpdateCompanion<KhataSnapshotRow> {
  final Value<String> farmerId;
  final Value<String> data;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const KhataSnapshotsCompanion({
    this.farmerId = const Value.absent(),
    this.data = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KhataSnapshotsCompanion.insert({
    required String farmerId,
    required String data,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : farmerId = Value(farmerId),
       data = Value(data),
       fetchedAt = Value(fetchedAt);
  static Insertable<KhataSnapshotRow> custom({
    Expression<String>? farmerId,
    Expression<String>? data,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (farmerId != null) 'farmer_id': farmerId,
      if (data != null) 'data': data,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KhataSnapshotsCompanion copyWith({
    Value<String>? farmerId,
    Value<String>? data,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return KhataSnapshotsCompanion(
      farmerId: farmerId ?? this.farmerId,
      data: data ?? this.data,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (farmerId.present) {
      map['farmer_id'] = Variable<String>(farmerId.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KhataSnapshotsCompanion(')
          ..write('farmerId: $farmerId, ')
          ..write('data: $data, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $KvTable kv = $KvTable(this);
  late final $FarmersTable farmers = $FarmersTable(this);
  late final $FarmsTable farms = $FarmsTable(this);
  late final $CropPlotsTable cropPlots = $CropPlotsTable(this);
  late final $ConsentRecordsTable consentRecords = $ConsentRecordsTable(this);
  late final $OutboxTableTable outboxTable = $OutboxTableTable(this);
  late final $UploadsTable uploads = $UploadsTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  late final $SyncedRefsTable syncedRefs = $SyncedRefsTable(this);
  late final $VillagesTable villages = $VillagesTable(this);
  late final $DutySessionsTable dutySessions = $DutySessionsTable(this);
  late final $LocationBufferTable locationBuffer = $LocationBufferTable(this);
  late final $SyncDocsTable syncDocs = $SyncDocsTable(this);
  late final $VisitsTable visits = $VisitsTable(this);
  late final $VisitPhotosTable visitPhotos = $VisitPhotosTable(this);
  late final $VisitConfirmationsTable visitConfirmations =
      $VisitConfirmationsTable(this);
  late final $CatalogProductsTable catalogProducts = $CatalogProductsTable(
    this,
  );
  late final $CatalogSkusTable catalogSkus = $CatalogSkusTable(this);
  late final $CatalogPricesTable catalogPrices = $CatalogPricesTable(this);
  late final $StockSnapshotsTable stockSnapshots = $StockSnapshotsTable(this);
  late final $CatalogStoresTable catalogStores = $CatalogStoresTable(this);
  late final $OrdersTable orders = $OrdersTable(this);
  late final $OrderLinesTable orderLines = $OrderLinesTable(this);
  late final $PaymentsTable payments = $PaymentsTable(this);
  late final $KhataSnapshotsTable khataSnapshots = $KhataSnapshotsTable(this);
  late final Index outboxStateSeq = Index(
    'outbox_state_seq',
    'CREATE INDEX outbox_state_seq ON outbox (state, seq)',
  );
  late final Index outboxEntity = Index(
    'outbox_entity',
    'CREATE INDEX outbox_entity ON outbox (entity_id)',
  );
  late final Index locationBufferSession = Index(
    'location_buffer_session',
    'CREATE INDEX location_buffer_session ON location_buffer (session_id, ts)',
  );
  late final Index visitsCheckin = Index(
    'visits_checkin',
    'CREATE INDEX visits_checkin ON visits (checkin_at)',
  );
  late final Index visitPhotosVisit = Index(
    'visit_photos_visit',
    'CREATE INDEX visit_photos_visit ON visit_photos (visit_id)',
  );
  late final Index visitConfirmationsVisit = Index(
    'visit_confirmations_visit',
    'CREATE INDEX visit_confirmations_visit ON visit_confirmations (visit_id)',
  );
  late final Index catalogSkusProduct = Index(
    'catalog_skus_product',
    'CREATE INDEX catalog_skus_product ON catalog_skus (product_id)',
  );
  late final Index ordersFarmer = Index(
    'orders_farmer',
    'CREATE INDEX orders_farmer ON orders (farmer_id)',
  );
  late final Index orderLinesOrder = Index(
    'order_lines_order',
    'CREATE INDEX order_lines_order ON order_lines (order_id)',
  );
  late final Index paymentsCollected = Index(
    'payments_collected',
    'CREATE INDEX payments_collected ON payments (collected_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    kv,
    farmers,
    farms,
    cropPlots,
    consentRecords,
    outboxTable,
    uploads,
    syncStates,
    syncedRefs,
    villages,
    dutySessions,
    locationBuffer,
    syncDocs,
    visits,
    visitPhotos,
    visitConfirmations,
    catalogProducts,
    catalogSkus,
    catalogPrices,
    stockSnapshots,
    catalogStores,
    orders,
    orderLines,
    payments,
    khataSnapshots,
    outboxStateSeq,
    outboxEntity,
    locationBufferSession,
    visitsCheckin,
    visitPhotosVisit,
    visitConfirmationsVisit,
    catalogSkusProduct,
    ordersFarmer,
    orderLinesOrder,
    paymentsCollected,
  ];
}

typedef $$KvTableCreateCompanionBuilder = KvCompanion Function({
  required String key,
  required String value,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$KvTableUpdateCompanionBuilder = KvCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$KvTableFilterComposer extends Composer<_$AppDatabase, $KvTable> {
  $$KvTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KvTableOrderingComposer extends Composer<_$AppDatabase, $KvTable> {
  $$KvTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KvTableAnnotationComposer extends Composer<_$AppDatabase, $KvTable> {
  $$KvTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KvTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KvTable,
          KvData,
          $$KvTableFilterComposer,
          $$KvTableOrderingComposer,
          $$KvTableAnnotationComposer,
          $$KvTableCreateCompanionBuilder,
          $$KvTableUpdateCompanionBuilder,
          (KvData, BaseReferences<_$AppDatabase, $KvTable, KvData>),
          KvData,
          PrefetchHooks Function()
        > {
  $$KvTableTableManager(_$AppDatabase db, $KvTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KvCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => KvCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KvTable, KvData>(table),
                  BaseReferences<_$AppDatabase, $KvTable, KvData>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KvTable,
      KvData,
      $$KvTableFilterComposer,
      $$KvTableOrderingComposer,
      $$KvTableAnnotationComposer,
      $$KvTableCreateCompanionBuilder,
      $$KvTableUpdateCompanionBuilder,
      (KvData, BaseReferences<_$AppDatabase, $KvTable, KvData>),
      KvData,
      PrefetchHooks Function()
    >;
typedef $$FarmersTableCreateCompanionBuilder = FarmersCompanion Function({
  required String id,
  Value<int> version,
  required DateTime updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String?> phone,
  Value<String> name,
  Value<String?> villageId,
  Value<String?> landmark,
  Value<String?> language,
  Value<String?> preferredLanguage,
  Value<String?> landOwnership,
  Value<String?> source,
  Value<bool> phoneVerified,
  Value<bool> consentMarketing,
  Value<int> rowid,
});
typedef $$FarmersTableUpdateCompanionBuilder = FarmersCompanion Function({
  Value<String> id,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String?> phone,
  Value<String> name,
  Value<String?> villageId,
  Value<String?> landmark,
  Value<String?> language,
  Value<String?> preferredLanguage,
  Value<String?> landOwnership,
  Value<String?> source,
  Value<bool> phoneVerified,
  Value<bool> consentMarketing,
  Value<int> rowid,
});

class $$FarmersTableFilterComposer
    extends Composer<_$AppDatabase, $FarmersTable> {
  $$FarmersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get villageId => $composableBuilder(
    column: $table.villageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get landmark => $composableBuilder(
    column: $table.landmark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preferredLanguage => $composableBuilder(
    column: $table.preferredLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get landOwnership => $composableBuilder(
    column: $table.landOwnership,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get phoneVerified => $composableBuilder(
    column: $table.phoneVerified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get consentMarketing => $composableBuilder(
    column: $table.consentMarketing,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FarmersTableOrderingComposer
    extends Composer<_$AppDatabase, $FarmersTable> {
  $$FarmersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get villageId => $composableBuilder(
    column: $table.villageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get landmark => $composableBuilder(
    column: $table.landmark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preferredLanguage => $composableBuilder(
    column: $table.preferredLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get landOwnership => $composableBuilder(
    column: $table.landOwnership,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get phoneVerified => $composableBuilder(
    column: $table.phoneVerified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get consentMarketing => $composableBuilder(
    column: $table.consentMarketing,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FarmersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FarmersTable> {
  $$FarmersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get villageId =>
      $composableBuilder(column: $table.villageId, builder: (column) => column);

  GeneratedColumn<String> get landmark =>
      $composableBuilder(column: $table.landmark, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get preferredLanguage => $composableBuilder(
    column: $table.preferredLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get landOwnership => $composableBuilder(
    column: $table.landOwnership,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get phoneVerified => $composableBuilder(
    column: $table.phoneVerified,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get consentMarketing => $composableBuilder(
    column: $table.consentMarketing,
    builder: (column) => column,
  );
}

class $$FarmersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FarmersTable,
          Farmer,
          $$FarmersTableFilterComposer,
          $$FarmersTableOrderingComposer,
          $$FarmersTableAnnotationComposer,
          $$FarmersTableCreateCompanionBuilder,
          $$FarmersTableUpdateCompanionBuilder,
          (Farmer, BaseReferences<_$AppDatabase, $FarmersTable, Farmer>),
          Farmer,
          PrefetchHooks Function()
        > {
  $$FarmersTableTableManager(_$AppDatabase db, $FarmersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FarmersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FarmersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FarmersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> villageId = const Value.absent(),
                Value<String?> landmark = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String?> preferredLanguage = const Value.absent(),
                Value<String?> landOwnership = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<bool> phoneVerified = const Value.absent(),
                Value<bool> consentMarketing = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmersCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                phone: phone,
                name: name,
                villageId: villageId,
                landmark: landmark,
                language: language,
                preferredLanguage: preferredLanguage,
                landOwnership: landOwnership,
                source: source,
                phoneVerified: phoneVerified,
                consentMarketing: consentMarketing,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> villageId = const Value.absent(),
                Value<String?> landmark = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String?> preferredLanguage = const Value.absent(),
                Value<String?> landOwnership = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<bool> phoneVerified = const Value.absent(),
                Value<bool> consentMarketing = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmersCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                phone: phone,
                name: name,
                villageId: villageId,
                landmark: landmark,
                language: language,
                preferredLanguage: preferredLanguage,
                landOwnership: landOwnership,
                source: source,
                phoneVerified: phoneVerified,
                consentMarketing: consentMarketing,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FarmersTable, Farmer>(table),
                  BaseReferences<_$AppDatabase, $FarmersTable, Farmer>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FarmersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FarmersTable,
      Farmer,
      $$FarmersTableFilterComposer,
      $$FarmersTableOrderingComposer,
      $$FarmersTableAnnotationComposer,
      $$FarmersTableCreateCompanionBuilder,
      $$FarmersTableUpdateCompanionBuilder,
      (Farmer, BaseReferences<_$AppDatabase, $FarmersTable, Farmer>),
      Farmer,
      PrefetchHooks Function()
    >;
typedef $$FarmsTableCreateCompanionBuilder = FarmsCompanion Function({
  required String id,
  Value<int> version,
  required DateTime updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  required String farmerId,
  Value<String?> name,
  Value<String?> boundary,
  Value<double?> areaAcres,
  Value<String?> soil,
  Value<String?> irrigation,
  Value<String?> ownership,
  Value<String> photos,
  Value<int> rowid,
});
typedef $$FarmsTableUpdateCompanionBuilder = FarmsCompanion Function({
  Value<String> id,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String> farmerId,
  Value<String?> name,
  Value<String?> boundary,
  Value<double?> areaAcres,
  Value<String?> soil,
  Value<String?> irrigation,
  Value<String?> ownership,
  Value<String> photos,
  Value<int> rowid,
});

class $$FarmsTableFilterComposer extends Composer<_$AppDatabase, $FarmsTable> {
  $$FarmsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get boundary => $composableBuilder(
    column: $table.boundary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get areaAcres => $composableBuilder(
    column: $table.areaAcres,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get soil => $composableBuilder(
    column: $table.soil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get irrigation => $composableBuilder(
    column: $table.irrigation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownership => $composableBuilder(
    column: $table.ownership,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photos => $composableBuilder(
    column: $table.photos,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FarmsTableOrderingComposer
    extends Composer<_$AppDatabase, $FarmsTable> {
  $$FarmsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get boundary => $composableBuilder(
    column: $table.boundary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get areaAcres => $composableBuilder(
    column: $table.areaAcres,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get soil => $composableBuilder(
    column: $table.soil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get irrigation => $composableBuilder(
    column: $table.irrigation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownership => $composableBuilder(
    column: $table.ownership,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photos => $composableBuilder(
    column: $table.photos,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FarmsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FarmsTable> {
  $$FarmsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get farmerId =>
      $composableBuilder(column: $table.farmerId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get boundary =>
      $composableBuilder(column: $table.boundary, builder: (column) => column);

  GeneratedColumn<double> get areaAcres =>
      $composableBuilder(column: $table.areaAcres, builder: (column) => column);

  GeneratedColumn<String> get soil =>
      $composableBuilder(column: $table.soil, builder: (column) => column);

  GeneratedColumn<String> get irrigation => $composableBuilder(
    column: $table.irrigation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownership =>
      $composableBuilder(column: $table.ownership, builder: (column) => column);

  GeneratedColumn<String> get photos =>
      $composableBuilder(column: $table.photos, builder: (column) => column);
}

class $$FarmsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FarmsTable,
          Farm,
          $$FarmsTableFilterComposer,
          $$FarmsTableOrderingComposer,
          $$FarmsTableAnnotationComposer,
          $$FarmsTableCreateCompanionBuilder,
          $$FarmsTableUpdateCompanionBuilder,
          (Farm, BaseReferences<_$AppDatabase, $FarmsTable, Farm>),
          Farm,
          PrefetchHooks Function()
        > {
  $$FarmsTableTableManager(_$AppDatabase db, $FarmsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FarmsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FarmsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FarmsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> farmerId = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> boundary = const Value.absent(),
                Value<double?> areaAcres = const Value.absent(),
                Value<String?> soil = const Value.absent(),
                Value<String?> irrigation = const Value.absent(),
                Value<String?> ownership = const Value.absent(),
                Value<String> photos = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmsCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                name: name,
                boundary: boundary,
                areaAcres: areaAcres,
                soil: soil,
                irrigation: irrigation,
                ownership: ownership,
                photos: photos,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String farmerId,
                Value<String?> name = const Value.absent(),
                Value<String?> boundary = const Value.absent(),
                Value<double?> areaAcres = const Value.absent(),
                Value<String?> soil = const Value.absent(),
                Value<String?> irrigation = const Value.absent(),
                Value<String?> ownership = const Value.absent(),
                Value<String> photos = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FarmsCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                name: name,
                boundary: boundary,
                areaAcres: areaAcres,
                soil: soil,
                irrigation: irrigation,
                ownership: ownership,
                photos: photos,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FarmsTable, Farm>(table),
                  BaseReferences<_$AppDatabase, $FarmsTable, Farm>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FarmsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FarmsTable,
      Farm,
      $$FarmsTableFilterComposer,
      $$FarmsTableOrderingComposer,
      $$FarmsTableAnnotationComposer,
      $$FarmsTableCreateCompanionBuilder,
      $$FarmsTableUpdateCompanionBuilder,
      (Farm, BaseReferences<_$AppDatabase, $FarmsTable, Farm>),
      Farm,
      PrefetchHooks Function()
    >;
typedef $$CropPlotsTableCreateCompanionBuilder = CropPlotsCompanion Function({
  required String id,
  Value<int> version,
  required DateTime updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  required String farmId,
  Value<String?> cropId,
  Value<String?> variety,
  Value<String?> season,
  Value<String?> sowingDate,
  Value<String?> stage,
  Value<double?> areaAcres,
  Value<int> rowid,
});
typedef $$CropPlotsTableUpdateCompanionBuilder = CropPlotsCompanion Function({
  Value<String> id,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String> farmId,
  Value<String?> cropId,
  Value<String?> variety,
  Value<String?> season,
  Value<String?> sowingDate,
  Value<String?> stage,
  Value<double?> areaAcres,
  Value<int> rowid,
});

class $$CropPlotsTableFilterComposer
    extends Composer<_$AppDatabase, $CropPlotsTable> {
  $$CropPlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cropId => $composableBuilder(
    column: $table.cropId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variety => $composableBuilder(
    column: $table.variety,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sowingDate => $composableBuilder(
    column: $table.sowingDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get areaAcres => $composableBuilder(
    column: $table.areaAcres,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CropPlotsTableOrderingComposer
    extends Composer<_$AppDatabase, $CropPlotsTable> {
  $$CropPlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cropId => $composableBuilder(
    column: $table.cropId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variety => $composableBuilder(
    column: $table.variety,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get season => $composableBuilder(
    column: $table.season,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sowingDate => $composableBuilder(
    column: $table.sowingDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get areaAcres => $composableBuilder(
    column: $table.areaAcres,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CropPlotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CropPlotsTable> {
  $$CropPlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get cropId =>
      $composableBuilder(column: $table.cropId, builder: (column) => column);

  GeneratedColumn<String> get variety =>
      $composableBuilder(column: $table.variety, builder: (column) => column);

  GeneratedColumn<String> get season =>
      $composableBuilder(column: $table.season, builder: (column) => column);

  GeneratedColumn<String> get sowingDate => $composableBuilder(
    column: $table.sowingDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<double> get areaAcres =>
      $composableBuilder(column: $table.areaAcres, builder: (column) => column);
}

class $$CropPlotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CropPlotsTable,
          CropPlot,
          $$CropPlotsTableFilterComposer,
          $$CropPlotsTableOrderingComposer,
          $$CropPlotsTableAnnotationComposer,
          $$CropPlotsTableCreateCompanionBuilder,
          $$CropPlotsTableUpdateCompanionBuilder,
          (CropPlot, BaseReferences<_$AppDatabase, $CropPlotsTable, CropPlot>),
          CropPlot,
          PrefetchHooks Function()
        > {
  $$CropPlotsTableTableManager(_$AppDatabase db, $CropPlotsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CropPlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CropPlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CropPlotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> farmId = const Value.absent(),
                Value<String?> cropId = const Value.absent(),
                Value<String?> variety = const Value.absent(),
                Value<String?> season = const Value.absent(),
                Value<String?> sowingDate = const Value.absent(),
                Value<String?> stage = const Value.absent(),
                Value<double?> areaAcres = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CropPlotsCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmId: farmId,
                cropId: cropId,
                variety: variety,
                season: season,
                sowingDate: sowingDate,
                stage: stage,
                areaAcres: areaAcres,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String farmId,
                Value<String?> cropId = const Value.absent(),
                Value<String?> variety = const Value.absent(),
                Value<String?> season = const Value.absent(),
                Value<String?> sowingDate = const Value.absent(),
                Value<String?> stage = const Value.absent(),
                Value<double?> areaAcres = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CropPlotsCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmId: farmId,
                cropId: cropId,
                variety: variety,
                season: season,
                sowingDate: sowingDate,
                stage: stage,
                areaAcres: areaAcres,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CropPlotsTable, CropPlot>(table),
                  BaseReferences<_$AppDatabase, $CropPlotsTable, CropPlot>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CropPlotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CropPlotsTable,
      CropPlot,
      $$CropPlotsTableFilterComposer,
      $$CropPlotsTableOrderingComposer,
      $$CropPlotsTableAnnotationComposer,
      $$CropPlotsTableCreateCompanionBuilder,
      $$CropPlotsTableUpdateCompanionBuilder,
      (CropPlot, BaseReferences<_$AppDatabase, $CropPlotsTable, CropPlot>),
      CropPlot,
      PrefetchHooks Function()
    >;
typedef $$ConsentRecordsTableCreateCompanionBuilder =
    ConsentRecordsCompanion Function({
      required String id,
      Value<int> version,
      required DateTime updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      required String farmerId,
      required String purpose,
      Value<bool> granted,
      Value<String?> consentVersion,
      Value<String?> channel,
      Value<int> rowid,
    });
typedef $$ConsentRecordsTableUpdateCompanionBuilder =
    ConsentRecordsCompanion Function({
      Value<String> id,
      Value<int> version,
      Value<DateTime> updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      Value<String> farmerId,
      Value<String> purpose,
      Value<bool> granted,
      Value<String?> consentVersion,
      Value<String?> channel,
      Value<int> rowid,
    });

class $$ConsentRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ConsentRecordsTable> {
  $$ConsentRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get granted => $composableBuilder(
    column: $table.granted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConsentRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConsentRecordsTable> {
  $$ConsentRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get granted => $composableBuilder(
    column: $table.granted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConsentRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConsentRecordsTable> {
  $$ConsentRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get farmerId =>
      $composableBuilder(column: $table.farmerId, builder: (column) => column);

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumn<bool> get granted =>
      $composableBuilder(column: $table.granted, builder: (column) => column);

  GeneratedColumn<String> get consentVersion => $composableBuilder(
    column: $table.consentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);
}

class $$ConsentRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConsentRecordsTable,
          ConsentRecord,
          $$ConsentRecordsTableFilterComposer,
          $$ConsentRecordsTableOrderingComposer,
          $$ConsentRecordsTableAnnotationComposer,
          $$ConsentRecordsTableCreateCompanionBuilder,
          $$ConsentRecordsTableUpdateCompanionBuilder,
          (
            ConsentRecord,
            BaseReferences<_$AppDatabase, $ConsentRecordsTable, ConsentRecord>,
          ),
          ConsentRecord,
          PrefetchHooks Function()
        > {
  $$ConsentRecordsTableTableManager(
    _$AppDatabase db,
    $ConsentRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConsentRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConsentRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConsentRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> farmerId = const Value.absent(),
                Value<String> purpose = const Value.absent(),
                Value<bool> granted = const Value.absent(),
                Value<String?> consentVersion = const Value.absent(),
                Value<String?> channel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConsentRecordsCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                purpose: purpose,
                granted: granted,
                consentVersion: consentVersion,
                channel: channel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String farmerId,
                required String purpose,
                Value<bool> granted = const Value.absent(),
                Value<String?> consentVersion = const Value.absent(),
                Value<String?> channel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConsentRecordsCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                purpose: purpose,
                granted: granted,
                consentVersion: consentVersion,
                channel: channel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConsentRecordsTable, ConsentRecord>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ConsentRecordsTable,
                    ConsentRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConsentRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConsentRecordsTable,
      ConsentRecord,
      $$ConsentRecordsTableFilterComposer,
      $$ConsentRecordsTableOrderingComposer,
      $$ConsentRecordsTableAnnotationComposer,
      $$ConsentRecordsTableCreateCompanionBuilder,
      $$ConsentRecordsTableUpdateCompanionBuilder,
      (
        ConsentRecord,
        BaseReferences<_$AppDatabase, $ConsentRecordsTable, ConsentRecord>,
      ),
      ConsentRecord,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableTableCreateCompanionBuilder =
    OutboxTableCompanion Function({
      required String opId,
      required int seq,
      required String entity,
      required String action,
      required String entityId,
      Value<int> baseVersion,
      required String payload,
      required String clientTs,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime?> nextAttemptAt,
      Value<String?> dependsOnUploadId,
      Value<int> rowid,
    });
typedef $$OutboxTableTableUpdateCompanionBuilder =
    OutboxTableCompanion Function({
      Value<String> opId,
      Value<int> seq,
      Value<String> entity,
      Value<String> action,
      Value<String> entityId,
      Value<int> baseVersion,
      Value<String> payload,
      Value<String> clientTs,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime?> nextAttemptAt,
      Value<String?> dependsOnUploadId,
      Value<int> rowid,
    });

class $$OutboxTableTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTableTable> {
  $$OutboxTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientTs => $composableBuilder(
    column: $table.clientTs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dependsOnUploadId => $composableBuilder(
    column: $table.dependsOnUploadId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTableTable> {
  $$OutboxTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientTs => $composableBuilder(
    column: $table.clientTs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dependsOnUploadId => $composableBuilder(
    column: $table.dependsOnUploadId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTableTable> {
  $$OutboxTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get opId =>
      $composableBuilder(column: $table.opId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get clientTs =>
      $composableBuilder(column: $table.clientTs, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dependsOnUploadId => $composableBuilder(
    column: $table.dependsOnUploadId,
    builder: (column) => column,
  );
}

class $$OutboxTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxTableTable,
          OutboxRow,
          $$OutboxTableTableFilterComposer,
          $$OutboxTableTableOrderingComposer,
          $$OutboxTableTableAnnotationComposer,
          $$OutboxTableTableCreateCompanionBuilder,
          $$OutboxTableTableUpdateCompanionBuilder,
          (
            OutboxRow,
            BaseReferences<_$AppDatabase, $OutboxTableTable, OutboxRow>,
          ),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableTableManager(_$AppDatabase db, $OutboxTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> opId = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<int> baseVersion = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> clientTs = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> dependsOnUploadId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxTableCompanion(
                opId: opId,
                seq: seq,
                entity: entity,
                action: action,
                entityId: entityId,
                baseVersion: baseVersion,
                payload: payload,
                clientTs: clientTs,
                state: state,
                attempts: attempts,
                lastError: lastError,
                nextAttemptAt: nextAttemptAt,
                dependsOnUploadId: dependsOnUploadId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opId,
                required int seq,
                required String entity,
                required String action,
                required String entityId,
                Value<int> baseVersion = const Value.absent(),
                required String payload,
                required String clientTs,
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> dependsOnUploadId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxTableCompanion.insert(
                opId: opId,
                seq: seq,
                entity: entity,
                action: action,
                entityId: entityId,
                baseVersion: baseVersion,
                payload: payload,
                clientTs: clientTs,
                state: state,
                attempts: attempts,
                lastError: lastError,
                nextAttemptAt: nextAttemptAt,
                dependsOnUploadId: dependsOnUploadId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTableTable, OutboxRow>(table),
                  BaseReferences<_$AppDatabase, $OutboxTableTable, OutboxRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxTableTable,
      OutboxRow,
      $$OutboxTableTableFilterComposer,
      $$OutboxTableTableOrderingComposer,
      $$OutboxTableTableAnnotationComposer,
      $$OutboxTableTableCreateCompanionBuilder,
      $$OutboxTableTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$AppDatabase, $OutboxTableTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;
typedef $$UploadsTableCreateCompanionBuilder = UploadsCompanion Function({
  required String id,
  Value<String?> uploadId,
  required String filePath,
  required String sha256,
  required int sizeBytes,
  required int chunkSize,
  Value<String> receivedChunks,
  Value<String> state,
  Value<String?> blobUri,
  required String purpose,
  Value<String> contentType,
  Value<int> attempts,
  Value<String?> lastError,
  Value<DateTime?> expiresAt,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$UploadsTableUpdateCompanionBuilder = UploadsCompanion Function({
  Value<String> id,
  Value<String?> uploadId,
  Value<String> filePath,
  Value<String> sha256,
  Value<int> sizeBytes,
  Value<int> chunkSize,
  Value<String> receivedChunks,
  Value<String> state,
  Value<String?> blobUri,
  Value<String> purpose,
  Value<String> contentType,
  Value<int> attempts,
  Value<String?> lastError,
  Value<DateTime?> expiresAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$UploadsTableFilterComposer
    extends Composer<_$AppDatabase, $UploadsTable> {
  $$UploadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uploadId => $composableBuilder(
    column: $table.uploadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkSize => $composableBuilder(
    column: $table.chunkSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receivedChunks => $composableBuilder(
    column: $table.receivedChunks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blobUri => $composableBuilder(
    column: $table.blobUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadsTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadsTable> {
  $$UploadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uploadId => $composableBuilder(
    column: $table.uploadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkSize => $composableBuilder(
    column: $table.chunkSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receivedChunks => $composableBuilder(
    column: $table.receivedChunks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blobUri => $composableBuilder(
    column: $table.blobUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadsTable> {
  $$UploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uploadId =>
      $composableBuilder(column: $table.uploadId, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get chunkSize =>
      $composableBuilder(column: $table.chunkSize, builder: (column) => column);

  GeneratedColumn<String> get receivedChunks => $composableBuilder(
    column: $table.receivedChunks,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get blobUri =>
      $composableBuilder(column: $table.blobUri, builder: (column) => column);

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$UploadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadsTable,
          Upload,
          $$UploadsTableFilterComposer,
          $$UploadsTableOrderingComposer,
          $$UploadsTableAnnotationComposer,
          $$UploadsTableCreateCompanionBuilder,
          $$UploadsTableUpdateCompanionBuilder,
          (Upload, BaseReferences<_$AppDatabase, $UploadsTable, Upload>),
          Upload,
          PrefetchHooks Function()
        > {
  $$UploadsTableTableManager(_$AppDatabase db, $UploadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> uploadId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> chunkSize = const Value.absent(),
                Value<String> receivedChunks = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> blobUri = const Value.absent(),
                Value<String> purpose = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UploadsCompanion(
                id: id,
                uploadId: uploadId,
                filePath: filePath,
                sha256: sha256,
                sizeBytes: sizeBytes,
                chunkSize: chunkSize,
                receivedChunks: receivedChunks,
                state: state,
                blobUri: blobUri,
                purpose: purpose,
                contentType: contentType,
                attempts: attempts,
                lastError: lastError,
                expiresAt: expiresAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> uploadId = const Value.absent(),
                required String filePath,
                required String sha256,
                required int sizeBytes,
                required int chunkSize,
                Value<String> receivedChunks = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> blobUri = const Value.absent(),
                required String purpose,
                Value<String> contentType = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => UploadsCompanion.insert(
                id: id,
                uploadId: uploadId,
                filePath: filePath,
                sha256: sha256,
                sizeBytes: sizeBytes,
                chunkSize: chunkSize,
                receivedChunks: receivedChunks,
                state: state,
                blobUri: blobUri,
                purpose: purpose,
                contentType: contentType,
                attempts: attempts,
                lastError: lastError,
                expiresAt: expiresAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadsTable, Upload>(table),
                  BaseReferences<_$AppDatabase, $UploadsTable, Upload>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadsTable,
      Upload,
      $$UploadsTableFilterComposer,
      $$UploadsTableOrderingComposer,
      $$UploadsTableAnnotationComposer,
      $$UploadsTableCreateCompanionBuilder,
      $$UploadsTableUpdateCompanionBuilder,
      (Upload, BaseReferences<_$AppDatabase, $UploadsTable, Upload>),
      Upload,
      PrefetchHooks Function()
    >;
typedef $$SyncStatesTableCreateCompanionBuilder = SyncStatesCompanion Function({
  Value<int> id,
  Value<String?> cursor,
  Value<DateTime?> lastSyncAt,
  Value<String?> lastError,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
});
typedef $$SyncStatesTableUpdateCompanionBuilder = SyncStatesCompanion Function({
  Value<int> id,
  Value<String?> cursor,
  Value<DateTime?> lastSyncAt,
  Value<String?> lastError,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
});

class $$SyncStatesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSyncAt => $composableBuilder(
    column: $table.lastSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );
}

class $$SyncStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStatesTable,
          SyncStateRow,
          $$SyncStatesTableFilterComposer,
          $$SyncStatesTableOrderingComposer,
          $$SyncStatesTableAnnotationComposer,
          $$SyncStatesTableCreateCompanionBuilder,
          $$SyncStatesTableUpdateCompanionBuilder,
          (
            SyncStateRow,
            BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateRow>,
          ),
          SyncStateRow,
          PrefetchHooks Function()
        > {
  $$SyncStatesTableTableManager(_$AppDatabase db, $SyncStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> cursor = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
              }) => SyncStatesCompanion(
                id: id,
                cursor: cursor,
                lastSyncAt: lastSyncAt,
                lastError: lastError,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> cursor = const Value.absent(),
                Value<DateTime?> lastSyncAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
              }) => SyncStatesCompanion.insert(
                id: id,
                cursor: cursor,
                lastSyncAt: lastSyncAt,
                lastError: lastError,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStatesTable, SyncStateRow>(table),
                  BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStatesTable,
      SyncStateRow,
      $$SyncStatesTableFilterComposer,
      $$SyncStatesTableOrderingComposer,
      $$SyncStatesTableAnnotationComposer,
      $$SyncStatesTableCreateCompanionBuilder,
      $$SyncStatesTableUpdateCompanionBuilder,
      (
        SyncStateRow,
        BaseReferences<_$AppDatabase, $SyncStatesTable, SyncStateRow>,
      ),
      SyncStateRow,
      PrefetchHooks Function()
    >;
typedef $$SyncedRefsTableCreateCompanionBuilder = SyncedRefsCompanion Function({
  required String entity,
  required String refId,
  Value<int> version,
  required String data,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SyncedRefsTableUpdateCompanionBuilder = SyncedRefsCompanion Function({
  Value<String> entity,
  Value<String> refId,
  Value<int> version,
  Value<String> data,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SyncedRefsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncedRefsTable> {
  $$SyncedRefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncedRefsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncedRefsTable> {
  $$SyncedRefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncedRefsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncedRefsTable> {
  $$SyncedRefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncedRefsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncedRefsTable,
          SyncedRef,
          $$SyncedRefsTableFilterComposer,
          $$SyncedRefsTableOrderingComposer,
          $$SyncedRefsTableAnnotationComposer,
          $$SyncedRefsTableCreateCompanionBuilder,
          $$SyncedRefsTableUpdateCompanionBuilder,
          (
            SyncedRef,
            BaseReferences<_$AppDatabase, $SyncedRefsTable, SyncedRef>,
          ),
          SyncedRef,
          PrefetchHooks Function()
        > {
  $$SyncedRefsTableTableManager(_$AppDatabase db, $SyncedRefsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncedRefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncedRefsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncedRefsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncedRefsCompanion(
                entity: entity,
                refId: refId,
                version: version,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                required String refId,
                Value<int> version = const Value.absent(),
                required String data,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncedRefsCompanion.insert(
                entity: entity,
                refId: refId,
                version: version,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncedRefsTable, SyncedRef>(table),
                  BaseReferences<_$AppDatabase, $SyncedRefsTable, SyncedRef>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncedRefsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncedRefsTable,
      SyncedRef,
      $$SyncedRefsTableFilterComposer,
      $$SyncedRefsTableOrderingComposer,
      $$SyncedRefsTableAnnotationComposer,
      $$SyncedRefsTableCreateCompanionBuilder,
      $$SyncedRefsTableUpdateCompanionBuilder,
      (SyncedRef, BaseReferences<_$AppDatabase, $SyncedRefsTable, SyncedRef>),
      SyncedRef,
      PrefetchHooks Function()
    >;
typedef $$VillagesTableCreateCompanionBuilder = VillagesCompanion Function({
  required String id,
  required String name,
  Value<String> district,
  Value<String> mandal,
  Value<String> state,
  Value<String?> storeId,
  Value<double?> latitude,
  Value<double?> longitude,
  Value<double?> meetingPointLat,
  Value<double?> meetingPointLon,
  Value<double?> meetingPointRadiusM,
  Value<int> version,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$VillagesTableUpdateCompanionBuilder = VillagesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> district,
  Value<String> mandal,
  Value<String> state,
  Value<String?> storeId,
  Value<double?> latitude,
  Value<double?> longitude,
  Value<double?> meetingPointLat,
  Value<double?> meetingPointLon,
  Value<double?> meetingPointRadiusM,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$VillagesTableFilterComposer
    extends Composer<_$AppDatabase, $VillagesTable> {
  $$VillagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get district => $composableBuilder(
    column: $table.district,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mandal => $composableBuilder(
    column: $table.mandal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get meetingPointLat => $composableBuilder(
    column: $table.meetingPointLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get meetingPointLon => $composableBuilder(
    column: $table.meetingPointLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get meetingPointRadiusM => $composableBuilder(
    column: $table.meetingPointRadiusM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VillagesTableOrderingComposer
    extends Composer<_$AppDatabase, $VillagesTable> {
  $$VillagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get district => $composableBuilder(
    column: $table.district,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mandal => $composableBuilder(
    column: $table.mandal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get meetingPointLat => $composableBuilder(
    column: $table.meetingPointLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get meetingPointLon => $composableBuilder(
    column: $table.meetingPointLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get meetingPointRadiusM => $composableBuilder(
    column: $table.meetingPointRadiusM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VillagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VillagesTable> {
  $$VillagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get district =>
      $composableBuilder(column: $table.district, builder: (column) => column);

  GeneratedColumn<String> get mandal =>
      $composableBuilder(column: $table.mandal, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get meetingPointLat => $composableBuilder(
    column: $table.meetingPointLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get meetingPointLon => $composableBuilder(
    column: $table.meetingPointLon,
    builder: (column) => column,
  );

  GeneratedColumn<double> get meetingPointRadiusM => $composableBuilder(
    column: $table.meetingPointRadiusM,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VillagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VillagesTable,
          Village,
          $$VillagesTableFilterComposer,
          $$VillagesTableOrderingComposer,
          $$VillagesTableAnnotationComposer,
          $$VillagesTableCreateCompanionBuilder,
          $$VillagesTableUpdateCompanionBuilder,
          (Village, BaseReferences<_$AppDatabase, $VillagesTable, Village>),
          Village,
          PrefetchHooks Function()
        > {
  $$VillagesTableTableManager(_$AppDatabase db, $VillagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VillagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VillagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VillagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> district = const Value.absent(),
                Value<String> mandal = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> meetingPointLat = const Value.absent(),
                Value<double?> meetingPointLon = const Value.absent(),
                Value<double?> meetingPointRadiusM = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VillagesCompanion(
                id: id,
                name: name,
                district: district,
                mandal: mandal,
                state: state,
                storeId: storeId,
                latitude: latitude,
                longitude: longitude,
                meetingPointLat: meetingPointLat,
                meetingPointLon: meetingPointLon,
                meetingPointRadiusM: meetingPointRadiusM,
                version: version,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> district = const Value.absent(),
                Value<String> mandal = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> meetingPointLat = const Value.absent(),
                Value<double?> meetingPointLon = const Value.absent(),
                Value<double?> meetingPointRadiusM = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => VillagesCompanion.insert(
                id: id,
                name: name,
                district: district,
                mandal: mandal,
                state: state,
                storeId: storeId,
                latitude: latitude,
                longitude: longitude,
                meetingPointLat: meetingPointLat,
                meetingPointLon: meetingPointLon,
                meetingPointRadiusM: meetingPointRadiusM,
                version: version,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VillagesTable, Village>(table),
                  BaseReferences<_$AppDatabase, $VillagesTable, Village>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VillagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VillagesTable,
      Village,
      $$VillagesTableFilterComposer,
      $$VillagesTableOrderingComposer,
      $$VillagesTableAnnotationComposer,
      $$VillagesTableCreateCompanionBuilder,
      $$VillagesTableUpdateCompanionBuilder,
      (Village, BaseReferences<_$AppDatabase, $VillagesTable, Village>),
      Village,
      PrefetchHooks Function()
    >;
typedef $$DutySessionsTableCreateCompanionBuilder =
    DutySessionsCompanion Function({
      required String id,
      Value<int> version,
      required DateTime updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      required DateTime startAt,
      Value<DateTime?> endAt,
      Value<String?> endReason,
      Value<double?> startLat,
      Value<double?> startLon,
      Value<double?> startAccuracyM,
      Value<double?> endLat,
      Value<double?> endLon,
      Value<double?> endAccuracyM,
      Value<String?> policyVersion,
      Value<String?> deviceId,
      Value<String?> appVersion,
      Value<String> integrity,
      Value<double> distanceM,
      Value<bool> autoEnded,
      Value<String> extra,
      Value<int> rowid,
    });
typedef $$DutySessionsTableUpdateCompanionBuilder =
    DutySessionsCompanion Function({
      Value<String> id,
      Value<int> version,
      Value<DateTime> updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      Value<DateTime> startAt,
      Value<DateTime?> endAt,
      Value<String?> endReason,
      Value<double?> startLat,
      Value<double?> startLon,
      Value<double?> startAccuracyM,
      Value<double?> endLat,
      Value<double?> endLon,
      Value<double?> endAccuracyM,
      Value<String?> policyVersion,
      Value<String?> deviceId,
      Value<String?> appVersion,
      Value<String> integrity,
      Value<double> distanceM,
      Value<bool> autoEnded,
      Value<String> extra,
      Value<int> rowid,
    });

class $$DutySessionsTableFilterComposer
    extends Composer<_$AppDatabase, $DutySessionsTable> {
  $$DutySessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get startLat => $composableBuilder(
    column: $table.startLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get startLon => $composableBuilder(
    column: $table.startLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get startAccuracyM => $composableBuilder(
    column: $table.startAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endLat => $composableBuilder(
    column: $table.endLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endLon => $composableBuilder(
    column: $table.endLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endAccuracyM => $composableBuilder(
    column: $table.endAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get policyVersion => $composableBuilder(
    column: $table.policyVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get integrity => $composableBuilder(
    column: $table.integrity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoEnded => $composableBuilder(
    column: $table.autoEnded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DutySessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $DutySessionsTable> {
  $$DutySessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get startLat => $composableBuilder(
    column: $table.startLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get startLon => $composableBuilder(
    column: $table.startLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get startAccuracyM => $composableBuilder(
    column: $table.startAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endLat => $composableBuilder(
    column: $table.endLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endLon => $composableBuilder(
    column: $table.endLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endAccuracyM => $composableBuilder(
    column: $table.endAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get policyVersion => $composableBuilder(
    column: $table.policyVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get integrity => $composableBuilder(
    column: $table.integrity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoEnded => $composableBuilder(
    column: $table.autoEnded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DutySessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DutySessionsTable> {
  $$DutySessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<DateTime> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<String> get endReason =>
      $composableBuilder(column: $table.endReason, builder: (column) => column);

  GeneratedColumn<double> get startLat =>
      $composableBuilder(column: $table.startLat, builder: (column) => column);

  GeneratedColumn<double> get startLon =>
      $composableBuilder(column: $table.startLon, builder: (column) => column);

  GeneratedColumn<double> get startAccuracyM => $composableBuilder(
    column: $table.startAccuracyM,
    builder: (column) => column,
  );

  GeneratedColumn<double> get endLat =>
      $composableBuilder(column: $table.endLat, builder: (column) => column);

  GeneratedColumn<double> get endLon =>
      $composableBuilder(column: $table.endLon, builder: (column) => column);

  GeneratedColumn<double> get endAccuracyM => $composableBuilder(
    column: $table.endAccuracyM,
    builder: (column) => column,
  );

  GeneratedColumn<String> get policyVersion => $composableBuilder(
    column: $table.policyVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get integrity =>
      $composableBuilder(column: $table.integrity, builder: (column) => column);

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);

  GeneratedColumn<bool> get autoEnded =>
      $composableBuilder(column: $table.autoEnded, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$DutySessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DutySessionsTable,
          DutySession,
          $$DutySessionsTableFilterComposer,
          $$DutySessionsTableOrderingComposer,
          $$DutySessionsTableAnnotationComposer,
          $$DutySessionsTableCreateCompanionBuilder,
          $$DutySessionsTableUpdateCompanionBuilder,
          (
            DutySession,
            BaseReferences<_$AppDatabase, $DutySessionsTable, DutySession>,
          ),
          DutySession,
          PrefetchHooks Function()
        > {
  $$DutySessionsTableTableManager(_$AppDatabase db, $DutySessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DutySessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DutySessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DutySessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<DateTime> startAt = const Value.absent(),
                Value<DateTime?> endAt = const Value.absent(),
                Value<String?> endReason = const Value.absent(),
                Value<double?> startLat = const Value.absent(),
                Value<double?> startLon = const Value.absent(),
                Value<double?> startAccuracyM = const Value.absent(),
                Value<double?> endLat = const Value.absent(),
                Value<double?> endLon = const Value.absent(),
                Value<double?> endAccuracyM = const Value.absent(),
                Value<String?> policyVersion = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<String> integrity = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<bool> autoEnded = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DutySessionsCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                startAt: startAt,
                endAt: endAt,
                endReason: endReason,
                startLat: startLat,
                startLon: startLon,
                startAccuracyM: startAccuracyM,
                endLat: endLat,
                endLon: endLon,
                endAccuracyM: endAccuracyM,
                policyVersion: policyVersion,
                deviceId: deviceId,
                appVersion: appVersion,
                integrity: integrity,
                distanceM: distanceM,
                autoEnded: autoEnded,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required DateTime startAt,
                Value<DateTime?> endAt = const Value.absent(),
                Value<String?> endReason = const Value.absent(),
                Value<double?> startLat = const Value.absent(),
                Value<double?> startLon = const Value.absent(),
                Value<double?> startAccuracyM = const Value.absent(),
                Value<double?> endLat = const Value.absent(),
                Value<double?> endLon = const Value.absent(),
                Value<double?> endAccuracyM = const Value.absent(),
                Value<String?> policyVersion = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<String> integrity = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<bool> autoEnded = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DutySessionsCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                startAt: startAt,
                endAt: endAt,
                endReason: endReason,
                startLat: startLat,
                startLon: startLon,
                startAccuracyM: startAccuracyM,
                endLat: endLat,
                endLon: endLon,
                endAccuracyM: endAccuracyM,
                policyVersion: policyVersion,
                deviceId: deviceId,
                appVersion: appVersion,
                integrity: integrity,
                distanceM: distanceM,
                autoEnded: autoEnded,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DutySessionsTable, DutySession>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DutySessionsTable,
                    DutySession
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DutySessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DutySessionsTable,
      DutySession,
      $$DutySessionsTableFilterComposer,
      $$DutySessionsTableOrderingComposer,
      $$DutySessionsTableAnnotationComposer,
      $$DutySessionsTableCreateCompanionBuilder,
      $$DutySessionsTableUpdateCompanionBuilder,
      (
        DutySession,
        BaseReferences<_$AppDatabase, $DutySessionsTable, DutySession>,
      ),
      DutySession,
      PrefetchHooks Function()
    >;
typedef $$LocationBufferTableCreateCompanionBuilder =
    LocationBufferCompanion Function({
      Value<int> id,
      required String sessionId,
      required DateTime ts,
      required double lat,
      required double lon,
      required double accuracyM,
      Value<double?> speedMps,
      Value<double?> bearing,
      Value<int?> batteryPct,
      Value<bool> isMock,
      Value<bool> isRooted,
      Value<int?> clockDriftS,
      Value<String?> provider,
      Value<String?> batchId,
    });
typedef $$LocationBufferTableUpdateCompanionBuilder =
    LocationBufferCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<DateTime> ts,
      Value<double> lat,
      Value<double> lon,
      Value<double> accuracyM,
      Value<double?> speedMps,
      Value<double?> bearing,
      Value<int?> batteryPct,
      Value<bool> isMock,
      Value<bool> isRooted,
      Value<int?> clockDriftS,
      Value<String?> provider,
      Value<String?> batchId,
    });

class $$LocationBufferTableFilterComposer
    extends Composer<_$AppDatabase, $LocationBufferTable> {
  $$LocationBufferTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bearing => $composableBuilder(
    column: $table.bearing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get batteryPct => $composableBuilder(
    column: $table.batteryPct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isMock => $composableBuilder(
    column: $table.isMock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRooted => $composableBuilder(
    column: $table.isRooted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clockDriftS => $composableBuilder(
    column: $table.clockDriftS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocationBufferTableOrderingComposer
    extends Composer<_$AppDatabase, $LocationBufferTable> {
  $$LocationBufferTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bearing => $composableBuilder(
    column: $table.bearing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get batteryPct => $composableBuilder(
    column: $table.batteryPct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isMock => $composableBuilder(
    column: $table.isMock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRooted => $composableBuilder(
    column: $table.isRooted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clockDriftS => $composableBuilder(
    column: $table.clockDriftS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batchId => $composableBuilder(
    column: $table.batchId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocationBufferTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocationBufferTable> {
  $$LocationBufferTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<DateTime> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  GeneratedColumn<double> get bearing =>
      $composableBuilder(column: $table.bearing, builder: (column) => column);

  GeneratedColumn<int> get batteryPct => $composableBuilder(
    column: $table.batteryPct,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isMock =>
      $composableBuilder(column: $table.isMock, builder: (column) => column);

  GeneratedColumn<bool> get isRooted =>
      $composableBuilder(column: $table.isRooted, builder: (column) => column);

  GeneratedColumn<int> get clockDriftS => $composableBuilder(
    column: $table.clockDriftS,
    builder: (column) => column,
  );

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get batchId =>
      $composableBuilder(column: $table.batchId, builder: (column) => column);
}

class $$LocationBufferTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocationBufferTable,
          LocationBufferRow,
          $$LocationBufferTableFilterComposer,
          $$LocationBufferTableOrderingComposer,
          $$LocationBufferTableAnnotationComposer,
          $$LocationBufferTableCreateCompanionBuilder,
          $$LocationBufferTableUpdateCompanionBuilder,
          (
            LocationBufferRow,
            BaseReferences<
              _$AppDatabase,
              $LocationBufferTable,
              LocationBufferRow
            >,
          ),
          LocationBufferRow,
          PrefetchHooks Function()
        > {
  $$LocationBufferTableTableManager(
    _$AppDatabase db,
    $LocationBufferTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocationBufferTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocationBufferTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocationBufferTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<DateTime> ts = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<double> accuracyM = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
                Value<double?> bearing = const Value.absent(),
                Value<int?> batteryPct = const Value.absent(),
                Value<bool> isMock = const Value.absent(),
                Value<bool> isRooted = const Value.absent(),
                Value<int?> clockDriftS = const Value.absent(),
                Value<String?> provider = const Value.absent(),
                Value<String?> batchId = const Value.absent(),
              }) => LocationBufferCompanion(
                id: id,
                sessionId: sessionId,
                ts: ts,
                lat: lat,
                lon: lon,
                accuracyM: accuracyM,
                speedMps: speedMps,
                bearing: bearing,
                batteryPct: batteryPct,
                isMock: isMock,
                isRooted: isRooted,
                clockDriftS: clockDriftS,
                provider: provider,
                batchId: batchId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required DateTime ts,
                required double lat,
                required double lon,
                required double accuracyM,
                Value<double?> speedMps = const Value.absent(),
                Value<double?> bearing = const Value.absent(),
                Value<int?> batteryPct = const Value.absent(),
                Value<bool> isMock = const Value.absent(),
                Value<bool> isRooted = const Value.absent(),
                Value<int?> clockDriftS = const Value.absent(),
                Value<String?> provider = const Value.absent(),
                Value<String?> batchId = const Value.absent(),
              }) => LocationBufferCompanion.insert(
                id: id,
                sessionId: sessionId,
                ts: ts,
                lat: lat,
                lon: lon,
                accuracyM: accuracyM,
                speedMps: speedMps,
                bearing: bearing,
                batteryPct: batteryPct,
                isMock: isMock,
                isRooted: isRooted,
                clockDriftS: clockDriftS,
                provider: provider,
                batchId: batchId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocationBufferTable, LocationBufferRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocationBufferTable,
                    LocationBufferRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocationBufferTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocationBufferTable,
      LocationBufferRow,
      $$LocationBufferTableFilterComposer,
      $$LocationBufferTableOrderingComposer,
      $$LocationBufferTableAnnotationComposer,
      $$LocationBufferTableCreateCompanionBuilder,
      $$LocationBufferTableUpdateCompanionBuilder,
      (
        LocationBufferRow,
        BaseReferences<_$AppDatabase, $LocationBufferTable, LocationBufferRow>,
      ),
      LocationBufferRow,
      PrefetchHooks Function()
    >;
typedef $$SyncDocsTableCreateCompanionBuilder = SyncDocsCompanion Function({
  required String entity,
  required String docId,
  Value<int> version,
  Value<bool> dirty,
  Value<bool> deleted,
  required String data,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SyncDocsTableUpdateCompanionBuilder = SyncDocsCompanion Function({
  Value<String> entity,
  Value<String> docId,
  Value<int> version,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String> data,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SyncDocsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncDocsTable> {
  $$SyncDocsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncDocsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncDocsTable> {
  $$SyncDocsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncDocsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncDocsTable> {
  $$SyncDocsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncDocsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncDocsTable,
          SyncDoc,
          $$SyncDocsTableFilterComposer,
          $$SyncDocsTableOrderingComposer,
          $$SyncDocsTableAnnotationComposer,
          $$SyncDocsTableCreateCompanionBuilder,
          $$SyncDocsTableUpdateCompanionBuilder,
          (SyncDoc, BaseReferences<_$AppDatabase, $SyncDocsTable, SyncDoc>),
          SyncDoc,
          PrefetchHooks Function()
        > {
  $$SyncDocsTableTableManager(_$AppDatabase db, $SyncDocsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncDocsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncDocsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncDocsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<String> docId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncDocsCompanion(
                entity: entity,
                docId: docId,
                version: version,
                dirty: dirty,
                deleted: deleted,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                required String docId,
                Value<int> version = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String data,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncDocsCompanion.insert(
                entity: entity,
                docId: docId,
                version: version,
                dirty: dirty,
                deleted: deleted,
                data: data,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncDocsTable, SyncDoc>(table),
                  BaseReferences<_$AppDatabase, $SyncDocsTable, SyncDoc>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncDocsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncDocsTable,
      SyncDoc,
      $$SyncDocsTableFilterComposer,
      $$SyncDocsTableOrderingComposer,
      $$SyncDocsTableAnnotationComposer,
      $$SyncDocsTableCreateCompanionBuilder,
      $$SyncDocsTableUpdateCompanionBuilder,
      (SyncDoc, BaseReferences<_$AppDatabase, $SyncDocsTable, SyncDoc>),
      SyncDoc,
      PrefetchHooks Function()
    >;
typedef $$VisitsTableCreateCompanionBuilder = VisitsCompanion Function({
  required String id,
  Value<int> version,
  required DateTime updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  required String farmerId,
  Value<String?> farmId,
  Value<String?> villageId,
  Value<String> purpose,
  required DateTime checkinAt,
  required double checkinLat,
  required double checkinLon,
  Value<double?> checkinAccuracyM,
  Value<DateTime?> checkoutAt,
  Value<double?> checkoutLat,
  Value<double?> checkoutLon,
  Value<String?> geofenceResult,
  Value<String?> precheckResult,
  Value<double?> precheckDistanceM,
  Value<String?> precheckTarget,
  Value<double?> precheckRadiusM,
  Value<String?> overrideNote,
  Value<String?> overrideApprovedBy,
  Value<String?> notes,
  Value<String?> cropStage,
  Value<int?> durationS,
  Value<int?> score,
  Value<String> status,
  Value<String> confirmationChannel,
  Value<DateTime?> confirmedAt,
  Value<String> deviceIntegrity,
  Value<String> integrityIssues,
  Value<String> flags,
  Value<String?> scoreComponents,
  Value<String?> clientVisitId,
  Value<String?> officerId,
  Value<String?> failureCode,
  Value<String?> failureDetail,
  Value<String> extra,
  Value<int> rowid,
});
typedef $$VisitsTableUpdateCompanionBuilder = VisitsCompanion Function({
  Value<String> id,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String> farmerId,
  Value<String?> farmId,
  Value<String?> villageId,
  Value<String> purpose,
  Value<DateTime> checkinAt,
  Value<double> checkinLat,
  Value<double> checkinLon,
  Value<double?> checkinAccuracyM,
  Value<DateTime?> checkoutAt,
  Value<double?> checkoutLat,
  Value<double?> checkoutLon,
  Value<String?> geofenceResult,
  Value<String?> precheckResult,
  Value<double?> precheckDistanceM,
  Value<String?> precheckTarget,
  Value<double?> precheckRadiusM,
  Value<String?> overrideNote,
  Value<String?> overrideApprovedBy,
  Value<String?> notes,
  Value<String?> cropStage,
  Value<int?> durationS,
  Value<int?> score,
  Value<String> status,
  Value<String> confirmationChannel,
  Value<DateTime?> confirmedAt,
  Value<String> deviceIntegrity,
  Value<String> integrityIssues,
  Value<String> flags,
  Value<String?> scoreComponents,
  Value<String?> clientVisitId,
  Value<String?> officerId,
  Value<String?> failureCode,
  Value<String?> failureDetail,
  Value<String> extra,
  Value<int> rowid,
});

class $$VisitsTableFilterComposer
    extends Composer<_$AppDatabase, $VisitsTable> {
  $$VisitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get villageId => $composableBuilder(
    column: $table.villageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkinAt => $composableBuilder(
    column: $table.checkinAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get checkinLat => $composableBuilder(
    column: $table.checkinLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get checkinLon => $composableBuilder(
    column: $table.checkinLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get checkinAccuracyM => $composableBuilder(
    column: $table.checkinAccuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkoutAt => $composableBuilder(
    column: $table.checkoutAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get checkoutLat => $composableBuilder(
    column: $table.checkoutLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get checkoutLon => $composableBuilder(
    column: $table.checkoutLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get geofenceResult => $composableBuilder(
    column: $table.geofenceResult,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get precheckResult => $composableBuilder(
    column: $table.precheckResult,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get precheckDistanceM => $composableBuilder(
    column: $table.precheckDistanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get precheckTarget => $composableBuilder(
    column: $table.precheckTarget,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get precheckRadiusM => $composableBuilder(
    column: $table.precheckRadiusM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overrideNote => $composableBuilder(
    column: $table.overrideNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overrideApprovedBy => $composableBuilder(
    column: $table.overrideApprovedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cropStage => $composableBuilder(
    column: $table.cropStage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationS => $composableBuilder(
    column: $table.durationS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confirmationChannel => $composableBuilder(
    column: $table.confirmationChannel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceIntegrity => $composableBuilder(
    column: $table.deviceIntegrity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get integrityIssues => $composableBuilder(
    column: $table.integrityIssues,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scoreComponents => $composableBuilder(
    column: $table.scoreComponents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientVisitId => $composableBuilder(
    column: $table.clientVisitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get officerId => $composableBuilder(
    column: $table.officerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureDetail => $composableBuilder(
    column: $table.failureDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisitsTableOrderingComposer
    extends Composer<_$AppDatabase, $VisitsTable> {
  $$VisitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmId => $composableBuilder(
    column: $table.farmId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get villageId => $composableBuilder(
    column: $table.villageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkinAt => $composableBuilder(
    column: $table.checkinAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get checkinLat => $composableBuilder(
    column: $table.checkinLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get checkinLon => $composableBuilder(
    column: $table.checkinLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get checkinAccuracyM => $composableBuilder(
    column: $table.checkinAccuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkoutAt => $composableBuilder(
    column: $table.checkoutAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get checkoutLat => $composableBuilder(
    column: $table.checkoutLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get checkoutLon => $composableBuilder(
    column: $table.checkoutLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get geofenceResult => $composableBuilder(
    column: $table.geofenceResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get precheckResult => $composableBuilder(
    column: $table.precheckResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get precheckDistanceM => $composableBuilder(
    column: $table.precheckDistanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get precheckTarget => $composableBuilder(
    column: $table.precheckTarget,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get precheckRadiusM => $composableBuilder(
    column: $table.precheckRadiusM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overrideNote => $composableBuilder(
    column: $table.overrideNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overrideApprovedBy => $composableBuilder(
    column: $table.overrideApprovedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cropStage => $composableBuilder(
    column: $table.cropStage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationS => $composableBuilder(
    column: $table.durationS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confirmationChannel => $composableBuilder(
    column: $table.confirmationChannel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceIntegrity => $composableBuilder(
    column: $table.deviceIntegrity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get integrityIssues => $composableBuilder(
    column: $table.integrityIssues,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get flags => $composableBuilder(
    column: $table.flags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scoreComponents => $composableBuilder(
    column: $table.scoreComponents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientVisitId => $composableBuilder(
    column: $table.clientVisitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get officerId => $composableBuilder(
    column: $table.officerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureDetail => $composableBuilder(
    column: $table.failureDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisitsTable> {
  $$VisitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get farmerId =>
      $composableBuilder(column: $table.farmerId, builder: (column) => column);

  GeneratedColumn<String> get farmId =>
      $composableBuilder(column: $table.farmId, builder: (column) => column);

  GeneratedColumn<String> get villageId =>
      $composableBuilder(column: $table.villageId, builder: (column) => column);

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumn<DateTime> get checkinAt =>
      $composableBuilder(column: $table.checkinAt, builder: (column) => column);

  GeneratedColumn<double> get checkinLat => $composableBuilder(
    column: $table.checkinLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get checkinLon => $composableBuilder(
    column: $table.checkinLon,
    builder: (column) => column,
  );

  GeneratedColumn<double> get checkinAccuracyM => $composableBuilder(
    column: $table.checkinAccuracyM,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get checkoutAt => $composableBuilder(
    column: $table.checkoutAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get checkoutLat => $composableBuilder(
    column: $table.checkoutLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get checkoutLon => $composableBuilder(
    column: $table.checkoutLon,
    builder: (column) => column,
  );

  GeneratedColumn<String> get geofenceResult => $composableBuilder(
    column: $table.geofenceResult,
    builder: (column) => column,
  );

  GeneratedColumn<String> get precheckResult => $composableBuilder(
    column: $table.precheckResult,
    builder: (column) => column,
  );

  GeneratedColumn<double> get precheckDistanceM => $composableBuilder(
    column: $table.precheckDistanceM,
    builder: (column) => column,
  );

  GeneratedColumn<String> get precheckTarget => $composableBuilder(
    column: $table.precheckTarget,
    builder: (column) => column,
  );

  GeneratedColumn<double> get precheckRadiusM => $composableBuilder(
    column: $table.precheckRadiusM,
    builder: (column) => column,
  );

  GeneratedColumn<String> get overrideNote => $composableBuilder(
    column: $table.overrideNote,
    builder: (column) => column,
  );

  GeneratedColumn<String> get overrideApprovedBy => $composableBuilder(
    column: $table.overrideApprovedBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get cropStage =>
      $composableBuilder(column: $table.cropStage, builder: (column) => column);

  GeneratedColumn<int> get durationS =>
      $composableBuilder(column: $table.durationS, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get confirmationChannel => $composableBuilder(
    column: $table.confirmationChannel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceIntegrity => $composableBuilder(
    column: $table.deviceIntegrity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get integrityIssues => $composableBuilder(
    column: $table.integrityIssues,
    builder: (column) => column,
  );

  GeneratedColumn<String> get flags =>
      $composableBuilder(column: $table.flags, builder: (column) => column);

  GeneratedColumn<String> get scoreComponents => $composableBuilder(
    column: $table.scoreComponents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clientVisitId => $composableBuilder(
    column: $table.clientVisitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get officerId =>
      $composableBuilder(column: $table.officerId, builder: (column) => column);

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureDetail => $composableBuilder(
    column: $table.failureDetail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$VisitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisitsTable,
          Visit,
          $$VisitsTableFilterComposer,
          $$VisitsTableOrderingComposer,
          $$VisitsTableAnnotationComposer,
          $$VisitsTableCreateCompanionBuilder,
          $$VisitsTableUpdateCompanionBuilder,
          (Visit, BaseReferences<_$AppDatabase, $VisitsTable, Visit>),
          Visit,
          PrefetchHooks Function()
        > {
  $$VisitsTableTableManager(_$AppDatabase db, $VisitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VisitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> farmerId = const Value.absent(),
                Value<String?> farmId = const Value.absent(),
                Value<String?> villageId = const Value.absent(),
                Value<String> purpose = const Value.absent(),
                Value<DateTime> checkinAt = const Value.absent(),
                Value<double> checkinLat = const Value.absent(),
                Value<double> checkinLon = const Value.absent(),
                Value<double?> checkinAccuracyM = const Value.absent(),
                Value<DateTime?> checkoutAt = const Value.absent(),
                Value<double?> checkoutLat = const Value.absent(),
                Value<double?> checkoutLon = const Value.absent(),
                Value<String?> geofenceResult = const Value.absent(),
                Value<String?> precheckResult = const Value.absent(),
                Value<double?> precheckDistanceM = const Value.absent(),
                Value<String?> precheckTarget = const Value.absent(),
                Value<double?> precheckRadiusM = const Value.absent(),
                Value<String?> overrideNote = const Value.absent(),
                Value<String?> overrideApprovedBy = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> cropStage = const Value.absent(),
                Value<int?> durationS = const Value.absent(),
                Value<int?> score = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> confirmationChannel = const Value.absent(),
                Value<DateTime?> confirmedAt = const Value.absent(),
                Value<String> deviceIntegrity = const Value.absent(),
                Value<String> integrityIssues = const Value.absent(),
                Value<String> flags = const Value.absent(),
                Value<String?> scoreComponents = const Value.absent(),
                Value<String?> clientVisitId = const Value.absent(),
                Value<String?> officerId = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> failureDetail = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitsCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                farmId: farmId,
                villageId: villageId,
                purpose: purpose,
                checkinAt: checkinAt,
                checkinLat: checkinLat,
                checkinLon: checkinLon,
                checkinAccuracyM: checkinAccuracyM,
                checkoutAt: checkoutAt,
                checkoutLat: checkoutLat,
                checkoutLon: checkoutLon,
                geofenceResult: geofenceResult,
                precheckResult: precheckResult,
                precheckDistanceM: precheckDistanceM,
                precheckTarget: precheckTarget,
                precheckRadiusM: precheckRadiusM,
                overrideNote: overrideNote,
                overrideApprovedBy: overrideApprovedBy,
                notes: notes,
                cropStage: cropStage,
                durationS: durationS,
                score: score,
                status: status,
                confirmationChannel: confirmationChannel,
                confirmedAt: confirmedAt,
                deviceIntegrity: deviceIntegrity,
                integrityIssues: integrityIssues,
                flags: flags,
                scoreComponents: scoreComponents,
                clientVisitId: clientVisitId,
                officerId: officerId,
                failureCode: failureCode,
                failureDetail: failureDetail,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String farmerId,
                Value<String?> farmId = const Value.absent(),
                Value<String?> villageId = const Value.absent(),
                Value<String> purpose = const Value.absent(),
                required DateTime checkinAt,
                required double checkinLat,
                required double checkinLon,
                Value<double?> checkinAccuracyM = const Value.absent(),
                Value<DateTime?> checkoutAt = const Value.absent(),
                Value<double?> checkoutLat = const Value.absent(),
                Value<double?> checkoutLon = const Value.absent(),
                Value<String?> geofenceResult = const Value.absent(),
                Value<String?> precheckResult = const Value.absent(),
                Value<double?> precheckDistanceM = const Value.absent(),
                Value<String?> precheckTarget = const Value.absent(),
                Value<double?> precheckRadiusM = const Value.absent(),
                Value<String?> overrideNote = const Value.absent(),
                Value<String?> overrideApprovedBy = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> cropStage = const Value.absent(),
                Value<int?> durationS = const Value.absent(),
                Value<int?> score = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> confirmationChannel = const Value.absent(),
                Value<DateTime?> confirmedAt = const Value.absent(),
                Value<String> deviceIntegrity = const Value.absent(),
                Value<String> integrityIssues = const Value.absent(),
                Value<String> flags = const Value.absent(),
                Value<String?> scoreComponents = const Value.absent(),
                Value<String?> clientVisitId = const Value.absent(),
                Value<String?> officerId = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> failureDetail = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitsCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                farmId: farmId,
                villageId: villageId,
                purpose: purpose,
                checkinAt: checkinAt,
                checkinLat: checkinLat,
                checkinLon: checkinLon,
                checkinAccuracyM: checkinAccuracyM,
                checkoutAt: checkoutAt,
                checkoutLat: checkoutLat,
                checkoutLon: checkoutLon,
                geofenceResult: geofenceResult,
                precheckResult: precheckResult,
                precheckDistanceM: precheckDistanceM,
                precheckTarget: precheckTarget,
                precheckRadiusM: precheckRadiusM,
                overrideNote: overrideNote,
                overrideApprovedBy: overrideApprovedBy,
                notes: notes,
                cropStage: cropStage,
                durationS: durationS,
                score: score,
                status: status,
                confirmationChannel: confirmationChannel,
                confirmedAt: confirmedAt,
                deviceIntegrity: deviceIntegrity,
                integrityIssues: integrityIssues,
                flags: flags,
                scoreComponents: scoreComponents,
                clientVisitId: clientVisitId,
                officerId: officerId,
                failureCode: failureCode,
                failureDetail: failureDetail,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VisitsTable, Visit>(table),
                  BaseReferences<_$AppDatabase, $VisitsTable, Visit>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisitsTable,
      Visit,
      $$VisitsTableFilterComposer,
      $$VisitsTableOrderingComposer,
      $$VisitsTableAnnotationComposer,
      $$VisitsTableCreateCompanionBuilder,
      $$VisitsTableUpdateCompanionBuilder,
      (Visit, BaseReferences<_$AppDatabase, $VisitsTable, Visit>),
      Visit,
      PrefetchHooks Function()
    >;
typedef $$VisitPhotosTableCreateCompanionBuilder =
    VisitPhotosCompanion Function({
      required String id,
      Value<int> version,
      required DateTime updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      required String visitId,
      Value<String> blobUri,
      Value<String?> sha256,
      Value<String?> phash,
      Value<DateTime?> exifTime,
      Value<double?> exifLat,
      Value<double?> exifLon,
      Value<bool> takenInApp,
      Value<DateTime?> deviceTime,
      Value<DateTime?> serverTime,
      Value<String> photoFlags,
      Value<String?> localPath,
      Value<String> extra,
      Value<int> rowid,
    });
typedef $$VisitPhotosTableUpdateCompanionBuilder =
    VisitPhotosCompanion Function({
      Value<String> id,
      Value<int> version,
      Value<DateTime> updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      Value<String> visitId,
      Value<String> blobUri,
      Value<String?> sha256,
      Value<String?> phash,
      Value<DateTime?> exifTime,
      Value<double?> exifLat,
      Value<double?> exifLon,
      Value<bool> takenInApp,
      Value<DateTime?> deviceTime,
      Value<DateTime?> serverTime,
      Value<String> photoFlags,
      Value<String?> localPath,
      Value<String> extra,
      Value<int> rowid,
    });

class $$VisitPhotosTableFilterComposer
    extends Composer<_$AppDatabase, $VisitPhotosTable> {
  $$VisitPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get visitId => $composableBuilder(
    column: $table.visitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blobUri => $composableBuilder(
    column: $table.blobUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phash => $composableBuilder(
    column: $table.phash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get exifTime => $composableBuilder(
    column: $table.exifTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get exifLat => $composableBuilder(
    column: $table.exifLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get exifLon => $composableBuilder(
    column: $table.exifLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get takenInApp => $composableBuilder(
    column: $table.takenInApp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deviceTime => $composableBuilder(
    column: $table.deviceTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverTime => $composableBuilder(
    column: $table.serverTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get photoFlags => $composableBuilder(
    column: $table.photoFlags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisitPhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $VisitPhotosTable> {
  $$VisitPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get visitId => $composableBuilder(
    column: $table.visitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blobUri => $composableBuilder(
    column: $table.blobUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phash => $composableBuilder(
    column: $table.phash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get exifTime => $composableBuilder(
    column: $table.exifTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get exifLat => $composableBuilder(
    column: $table.exifLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get exifLon => $composableBuilder(
    column: $table.exifLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get takenInApp => $composableBuilder(
    column: $table.takenInApp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deviceTime => $composableBuilder(
    column: $table.deviceTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverTime => $composableBuilder(
    column: $table.serverTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get photoFlags => $composableBuilder(
    column: $table.photoFlags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisitPhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisitPhotosTable> {
  $$VisitPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get visitId =>
      $composableBuilder(column: $table.visitId, builder: (column) => column);

  GeneratedColumn<String> get blobUri =>
      $composableBuilder(column: $table.blobUri, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get phash =>
      $composableBuilder(column: $table.phash, builder: (column) => column);

  GeneratedColumn<DateTime> get exifTime =>
      $composableBuilder(column: $table.exifTime, builder: (column) => column);

  GeneratedColumn<double> get exifLat =>
      $composableBuilder(column: $table.exifLat, builder: (column) => column);

  GeneratedColumn<double> get exifLon =>
      $composableBuilder(column: $table.exifLon, builder: (column) => column);

  GeneratedColumn<bool> get takenInApp => $composableBuilder(
    column: $table.takenInApp,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deviceTime => $composableBuilder(
    column: $table.deviceTime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get serverTime => $composableBuilder(
    column: $table.serverTime,
    builder: (column) => column,
  );

  GeneratedColumn<String> get photoFlags => $composableBuilder(
    column: $table.photoFlags,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$VisitPhotosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisitPhotosTable,
          VisitPhoto,
          $$VisitPhotosTableFilterComposer,
          $$VisitPhotosTableOrderingComposer,
          $$VisitPhotosTableAnnotationComposer,
          $$VisitPhotosTableCreateCompanionBuilder,
          $$VisitPhotosTableUpdateCompanionBuilder,
          (
            VisitPhoto,
            BaseReferences<_$AppDatabase, $VisitPhotosTable, VisitPhoto>,
          ),
          VisitPhoto,
          PrefetchHooks Function()
        > {
  $$VisitPhotosTableTableManager(_$AppDatabase db, $VisitPhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisitPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisitPhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VisitPhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> visitId = const Value.absent(),
                Value<String> blobUri = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String?> phash = const Value.absent(),
                Value<DateTime?> exifTime = const Value.absent(),
                Value<double?> exifLat = const Value.absent(),
                Value<double?> exifLon = const Value.absent(),
                Value<bool> takenInApp = const Value.absent(),
                Value<DateTime?> deviceTime = const Value.absent(),
                Value<DateTime?> serverTime = const Value.absent(),
                Value<String> photoFlags = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitPhotosCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                visitId: visitId,
                blobUri: blobUri,
                sha256: sha256,
                phash: phash,
                exifTime: exifTime,
                exifLat: exifLat,
                exifLon: exifLon,
                takenInApp: takenInApp,
                deviceTime: deviceTime,
                serverTime: serverTime,
                photoFlags: photoFlags,
                localPath: localPath,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String visitId,
                Value<String> blobUri = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String?> phash = const Value.absent(),
                Value<DateTime?> exifTime = const Value.absent(),
                Value<double?> exifLat = const Value.absent(),
                Value<double?> exifLon = const Value.absent(),
                Value<bool> takenInApp = const Value.absent(),
                Value<DateTime?> deviceTime = const Value.absent(),
                Value<DateTime?> serverTime = const Value.absent(),
                Value<String> photoFlags = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitPhotosCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                visitId: visitId,
                blobUri: blobUri,
                sha256: sha256,
                phash: phash,
                exifTime: exifTime,
                exifLat: exifLat,
                exifLon: exifLon,
                takenInApp: takenInApp,
                deviceTime: deviceTime,
                serverTime: serverTime,
                photoFlags: photoFlags,
                localPath: localPath,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VisitPhotosTable, VisitPhoto>(table),
                  BaseReferences<_$AppDatabase, $VisitPhotosTable, VisitPhoto>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisitPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisitPhotosTable,
      VisitPhoto,
      $$VisitPhotosTableFilterComposer,
      $$VisitPhotosTableOrderingComposer,
      $$VisitPhotosTableAnnotationComposer,
      $$VisitPhotosTableCreateCompanionBuilder,
      $$VisitPhotosTableUpdateCompanionBuilder,
      (
        VisitPhoto,
        BaseReferences<_$AppDatabase, $VisitPhotosTable, VisitPhoto>,
      ),
      VisitPhoto,
      PrefetchHooks Function()
    >;
typedef $$VisitConfirmationsTableCreateCompanionBuilder =
    VisitConfirmationsCompanion Function({
      required String id,
      Value<int> version,
      required DateTime updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      required String visitId,
      required String channel,
      Value<String> status,
      Value<DateTime?> requestedAt,
      Value<DateTime?> expiresAt,
      Value<DateTime?> confirmedAt,
      Value<String?> farmerPhoneLast4,
      Value<int?> rating,
      Value<String?> token,
      Value<String> extra,
      Value<int> rowid,
    });
typedef $$VisitConfirmationsTableUpdateCompanionBuilder =
    VisitConfirmationsCompanion Function({
      Value<String> id,
      Value<int> version,
      Value<DateTime> updatedAt,
      Value<bool> dirty,
      Value<bool> deleted,
      Value<String> visitId,
      Value<String> channel,
      Value<String> status,
      Value<DateTime?> requestedAt,
      Value<DateTime?> expiresAt,
      Value<DateTime?> confirmedAt,
      Value<String?> farmerPhoneLast4,
      Value<int?> rating,
      Value<String?> token,
      Value<String> extra,
      Value<int> rowid,
    });

class $$VisitConfirmationsTableFilterComposer
    extends Composer<_$AppDatabase, $VisitConfirmationsTable> {
  $$VisitConfirmationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get visitId => $composableBuilder(
    column: $table.visitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmerPhoneLast4 => $composableBuilder(
    column: $table.farmerPhoneLast4,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisitConfirmationsTableOrderingComposer
    extends Composer<_$AppDatabase, $VisitConfirmationsTable> {
  $$VisitConfirmationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get visitId => $composableBuilder(
    column: $table.visitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmerPhoneLast4 => $composableBuilder(
    column: $table.farmerPhoneLast4,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisitConfirmationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VisitConfirmationsTable> {
  $$VisitConfirmationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get visitId =>
      $composableBuilder(column: $table.visitId, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get confirmedAt => $composableBuilder(
    column: $table.confirmedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get farmerPhoneLast4 => $composableBuilder(
    column: $table.farmerPhoneLast4,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$VisitConfirmationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VisitConfirmationsTable,
          VisitConfirmation,
          $$VisitConfirmationsTableFilterComposer,
          $$VisitConfirmationsTableOrderingComposer,
          $$VisitConfirmationsTableAnnotationComposer,
          $$VisitConfirmationsTableCreateCompanionBuilder,
          $$VisitConfirmationsTableUpdateCompanionBuilder,
          (
            VisitConfirmation,
            BaseReferences<
              _$AppDatabase,
              $VisitConfirmationsTable,
              VisitConfirmation
            >,
          ),
          VisitConfirmation,
          PrefetchHooks Function()
        > {
  $$VisitConfirmationsTableTableManager(
    _$AppDatabase db,
    $VisitConfirmationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisitConfirmationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisitConfirmationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VisitConfirmationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> visitId = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> requestedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime?> confirmedAt = const Value.absent(),
                Value<String?> farmerPhoneLast4 = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<String?> token = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitConfirmationsCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                visitId: visitId,
                channel: channel,
                status: status,
                requestedAt: requestedAt,
                expiresAt: expiresAt,
                confirmedAt: confirmedAt,
                farmerPhoneLast4: farmerPhoneLast4,
                rating: rating,
                token: token,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                required String visitId,
                required String channel,
                Value<String> status = const Value.absent(),
                Value<DateTime?> requestedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime?> confirmedAt = const Value.absent(),
                Value<String?> farmerPhoneLast4 = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<String?> token = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitConfirmationsCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                visitId: visitId,
                channel: channel,
                status: status,
                requestedAt: requestedAt,
                expiresAt: expiresAt,
                confirmedAt: confirmedAt,
                farmerPhoneLast4: farmerPhoneLast4,
                rating: rating,
                token: token,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VisitConfirmationsTable, VisitConfirmation>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $VisitConfirmationsTable,
                    VisitConfirmation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisitConfirmationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VisitConfirmationsTable,
      VisitConfirmation,
      $$VisitConfirmationsTableFilterComposer,
      $$VisitConfirmationsTableOrderingComposer,
      $$VisitConfirmationsTableAnnotationComposer,
      $$VisitConfirmationsTableCreateCompanionBuilder,
      $$VisitConfirmationsTableUpdateCompanionBuilder,
      (
        VisitConfirmation,
        BaseReferences<
          _$AppDatabase,
          $VisitConfirmationsTable,
          VisitConfirmation
        >,
      ),
      VisitConfirmation,
      PrefetchHooks Function()
    >;
typedef $$CatalogProductsTableCreateCompanionBuilder =
    CatalogProductsCompanion Function({
      required String id,
      required String name,
      Value<String> brand,
      Value<bool> ownBrand,
      Value<String> category,
      Value<String?> activeIngredient,
      Value<String?> formulation,
      Value<String> names,
      Value<String?> imageUri,
      Value<int> gstRateBp,
      Value<bool> active,
      Value<String> searchText,
      Value<int> version,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CatalogProductsTableUpdateCompanionBuilder =
    CatalogProductsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> brand,
      Value<bool> ownBrand,
      Value<String> category,
      Value<String?> activeIngredient,
      Value<String?> formulation,
      Value<String> names,
      Value<String?> imageUri,
      Value<int> gstRateBp,
      Value<bool> active,
      Value<String> searchText,
      Value<int> version,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CatalogProductsTableFilterComposer
    extends Composer<_$AppDatabase, $CatalogProductsTable> {
  $$CatalogProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get ownBrand => $composableBuilder(
    column: $table.ownBrand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeIngredient => $composableBuilder(
    column: $table.activeIngredient,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get formulation => $composableBuilder(
    column: $table.formulation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get names => $composableBuilder(
    column: $table.names,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUri => $composableBuilder(
    column: $table.imageUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gstRateBp => $composableBuilder(
    column: $table.gstRateBp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $CatalogProductsTable> {
  $$CatalogProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get ownBrand => $composableBuilder(
    column: $table.ownBrand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeIngredient => $composableBuilder(
    column: $table.activeIngredient,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get formulation => $composableBuilder(
    column: $table.formulation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get names => $composableBuilder(
    column: $table.names,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUri => $composableBuilder(
    column: $table.imageUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gstRateBp => $composableBuilder(
    column: $table.gstRateBp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CatalogProductsTable> {
  $$CatalogProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<bool> get ownBrand =>
      $composableBuilder(column: $table.ownBrand, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get activeIngredient => $composableBuilder(
    column: $table.activeIngredient,
    builder: (column) => column,
  );

  GeneratedColumn<String> get formulation => $composableBuilder(
    column: $table.formulation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get names =>
      $composableBuilder(column: $table.names, builder: (column) => column);

  GeneratedColumn<String> get imageUri =>
      $composableBuilder(column: $table.imageUri, builder: (column) => column);

  GeneratedColumn<int> get gstRateBp =>
      $composableBuilder(column: $table.gstRateBp, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CatalogProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CatalogProductsTable,
          CatalogProductRow,
          $$CatalogProductsTableFilterComposer,
          $$CatalogProductsTableOrderingComposer,
          $$CatalogProductsTableAnnotationComposer,
          $$CatalogProductsTableCreateCompanionBuilder,
          $$CatalogProductsTableUpdateCompanionBuilder,
          (
            CatalogProductRow,
            BaseReferences<
              _$AppDatabase,
              $CatalogProductsTable,
              CatalogProductRow
            >,
          ),
          CatalogProductRow,
          PrefetchHooks Function()
        > {
  $$CatalogProductsTableTableManager(
    _$AppDatabase db,
    $CatalogProductsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> brand = const Value.absent(),
                Value<bool> ownBrand = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> activeIngredient = const Value.absent(),
                Value<String?> formulation = const Value.absent(),
                Value<String> names = const Value.absent(),
                Value<String?> imageUri = const Value.absent(),
                Value<int> gstRateBp = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogProductsCompanion(
                id: id,
                name: name,
                brand: brand,
                ownBrand: ownBrand,
                category: category,
                activeIngredient: activeIngredient,
                formulation: formulation,
                names: names,
                imageUri: imageUri,
                gstRateBp: gstRateBp,
                active: active,
                searchText: searchText,
                version: version,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> brand = const Value.absent(),
                Value<bool> ownBrand = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> activeIngredient = const Value.absent(),
                Value<String?> formulation = const Value.absent(),
                Value<String> names = const Value.absent(),
                Value<String?> imageUri = const Value.absent(),
                Value<int> gstRateBp = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CatalogProductsCompanion.insert(
                id: id,
                name: name,
                brand: brand,
                ownBrand: ownBrand,
                category: category,
                activeIngredient: activeIngredient,
                formulation: formulation,
                names: names,
                imageUri: imageUri,
                gstRateBp: gstRateBp,
                active: active,
                searchText: searchText,
                version: version,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogProductsTable, CatalogProductRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CatalogProductsTable,
                    CatalogProductRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CatalogProductsTable,
      CatalogProductRow,
      $$CatalogProductsTableFilterComposer,
      $$CatalogProductsTableOrderingComposer,
      $$CatalogProductsTableAnnotationComposer,
      $$CatalogProductsTableCreateCompanionBuilder,
      $$CatalogProductsTableUpdateCompanionBuilder,
      (
        CatalogProductRow,
        BaseReferences<_$AppDatabase, $CatalogProductsTable, CatalogProductRow>,
      ),
      CatalogProductRow,
      PrefetchHooks Function()
    >;
typedef $$CatalogSkusTableCreateCompanionBuilder =
    CatalogSkusCompanion Function({
      required String id,
      required String productId,
      Value<String> packLabel,
      Value<String?> barcode,
      Value<int> mrpPaise,
      Value<bool> active,
      Value<int> version,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CatalogSkusTableUpdateCompanionBuilder =
    CatalogSkusCompanion Function({
      Value<String> id,
      Value<String> productId,
      Value<String> packLabel,
      Value<String?> barcode,
      Value<int> mrpPaise,
      Value<bool> active,
      Value<int> version,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CatalogSkusTableFilterComposer
    extends Composer<_$AppDatabase, $CatalogSkusTable> {
  $$CatalogSkusTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packLabel => $composableBuilder(
    column: $table.packLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mrpPaise => $composableBuilder(
    column: $table.mrpPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogSkusTableOrderingComposer
    extends Composer<_$AppDatabase, $CatalogSkusTable> {
  $$CatalogSkusTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packLabel => $composableBuilder(
    column: $table.packLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mrpPaise => $composableBuilder(
    column: $table.mrpPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogSkusTableAnnotationComposer
    extends Composer<_$AppDatabase, $CatalogSkusTable> {
  $$CatalogSkusTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get packLabel =>
      $composableBuilder(column: $table.packLabel, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<int> get mrpPaise =>
      $composableBuilder(column: $table.mrpPaise, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CatalogSkusTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CatalogSkusTable,
          CatalogSkuRow,
          $$CatalogSkusTableFilterComposer,
          $$CatalogSkusTableOrderingComposer,
          $$CatalogSkusTableAnnotationComposer,
          $$CatalogSkusTableCreateCompanionBuilder,
          $$CatalogSkusTableUpdateCompanionBuilder,
          (
            CatalogSkuRow,
            BaseReferences<_$AppDatabase, $CatalogSkusTable, CatalogSkuRow>,
          ),
          CatalogSkuRow,
          PrefetchHooks Function()
        > {
  $$CatalogSkusTableTableManager(_$AppDatabase db, $CatalogSkusTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogSkusTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogSkusTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogSkusTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String> packLabel = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<int> mrpPaise = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogSkusCompanion(
                id: id,
                productId: productId,
                packLabel: packLabel,
                barcode: barcode,
                mrpPaise: mrpPaise,
                active: active,
                version: version,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String productId,
                Value<String> packLabel = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<int> mrpPaise = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CatalogSkusCompanion.insert(
                id: id,
                productId: productId,
                packLabel: packLabel,
                barcode: barcode,
                mrpPaise: mrpPaise,
                active: active,
                version: version,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogSkusTable, CatalogSkuRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CatalogSkusTable,
                    CatalogSkuRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogSkusTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CatalogSkusTable,
      CatalogSkuRow,
      $$CatalogSkusTableFilterComposer,
      $$CatalogSkusTableOrderingComposer,
      $$CatalogSkusTableAnnotationComposer,
      $$CatalogSkusTableCreateCompanionBuilder,
      $$CatalogSkusTableUpdateCompanionBuilder,
      (
        CatalogSkuRow,
        BaseReferences<_$AppDatabase, $CatalogSkusTable, CatalogSkuRow>,
      ),
      CatalogSkuRow,
      PrefetchHooks Function()
    >;
typedef $$CatalogPricesTableCreateCompanionBuilder =
    CatalogPricesCompanion Function({
      required String storeId,
      required String skuId,
      required int pricePaise,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CatalogPricesTableUpdateCompanionBuilder =
    CatalogPricesCompanion Function({
      Value<String> storeId,
      Value<String> skuId,
      Value<int> pricePaise,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CatalogPricesTableFilterComposer
    extends Composer<_$AppDatabase, $CatalogPricesTable> {
  $$CatalogPricesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skuId => $composableBuilder(
    column: $table.skuId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogPricesTableOrderingComposer
    extends Composer<_$AppDatabase, $CatalogPricesTable> {
  $$CatalogPricesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skuId => $composableBuilder(
    column: $table.skuId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogPricesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CatalogPricesTable> {
  $$CatalogPricesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get skuId =>
      $composableBuilder(column: $table.skuId, builder: (column) => column);

  GeneratedColumn<int> get pricePaise => $composableBuilder(
    column: $table.pricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CatalogPricesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CatalogPricesTable,
          CatalogPriceRow,
          $$CatalogPricesTableFilterComposer,
          $$CatalogPricesTableOrderingComposer,
          $$CatalogPricesTableAnnotationComposer,
          $$CatalogPricesTableCreateCompanionBuilder,
          $$CatalogPricesTableUpdateCompanionBuilder,
          (
            CatalogPriceRow,
            BaseReferences<_$AppDatabase, $CatalogPricesTable, CatalogPriceRow>,
          ),
          CatalogPriceRow,
          PrefetchHooks Function()
        > {
  $$CatalogPricesTableTableManager(_$AppDatabase db, $CatalogPricesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogPricesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogPricesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogPricesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> storeId = const Value.absent(),
                Value<String> skuId = const Value.absent(),
                Value<int> pricePaise = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogPricesCompanion(
                storeId: storeId,
                skuId: skuId,
                pricePaise: pricePaise,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String storeId,
                required String skuId,
                required int pricePaise,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CatalogPricesCompanion.insert(
                storeId: storeId,
                skuId: skuId,
                pricePaise: pricePaise,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogPricesTable, CatalogPriceRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CatalogPricesTable,
                    CatalogPriceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogPricesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CatalogPricesTable,
      CatalogPriceRow,
      $$CatalogPricesTableFilterComposer,
      $$CatalogPricesTableOrderingComposer,
      $$CatalogPricesTableAnnotationComposer,
      $$CatalogPricesTableCreateCompanionBuilder,
      $$CatalogPricesTableUpdateCompanionBuilder,
      (
        CatalogPriceRow,
        BaseReferences<_$AppDatabase, $CatalogPricesTable, CatalogPriceRow>,
      ),
      CatalogPriceRow,
      PrefetchHooks Function()
    >;
typedef $$StockSnapshotsTableCreateCompanionBuilder =
    StockSnapshotsCompanion Function({
      required String storeId,
      required String skuId,
      Value<double?> onHand,
      Value<double?> available,
      required DateTime asOf,
      Value<int> rowid,
    });
typedef $$StockSnapshotsTableUpdateCompanionBuilder =
    StockSnapshotsCompanion Function({
      Value<String> storeId,
      Value<String> skuId,
      Value<double?> onHand,
      Value<double?> available,
      Value<DateTime> asOf,
      Value<int> rowid,
    });

class $$StockSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $StockSnapshotsTable> {
  $$StockSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skuId => $composableBuilder(
    column: $table.skuId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get onHand => $composableBuilder(
    column: $table.onHand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get available => $composableBuilder(
    column: $table.available,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StockSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $StockSnapshotsTable> {
  $$StockSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skuId => $composableBuilder(
    column: $table.skuId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get onHand => $composableBuilder(
    column: $table.onHand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get available => $composableBuilder(
    column: $table.available,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get asOf => $composableBuilder(
    column: $table.asOf,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StockSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StockSnapshotsTable> {
  $$StockSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get skuId =>
      $composableBuilder(column: $table.skuId, builder: (column) => column);

  GeneratedColumn<double> get onHand =>
      $composableBuilder(column: $table.onHand, builder: (column) => column);

  GeneratedColumn<double> get available =>
      $composableBuilder(column: $table.available, builder: (column) => column);

  GeneratedColumn<DateTime> get asOf =>
      $composableBuilder(column: $table.asOf, builder: (column) => column);
}

class $$StockSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StockSnapshotsTable,
          StockSnapshotRow,
          $$StockSnapshotsTableFilterComposer,
          $$StockSnapshotsTableOrderingComposer,
          $$StockSnapshotsTableAnnotationComposer,
          $$StockSnapshotsTableCreateCompanionBuilder,
          $$StockSnapshotsTableUpdateCompanionBuilder,
          (
            StockSnapshotRow,
            BaseReferences<
              _$AppDatabase,
              $StockSnapshotsTable,
              StockSnapshotRow
            >,
          ),
          StockSnapshotRow,
          PrefetchHooks Function()
        > {
  $$StockSnapshotsTableTableManager(
    _$AppDatabase db,
    $StockSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StockSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> storeId = const Value.absent(),
                Value<String> skuId = const Value.absent(),
                Value<double?> onHand = const Value.absent(),
                Value<double?> available = const Value.absent(),
                Value<DateTime> asOf = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StockSnapshotsCompanion(
                storeId: storeId,
                skuId: skuId,
                onHand: onHand,
                available: available,
                asOf: asOf,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String storeId,
                required String skuId,
                Value<double?> onHand = const Value.absent(),
                Value<double?> available = const Value.absent(),
                required DateTime asOf,
                Value<int> rowid = const Value.absent(),
              }) => StockSnapshotsCompanion.insert(
                storeId: storeId,
                skuId: skuId,
                onHand: onHand,
                available: available,
                asOf: asOf,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StockSnapshotsTable, StockSnapshotRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $StockSnapshotsTable,
                    StockSnapshotRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StockSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StockSnapshotsTable,
      StockSnapshotRow,
      $$StockSnapshotsTableFilterComposer,
      $$StockSnapshotsTableOrderingComposer,
      $$StockSnapshotsTableAnnotationComposer,
      $$StockSnapshotsTableCreateCompanionBuilder,
      $$StockSnapshotsTableUpdateCompanionBuilder,
      (
        StockSnapshotRow,
        BaseReferences<_$AppDatabase, $StockSnapshotsTable, StockSnapshotRow>,
      ),
      StockSnapshotRow,
      PrefetchHooks Function()
    >;
typedef $$CatalogStoresTableCreateCompanionBuilder =
    CatalogStoresCompanion Function({
      required String id,
      Value<String> code,
      Value<String> name,
      Value<String> district,
      Value<DateTime?> catalogRefreshedAt,
      Value<int> rowid,
    });
typedef $$CatalogStoresTableUpdateCompanionBuilder =
    CatalogStoresCompanion Function({
      Value<String> id,
      Value<String> code,
      Value<String> name,
      Value<String> district,
      Value<DateTime?> catalogRefreshedAt,
      Value<int> rowid,
    });

class $$CatalogStoresTableFilterComposer
    extends Composer<_$AppDatabase, $CatalogStoresTable> {
  $$CatalogStoresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get district => $composableBuilder(
    column: $table.district,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get catalogRefreshedAt => $composableBuilder(
    column: $table.catalogRefreshedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogStoresTableOrderingComposer
    extends Composer<_$AppDatabase, $CatalogStoresTable> {
  $$CatalogStoresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get district => $composableBuilder(
    column: $table.district,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get catalogRefreshedAt => $composableBuilder(
    column: $table.catalogRefreshedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogStoresTableAnnotationComposer
    extends Composer<_$AppDatabase, $CatalogStoresTable> {
  $$CatalogStoresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get district =>
      $composableBuilder(column: $table.district, builder: (column) => column);

  GeneratedColumn<DateTime> get catalogRefreshedAt => $composableBuilder(
    column: $table.catalogRefreshedAt,
    builder: (column) => column,
  );
}

class $$CatalogStoresTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CatalogStoresTable,
          CatalogStoreRow,
          $$CatalogStoresTableFilterComposer,
          $$CatalogStoresTableOrderingComposer,
          $$CatalogStoresTableAnnotationComposer,
          $$CatalogStoresTableCreateCompanionBuilder,
          $$CatalogStoresTableUpdateCompanionBuilder,
          (
            CatalogStoreRow,
            BaseReferences<_$AppDatabase, $CatalogStoresTable, CatalogStoreRow>,
          ),
          CatalogStoreRow,
          PrefetchHooks Function()
        > {
  $$CatalogStoresTableTableManager(_$AppDatabase db, $CatalogStoresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogStoresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogStoresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogStoresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> district = const Value.absent(),
                Value<DateTime?> catalogRefreshedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogStoresCompanion(
                id: id,
                code: code,
                name: name,
                district: district,
                catalogRefreshedAt: catalogRefreshedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> district = const Value.absent(),
                Value<DateTime?> catalogRefreshedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogStoresCompanion.insert(
                id: id,
                code: code,
                name: name,
                district: district,
                catalogRefreshedAt: catalogRefreshedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CatalogStoresTable, CatalogStoreRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CatalogStoresTable,
                    CatalogStoreRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogStoresTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CatalogStoresTable,
      CatalogStoreRow,
      $$CatalogStoresTableFilterComposer,
      $$CatalogStoresTableOrderingComposer,
      $$CatalogStoresTableAnnotationComposer,
      $$CatalogStoresTableCreateCompanionBuilder,
      $$CatalogStoresTableUpdateCompanionBuilder,
      (
        CatalogStoreRow,
        BaseReferences<_$AppDatabase, $CatalogStoresTable, CatalogStoreRow>,
      ),
      CatalogStoreRow,
      PrefetchHooks Function()
    >;
typedef $$OrdersTableCreateCompanionBuilder = OrdersCompanion Function({
  required String id,
  Value<int> version,
  required DateTime updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String?> farmerId,
  Value<String?> storeId,
  Value<String> status,
  Value<String> fulfilment,
  Value<String?> paymentMode,
  Value<int?> subtotalPaise,
  Value<int?> taxPaise,
  Value<int?> totalPaise,
  Value<int> estimatedTotalPaise,
  Value<DateTime?> placedAt,
  Value<String?> invoiceNo,
  Value<String?> invoiceId,
  Value<String?> notes,
  Value<String> events,
  Value<String> extra,
  Value<int> rowid,
});
typedef $$OrdersTableUpdateCompanionBuilder = OrdersCompanion Function({
  Value<String> id,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String?> farmerId,
  Value<String?> storeId,
  Value<String> status,
  Value<String> fulfilment,
  Value<String?> paymentMode,
  Value<int?> subtotalPaise,
  Value<int?> taxPaise,
  Value<int?> totalPaise,
  Value<int> estimatedTotalPaise,
  Value<DateTime?> placedAt,
  Value<String?> invoiceNo,
  Value<String?> invoiceId,
  Value<String?> notes,
  Value<String> events,
  Value<String> extra,
  Value<int> rowid,
});

class $$OrdersTableFilterComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fulfilment => $composableBuilder(
    column: $table.fulfilment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taxPaise => $composableBuilder(
    column: $table.taxPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedTotalPaise => $composableBuilder(
    column: $table.estimatedTotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get placedAt => $composableBuilder(
    column: $table.placedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invoiceNo => $composableBuilder(
    column: $table.invoiceNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get invoiceId => $composableBuilder(
    column: $table.invoiceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get events => $composableBuilder(
    column: $table.events,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrdersTableOrderingComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fulfilment => $composableBuilder(
    column: $table.fulfilment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taxPaise => $composableBuilder(
    column: $table.taxPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedTotalPaise => $composableBuilder(
    column: $table.estimatedTotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get placedAt => $composableBuilder(
    column: $table.placedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invoiceNo => $composableBuilder(
    column: $table.invoiceNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get invoiceId => $composableBuilder(
    column: $table.invoiceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get events => $composableBuilder(
    column: $table.events,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrdersTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get farmerId =>
      $composableBuilder(column: $table.farmerId, builder: (column) => column);

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get fulfilment => $composableBuilder(
    column: $table.fulfilment,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMode => $composableBuilder(
    column: $table.paymentMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get subtotalPaise => $composableBuilder(
    column: $table.subtotalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taxPaise =>
      $composableBuilder(column: $table.taxPaise, builder: (column) => column);

  GeneratedColumn<int> get totalPaise => $composableBuilder(
    column: $table.totalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedTotalPaise => $composableBuilder(
    column: $table.estimatedTotalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get placedAt =>
      $composableBuilder(column: $table.placedAt, builder: (column) => column);

  GeneratedColumn<String> get invoiceNo =>
      $composableBuilder(column: $table.invoiceNo, builder: (column) => column);

  GeneratedColumn<String> get invoiceId =>
      $composableBuilder(column: $table.invoiceId, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get events =>
      $composableBuilder(column: $table.events, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$OrdersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrdersTable,
          OrderRow,
          $$OrdersTableFilterComposer,
          $$OrdersTableOrderingComposer,
          $$OrdersTableAnnotationComposer,
          $$OrdersTableCreateCompanionBuilder,
          $$OrdersTableUpdateCompanionBuilder,
          (OrderRow, BaseReferences<_$AppDatabase, $OrdersTable, OrderRow>),
          OrderRow,
          PrefetchHooks Function()
        > {
  $$OrdersTableTableManager(_$AppDatabase db, $OrdersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrdersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrdersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrdersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> farmerId = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> fulfilment = const Value.absent(),
                Value<String?> paymentMode = const Value.absent(),
                Value<int?> subtotalPaise = const Value.absent(),
                Value<int?> taxPaise = const Value.absent(),
                Value<int?> totalPaise = const Value.absent(),
                Value<int> estimatedTotalPaise = const Value.absent(),
                Value<DateTime?> placedAt = const Value.absent(),
                Value<String?> invoiceNo = const Value.absent(),
                Value<String?> invoiceId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> events = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrdersCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                storeId: storeId,
                status: status,
                fulfilment: fulfilment,
                paymentMode: paymentMode,
                subtotalPaise: subtotalPaise,
                taxPaise: taxPaise,
                totalPaise: totalPaise,
                estimatedTotalPaise: estimatedTotalPaise,
                placedAt: placedAt,
                invoiceNo: invoiceNo,
                invoiceId: invoiceId,
                notes: notes,
                events: events,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> farmerId = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> fulfilment = const Value.absent(),
                Value<String?> paymentMode = const Value.absent(),
                Value<int?> subtotalPaise = const Value.absent(),
                Value<int?> taxPaise = const Value.absent(),
                Value<int?> totalPaise = const Value.absent(),
                Value<int> estimatedTotalPaise = const Value.absent(),
                Value<DateTime?> placedAt = const Value.absent(),
                Value<String?> invoiceNo = const Value.absent(),
                Value<String?> invoiceId = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String> events = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrdersCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                farmerId: farmerId,
                storeId: storeId,
                status: status,
                fulfilment: fulfilment,
                paymentMode: paymentMode,
                subtotalPaise: subtotalPaise,
                taxPaise: taxPaise,
                totalPaise: totalPaise,
                estimatedTotalPaise: estimatedTotalPaise,
                placedAt: placedAt,
                invoiceNo: invoiceNo,
                invoiceId: invoiceId,
                notes: notes,
                events: events,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OrdersTable, OrderRow>(table),
                  BaseReferences<_$AppDatabase, $OrdersTable, OrderRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrdersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrdersTable,
      OrderRow,
      $$OrdersTableFilterComposer,
      $$OrdersTableOrderingComposer,
      $$OrdersTableAnnotationComposer,
      $$OrdersTableCreateCompanionBuilder,
      $$OrdersTableUpdateCompanionBuilder,
      (OrderRow, BaseReferences<_$AppDatabase, $OrdersTable, OrderRow>),
      OrderRow,
      PrefetchHooks Function()
    >;
typedef $$OrderLinesTableCreateCompanionBuilder = OrderLinesCompanion Function({
  required String id,
  required String orderId,
  required String skuId,
  required double qty,
  Value<int?> unitPricePaise,
  Value<int?> lineTotalPaise,
  Value<int> estimatedUnitPricePaise,
  Value<String> productName,
  Value<String> packLabel,
  Value<String?> labelClaimId,
  Value<int> position,
  Value<int> rowid,
});
typedef $$OrderLinesTableUpdateCompanionBuilder = OrderLinesCompanion Function({
  Value<String> id,
  Value<String> orderId,
  Value<String> skuId,
  Value<double> qty,
  Value<int?> unitPricePaise,
  Value<int?> lineTotalPaise,
  Value<int> estimatedUnitPricePaise,
  Value<String> productName,
  Value<String> packLabel,
  Value<String?> labelClaimId,
  Value<int> position,
  Value<int> rowid,
});

class $$OrderLinesTableFilterComposer
    extends Composer<_$AppDatabase, $OrderLinesTable> {
  $$OrderLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skuId => $composableBuilder(
    column: $table.skuId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get qty => $composableBuilder(
    column: $table.qty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitPricePaise => $composableBuilder(
    column: $table.unitPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedUnitPricePaise => $composableBuilder(
    column: $table.estimatedUnitPricePaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packLabel => $composableBuilder(
    column: $table.packLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get labelClaimId => $composableBuilder(
    column: $table.labelClaimId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrderLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderLinesTable> {
  $$OrderLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skuId => $composableBuilder(
    column: $table.skuId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get qty => $composableBuilder(
    column: $table.qty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitPricePaise => $composableBuilder(
    column: $table.unitPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedUnitPricePaise => $composableBuilder(
    column: $table.estimatedUnitPricePaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packLabel => $composableBuilder(
    column: $table.packLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get labelClaimId => $composableBuilder(
    column: $table.labelClaimId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrderLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderLinesTable> {
  $$OrderLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<String> get skuId =>
      $composableBuilder(column: $table.skuId, builder: (column) => column);

  GeneratedColumn<double> get qty =>
      $composableBuilder(column: $table.qty, builder: (column) => column);

  GeneratedColumn<int> get unitPricePaise => $composableBuilder(
    column: $table.unitPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lineTotalPaise => $composableBuilder(
    column: $table.lineTotalPaise,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedUnitPricePaise => $composableBuilder(
    column: $table.estimatedUnitPricePaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packLabel =>
      $composableBuilder(column: $table.packLabel, builder: (column) => column);

  GeneratedColumn<String> get labelClaimId => $composableBuilder(
    column: $table.labelClaimId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$OrderLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrderLinesTable,
          OrderLineRow,
          $$OrderLinesTableFilterComposer,
          $$OrderLinesTableOrderingComposer,
          $$OrderLinesTableAnnotationComposer,
          $$OrderLinesTableCreateCompanionBuilder,
          $$OrderLinesTableUpdateCompanionBuilder,
          (
            OrderLineRow,
            BaseReferences<_$AppDatabase, $OrderLinesTable, OrderLineRow>,
          ),
          OrderLineRow,
          PrefetchHooks Function()
        > {
  $$OrderLinesTableTableManager(_$AppDatabase db, $OrderLinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orderId = const Value.absent(),
                Value<String> skuId = const Value.absent(),
                Value<double> qty = const Value.absent(),
                Value<int?> unitPricePaise = const Value.absent(),
                Value<int?> lineTotalPaise = const Value.absent(),
                Value<int> estimatedUnitPricePaise = const Value.absent(),
                Value<String> productName = const Value.absent(),
                Value<String> packLabel = const Value.absent(),
                Value<String?> labelClaimId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrderLinesCompanion(
                id: id,
                orderId: orderId,
                skuId: skuId,
                qty: qty,
                unitPricePaise: unitPricePaise,
                lineTotalPaise: lineTotalPaise,
                estimatedUnitPricePaise: estimatedUnitPricePaise,
                productName: productName,
                packLabel: packLabel,
                labelClaimId: labelClaimId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orderId,
                required String skuId,
                required double qty,
                Value<int?> unitPricePaise = const Value.absent(),
                Value<int?> lineTotalPaise = const Value.absent(),
                Value<int> estimatedUnitPricePaise = const Value.absent(),
                Value<String> productName = const Value.absent(),
                Value<String> packLabel = const Value.absent(),
                Value<String?> labelClaimId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrderLinesCompanion.insert(
                id: id,
                orderId: orderId,
                skuId: skuId,
                qty: qty,
                unitPricePaise: unitPricePaise,
                lineTotalPaise: lineTotalPaise,
                estimatedUnitPricePaise: estimatedUnitPricePaise,
                productName: productName,
                packLabel: packLabel,
                labelClaimId: labelClaimId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OrderLinesTable, OrderLineRow>(table),
                  BaseReferences<_$AppDatabase, $OrderLinesTable, OrderLineRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrderLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrderLinesTable,
      OrderLineRow,
      $$OrderLinesTableFilterComposer,
      $$OrderLinesTableOrderingComposer,
      $$OrderLinesTableAnnotationComposer,
      $$OrderLinesTableCreateCompanionBuilder,
      $$OrderLinesTableUpdateCompanionBuilder,
      (
        OrderLineRow,
        BaseReferences<_$AppDatabase, $OrderLinesTable, OrderLineRow>,
      ),
      OrderLineRow,
      PrefetchHooks Function()
    >;
typedef $$PaymentsTableCreateCompanionBuilder = PaymentsCompanion Function({
  required String id,
  Value<int> version,
  required DateTime updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String?> orderId,
  Value<String?> farmerId,
  Value<String?> storeId,
  required String mode,
  Value<int> amountPaise,
  Value<String> status,
  Value<String?> receiptUri,
  Value<String?> receiptPath,
  Value<String?> collectedBy,
  required DateTime collectedAt,
  Value<DateTime?> paidAt,
  Value<DateTime?> expiresAt,
  Value<String?> shortUrl,
  Value<String?> sentVia,
  Value<String?> qrPayload,
  Value<String?> failureReason,
  Value<String> extra,
  Value<int> rowid,
});
typedef $$PaymentsTableUpdateCompanionBuilder = PaymentsCompanion Function({
  Value<String> id,
  Value<int> version,
  Value<DateTime> updatedAt,
  Value<bool> dirty,
  Value<bool> deleted,
  Value<String?> orderId,
  Value<String?> farmerId,
  Value<String?> storeId,
  Value<String> mode,
  Value<int> amountPaise,
  Value<String> status,
  Value<String?> receiptUri,
  Value<String?> receiptPath,
  Value<String?> collectedBy,
  Value<DateTime> collectedAt,
  Value<DateTime?> paidAt,
  Value<DateTime?> expiresAt,
  Value<String?> shortUrl,
  Value<String?> sentVia,
  Value<String?> qrPayload,
  Value<String?> failureReason,
  Value<String> extra,
  Value<int> rowid,
});

class $$PaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptUri => $composableBuilder(
    column: $table.receiptUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptPath => $composableBuilder(
    column: $table.receiptPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectedBy => $composableBuilder(
    column: $table.collectedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get collectedAt => $composableBuilder(
    column: $table.collectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shortUrl => $composableBuilder(
    column: $table.shortUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sentVia => $composableBuilder(
    column: $table.sentVia,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get qrPayload => $composableBuilder(
    column: $table.qrPayload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storeId => $composableBuilder(
    column: $table.storeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptUri => $composableBuilder(
    column: $table.receiptUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptPath => $composableBuilder(
    column: $table.receiptPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectedBy => $composableBuilder(
    column: $table.collectedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get collectedAt => $composableBuilder(
    column: $table.collectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get paidAt => $composableBuilder(
    column: $table.paidAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shortUrl => $composableBuilder(
    column: $table.shortUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sentVia => $composableBuilder(
    column: $table.sentVia,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get qrPayload => $composableBuilder(
    column: $table.qrPayload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<String> get farmerId =>
      $composableBuilder(column: $table.farmerId, builder: (column) => column);

  GeneratedColumn<String> get storeId =>
      $composableBuilder(column: $table.storeId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get amountPaise => $composableBuilder(
    column: $table.amountPaise,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get receiptUri => $composableBuilder(
    column: $table.receiptUri,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptPath => $composableBuilder(
    column: $table.receiptPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get collectedBy => $composableBuilder(
    column: $table.collectedBy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get collectedAt => $composableBuilder(
    column: $table.collectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get paidAt =>
      $composableBuilder(column: $table.paidAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get shortUrl =>
      $composableBuilder(column: $table.shortUrl, builder: (column) => column);

  GeneratedColumn<String> get sentVia =>
      $composableBuilder(column: $table.sentVia, builder: (column) => column);

  GeneratedColumn<String> get qrPayload =>
      $composableBuilder(column: $table.qrPayload, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$PaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PaymentsTable,
          PaymentRow,
          $$PaymentsTableFilterComposer,
          $$PaymentsTableOrderingComposer,
          $$PaymentsTableAnnotationComposer,
          $$PaymentsTableCreateCompanionBuilder,
          $$PaymentsTableUpdateCompanionBuilder,
          (
            PaymentRow,
            BaseReferences<_$AppDatabase, $PaymentsTable, PaymentRow>,
          ),
          PaymentRow,
          PrefetchHooks Function()
        > {
  $$PaymentsTableTableManager(_$AppDatabase db, $PaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> orderId = const Value.absent(),
                Value<String?> farmerId = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> amountPaise = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> receiptUri = const Value.absent(),
                Value<String?> receiptPath = const Value.absent(),
                Value<String?> collectedBy = const Value.absent(),
                Value<DateTime> collectedAt = const Value.absent(),
                Value<DateTime?> paidAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> shortUrl = const Value.absent(),
                Value<String?> sentVia = const Value.absent(),
                Value<String?> qrPayload = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PaymentsCompanion(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                orderId: orderId,
                farmerId: farmerId,
                storeId: storeId,
                mode: mode,
                amountPaise: amountPaise,
                status: status,
                receiptUri: receiptUri,
                receiptPath: receiptPath,
                collectedBy: collectedBy,
                collectedAt: collectedAt,
                paidAt: paidAt,
                expiresAt: expiresAt,
                shortUrl: shortUrl,
                sentVia: sentVia,
                qrPayload: qrPayload,
                failureReason: failureReason,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> version = const Value.absent(),
                required DateTime updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> orderId = const Value.absent(),
                Value<String?> farmerId = const Value.absent(),
                Value<String?> storeId = const Value.absent(),
                required String mode,
                Value<int> amountPaise = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> receiptUri = const Value.absent(),
                Value<String?> receiptPath = const Value.absent(),
                Value<String?> collectedBy = const Value.absent(),
                required DateTime collectedAt,
                Value<DateTime?> paidAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> shortUrl = const Value.absent(),
                Value<String?> sentVia = const Value.absent(),
                Value<String?> qrPayload = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PaymentsCompanion.insert(
                id: id,
                version: version,
                updatedAt: updatedAt,
                dirty: dirty,
                deleted: deleted,
                orderId: orderId,
                farmerId: farmerId,
                storeId: storeId,
                mode: mode,
                amountPaise: amountPaise,
                status: status,
                receiptUri: receiptUri,
                receiptPath: receiptPath,
                collectedBy: collectedBy,
                collectedAt: collectedAt,
                paidAt: paidAt,
                expiresAt: expiresAt,
                shortUrl: shortUrl,
                sentVia: sentVia,
                qrPayload: qrPayload,
                failureReason: failureReason,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PaymentsTable, PaymentRow>(table),
                  BaseReferences<_$AppDatabase, $PaymentsTable, PaymentRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PaymentsTable,
      PaymentRow,
      $$PaymentsTableFilterComposer,
      $$PaymentsTableOrderingComposer,
      $$PaymentsTableAnnotationComposer,
      $$PaymentsTableCreateCompanionBuilder,
      $$PaymentsTableUpdateCompanionBuilder,
      (PaymentRow, BaseReferences<_$AppDatabase, $PaymentsTable, PaymentRow>),
      PaymentRow,
      PrefetchHooks Function()
    >;
typedef $$KhataSnapshotsTableCreateCompanionBuilder =
    KhataSnapshotsCompanion Function({
      required String farmerId,
      required String data,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$KhataSnapshotsTableUpdateCompanionBuilder =
    KhataSnapshotsCompanion Function({
      Value<String> farmerId,
      Value<String> data,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$KhataSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $KhataSnapshotsTable> {
  $$KhataSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KhataSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $KhataSnapshotsTable> {
  $$KhataSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get farmerId => $composableBuilder(
    column: $table.farmerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KhataSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KhataSnapshotsTable> {
  $$KhataSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get farmerId =>
      $composableBuilder(column: $table.farmerId, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$KhataSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KhataSnapshotsTable,
          KhataSnapshotRow,
          $$KhataSnapshotsTableFilterComposer,
          $$KhataSnapshotsTableOrderingComposer,
          $$KhataSnapshotsTableAnnotationComposer,
          $$KhataSnapshotsTableCreateCompanionBuilder,
          $$KhataSnapshotsTableUpdateCompanionBuilder,
          (
            KhataSnapshotRow,
            BaseReferences<
              _$AppDatabase,
              $KhataSnapshotsTable,
              KhataSnapshotRow
            >,
          ),
          KhataSnapshotRow,
          PrefetchHooks Function()
        > {
  $$KhataSnapshotsTableTableManager(
    _$AppDatabase db,
    $KhataSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KhataSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KhataSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KhataSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> farmerId = const Value.absent(),
                Value<String> data = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KhataSnapshotsCompanion(
                farmerId: farmerId,
                data: data,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String farmerId,
                required String data,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => KhataSnapshotsCompanion.insert(
                farmerId: farmerId,
                data: data,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KhataSnapshotsTable, KhataSnapshotRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $KhataSnapshotsTable,
                    KhataSnapshotRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KhataSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KhataSnapshotsTable,
      KhataSnapshotRow,
      $$KhataSnapshotsTableFilterComposer,
      $$KhataSnapshotsTableOrderingComposer,
      $$KhataSnapshotsTableAnnotationComposer,
      $$KhataSnapshotsTableCreateCompanionBuilder,
      $$KhataSnapshotsTableUpdateCompanionBuilder,
      (
        KhataSnapshotRow,
        BaseReferences<_$AppDatabase, $KhataSnapshotsTable, KhataSnapshotRow>,
      ),
      KhataSnapshotRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$KvTableTableManager get kv => $$KvTableTableManager(_db, _db.kv);
  $$FarmersTableTableManager get farmers =>
      $$FarmersTableTableManager(_db, _db.farmers);
  $$FarmsTableTableManager get farms =>
      $$FarmsTableTableManager(_db, _db.farms);
  $$CropPlotsTableTableManager get cropPlots =>
      $$CropPlotsTableTableManager(_db, _db.cropPlots);
  $$ConsentRecordsTableTableManager get consentRecords =>
      $$ConsentRecordsTableTableManager(_db, _db.consentRecords);
  $$OutboxTableTableTableManager get outboxTable =>
      $$OutboxTableTableTableManager(_db, _db.outboxTable);
  $$UploadsTableTableManager get uploads =>
      $$UploadsTableTableManager(_db, _db.uploads);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
  $$SyncedRefsTableTableManager get syncedRefs =>
      $$SyncedRefsTableTableManager(_db, _db.syncedRefs);
  $$VillagesTableTableManager get villages =>
      $$VillagesTableTableManager(_db, _db.villages);
  $$DutySessionsTableTableManager get dutySessions =>
      $$DutySessionsTableTableManager(_db, _db.dutySessions);
  $$LocationBufferTableTableManager get locationBuffer =>
      $$LocationBufferTableTableManager(_db, _db.locationBuffer);
  $$SyncDocsTableTableManager get syncDocs =>
      $$SyncDocsTableTableManager(_db, _db.syncDocs);
  $$VisitsTableTableManager get visits =>
      $$VisitsTableTableManager(_db, _db.visits);
  $$VisitPhotosTableTableManager get visitPhotos =>
      $$VisitPhotosTableTableManager(_db, _db.visitPhotos);
  $$VisitConfirmationsTableTableManager get visitConfirmations =>
      $$VisitConfirmationsTableTableManager(_db, _db.visitConfirmations);
  $$CatalogProductsTableTableManager get catalogProducts =>
      $$CatalogProductsTableTableManager(_db, _db.catalogProducts);
  $$CatalogSkusTableTableManager get catalogSkus =>
      $$CatalogSkusTableTableManager(_db, _db.catalogSkus);
  $$CatalogPricesTableTableManager get catalogPrices =>
      $$CatalogPricesTableTableManager(_db, _db.catalogPrices);
  $$StockSnapshotsTableTableManager get stockSnapshots =>
      $$StockSnapshotsTableTableManager(_db, _db.stockSnapshots);
  $$CatalogStoresTableTableManager get catalogStores =>
      $$CatalogStoresTableTableManager(_db, _db.catalogStores);
  $$OrdersTableTableManager get orders =>
      $$OrdersTableTableManager(_db, _db.orders);
  $$OrderLinesTableTableManager get orderLines =>
      $$OrderLinesTableTableManager(_db, _db.orderLines);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db, _db.payments);
  $$KhataSnapshotsTableTableManager get khataSnapshots =>
      $$KhataSnapshotsTableTableManager(_db, _db.khataSnapshots);
}
