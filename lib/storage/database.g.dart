// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $TracksTable extends Tracks with TableInfo<$TracksTable, Track> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TracksTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _distanceMetersMeta = const VerificationMeta(
    'distanceMeters',
  );
  @override
  late final GeneratedColumn<double> distanceMeters = GeneratedColumn<double>(
    'distance_meters',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _elevationGainMetersMeta =
      const VerificationMeta('elevationGainMeters');
  @override
  late final GeneratedColumn<double> elevationGainMeters =
      GeneratedColumn<double>(
        'elevation_gain_meters',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    createdAt,
    distanceMeters,
    durationSeconds,
    elevationGainMeters,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Track> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('distance_meters')) {
      context.handle(
        _distanceMetersMeta,
        distanceMeters.isAcceptableOrUnknown(
          data['distance_meters']!,
          _distanceMetersMeta,
        ),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('elevation_gain_meters')) {
      context.handle(
        _elevationGainMetersMeta,
        elevationGainMeters.isAcceptableOrUnknown(
          data['elevation_gain_meters']!,
          _elevationGainMetersMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Track map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Track(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      distanceMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_meters'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      elevationGainMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}elevation_gain_meters'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $TracksTable createAlias(String alias) {
    return $TracksTable(attachedDatabase, alias);
  }
}

class Track extends DataClass implements Insertable<Track> {
  final int id;
  final String name;
  final DateTime createdAt;
  final double distanceMeters;
  final int durationSeconds;
  final double elevationGainMeters;
  final String source;
  const Track({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.elevationGainMeters,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['distance_meters'] = Variable<double>(distanceMeters);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['elevation_gain_meters'] = Variable<double>(elevationGainMeters);
    map['source'] = Variable<String>(source);
    return map;
  }

  TracksCompanion toCompanion(bool nullToAbsent) {
    return TracksCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      distanceMeters: Value(distanceMeters),
      durationSeconds: Value(durationSeconds),
      elevationGainMeters: Value(elevationGainMeters),
      source: Value(source),
    );
  }

  factory Track.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Track(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      distanceMeters: serializer.fromJson<double>(json['distanceMeters']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      elevationGainMeters: serializer.fromJson<double>(
        json['elevationGainMeters'],
      ),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'distanceMeters': serializer.toJson<double>(distanceMeters),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'elevationGainMeters': serializer.toJson<double>(elevationGainMeters),
      'source': serializer.toJson<String>(source),
    };
  }

  Track copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    double? distanceMeters,
    int? durationSeconds,
    double? elevationGainMeters,
    String? source,
  }) => Track(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
    source: source ?? this.source,
  );
  Track copyWithCompanion(TracksCompanion data) {
    return Track(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      distanceMeters: data.distanceMeters.present
          ? data.distanceMeters.value
          : this.distanceMeters,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      elevationGainMeters: data.elevationGainMeters.present
          ? data.elevationGainMeters.value
          : this.elevationGainMeters,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Track(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('elevationGainMeters: $elevationGainMeters, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    distanceMeters,
    durationSeconds,
    elevationGainMeters,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.distanceMeters == this.distanceMeters &&
          other.durationSeconds == this.durationSeconds &&
          other.elevationGainMeters == this.elevationGainMeters &&
          other.source == this.source);
}

class TracksCompanion extends UpdateCompanion<Track> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<double> distanceMeters;
  final Value<int> durationSeconds;
  final Value<double> elevationGainMeters;
  final Value<String> source;
  const TracksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.distanceMeters = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.elevationGainMeters = const Value.absent(),
    this.source = const Value.absent(),
  });
  TracksCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required DateTime createdAt,
    this.distanceMeters = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.elevationGainMeters = const Value.absent(),
    required String source,
  }) : name = Value(name),
       createdAt = Value(createdAt),
       source = Value(source);
  static Insertable<Track> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<double>? distanceMeters,
    Expression<int>? durationSeconds,
    Expression<double>? elevationGainMeters,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (distanceMeters != null) 'distance_meters': distanceMeters,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (elevationGainMeters != null)
        'elevation_gain_meters': elevationGainMeters,
      if (source != null) 'source': source,
    });
  }

  TracksCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<double>? distanceMeters,
    Value<int>? durationSeconds,
    Value<double>? elevationGainMeters,
    Value<String>? source,
  }) {
    return TracksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (distanceMeters.present) {
      map['distance_meters'] = Variable<double>(distanceMeters.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (elevationGainMeters.present) {
      map['elevation_gain_meters'] = Variable<double>(
        elevationGainMeters.value,
      );
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TracksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('distanceMeters: $distanceMeters, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('elevationGainMeters: $elevationGainMeters, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

class $TrackPointsTable extends TrackPoints
    with TableInfo<$TrackPointsTable, TrackPoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrackPointsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<int> trackId = GeneratedColumn<int>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tracks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _altitudeMetersMeta = const VerificationMeta(
    'altitudeMeters',
  );
  @override
  late final GeneratedColumn<double> altitudeMeters = GeneratedColumn<double>(
    'altitude_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accuracyMetersMeta = const VerificationMeta(
    'accuracyMeters',
  );
  @override
  late final GeneratedColumn<double> accuracyMeters = GeneratedColumn<double>(
    'accuracy_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedMetersPerSecondMeta =
      const VerificationMeta('speedMetersPerSecond');
  @override
  late final GeneratedColumn<double> speedMetersPerSecond =
      GeneratedColumn<double>(
        'speed_meters_per_second',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _headingDegreesMeta = const VerificationMeta(
    'headingDegrees',
  );
  @override
  late final GeneratedColumn<double> headingDegrees = GeneratedColumn<double>(
    'heading_degrees',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    trackId,
    sequence,
    latitude,
    longitude,
    altitudeMeters,
    timestampMs,
    accuracyMeters,
    speedMetersPerSecond,
    headingDegrees,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'track_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrackPoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('altitude_meters')) {
      context.handle(
        _altitudeMetersMeta,
        altitudeMeters.isAcceptableOrUnknown(
          data['altitude_meters']!,
          _altitudeMetersMeta,
        ),
      );
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampMsMeta);
    }
    if (data.containsKey('accuracy_meters')) {
      context.handle(
        _accuracyMetersMeta,
        accuracyMeters.isAcceptableOrUnknown(
          data['accuracy_meters']!,
          _accuracyMetersMeta,
        ),
      );
    }
    if (data.containsKey('speed_meters_per_second')) {
      context.handle(
        _speedMetersPerSecondMeta,
        speedMetersPerSecond.isAcceptableOrUnknown(
          data['speed_meters_per_second']!,
          _speedMetersPerSecondMeta,
        ),
      );
    }
    if (data.containsKey('heading_degrees')) {
      context.handle(
        _headingDegreesMeta,
        headingDegrees.isAcceptableOrUnknown(
          data['heading_degrees']!,
          _headingDegreesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TrackPoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrackPoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      altitudeMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude_meters'],
      ),
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      )!,
      accuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_meters'],
      ),
      speedMetersPerSecond: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_meters_per_second'],
      ),
      headingDegrees: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}heading_degrees'],
      ),
    );
  }

  @override
  $TrackPointsTable createAlias(String alias) {
    return $TrackPointsTable(attachedDatabase, alias);
  }
}

class TrackPoint extends DataClass implements Insertable<TrackPoint> {
  final int id;
  final int trackId;
  final int sequence;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final int timestampMs;
  final double? accuracyMeters;
  final double? speedMetersPerSecond;
  final double? headingDegrees;
  const TrackPoint({
    required this.id,
    required this.trackId,
    required this.sequence,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    required this.timestampMs,
    this.accuracyMeters,
    this.speedMetersPerSecond,
    this.headingDegrees,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['track_id'] = Variable<int>(trackId);
    map['sequence'] = Variable<int>(sequence);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    if (!nullToAbsent || altitudeMeters != null) {
      map['altitude_meters'] = Variable<double>(altitudeMeters);
    }
    map['timestamp_ms'] = Variable<int>(timestampMs);
    if (!nullToAbsent || accuracyMeters != null) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters);
    }
    if (!nullToAbsent || speedMetersPerSecond != null) {
      map['speed_meters_per_second'] = Variable<double>(speedMetersPerSecond);
    }
    if (!nullToAbsent || headingDegrees != null) {
      map['heading_degrees'] = Variable<double>(headingDegrees);
    }
    return map;
  }

  TrackPointsCompanion toCompanion(bool nullToAbsent) {
    return TrackPointsCompanion(
      id: Value(id),
      trackId: Value(trackId),
      sequence: Value(sequence),
      latitude: Value(latitude),
      longitude: Value(longitude),
      altitudeMeters: altitudeMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeMeters),
      timestampMs: Value(timestampMs),
      accuracyMeters: accuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyMeters),
      speedMetersPerSecond: speedMetersPerSecond == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMetersPerSecond),
      headingDegrees: headingDegrees == null && nullToAbsent
          ? const Value.absent()
          : Value(headingDegrees),
    );
  }

  factory TrackPoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrackPoint(
      id: serializer.fromJson<int>(json['id']),
      trackId: serializer.fromJson<int>(json['trackId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      altitudeMeters: serializer.fromJson<double?>(json['altitudeMeters']),
      timestampMs: serializer.fromJson<int>(json['timestampMs']),
      accuracyMeters: serializer.fromJson<double?>(json['accuracyMeters']),
      speedMetersPerSecond: serializer.fromJson<double?>(
        json['speedMetersPerSecond'],
      ),
      headingDegrees: serializer.fromJson<double?>(json['headingDegrees']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'trackId': serializer.toJson<int>(trackId),
      'sequence': serializer.toJson<int>(sequence),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'altitudeMeters': serializer.toJson<double?>(altitudeMeters),
      'timestampMs': serializer.toJson<int>(timestampMs),
      'accuracyMeters': serializer.toJson<double?>(accuracyMeters),
      'speedMetersPerSecond': serializer.toJson<double?>(speedMetersPerSecond),
      'headingDegrees': serializer.toJson<double?>(headingDegrees),
    };
  }

  TrackPoint copyWith({
    int? id,
    int? trackId,
    int? sequence,
    double? latitude,
    double? longitude,
    Value<double?> altitudeMeters = const Value.absent(),
    int? timestampMs,
    Value<double?> accuracyMeters = const Value.absent(),
    Value<double?> speedMetersPerSecond = const Value.absent(),
    Value<double?> headingDegrees = const Value.absent(),
  }) => TrackPoint(
    id: id ?? this.id,
    trackId: trackId ?? this.trackId,
    sequence: sequence ?? this.sequence,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    altitudeMeters: altitudeMeters.present
        ? altitudeMeters.value
        : this.altitudeMeters,
    timestampMs: timestampMs ?? this.timestampMs,
    accuracyMeters: accuracyMeters.present
        ? accuracyMeters.value
        : this.accuracyMeters,
    speedMetersPerSecond: speedMetersPerSecond.present
        ? speedMetersPerSecond.value
        : this.speedMetersPerSecond,
    headingDegrees: headingDegrees.present
        ? headingDegrees.value
        : this.headingDegrees,
  );
  TrackPoint copyWithCompanion(TrackPointsCompanion data) {
    return TrackPoint(
      id: data.id.present ? data.id.value : this.id,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitudeMeters: data.altitudeMeters.present
          ? data.altitudeMeters.value
          : this.altitudeMeters,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      accuracyMeters: data.accuracyMeters.present
          ? data.accuracyMeters.value
          : this.accuracyMeters,
      speedMetersPerSecond: data.speedMetersPerSecond.present
          ? data.speedMetersPerSecond.value
          : this.speedMetersPerSecond,
      headingDegrees: data.headingDegrees.present
          ? data.headingDegrees.value
          : this.headingDegrees,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrackPoint(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('sequence: $sequence, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitudeMeters: $altitudeMeters, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('accuracyMeters: $accuracyMeters, ')
          ..write('speedMetersPerSecond: $speedMetersPerSecond, ')
          ..write('headingDegrees: $headingDegrees')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    trackId,
    sequence,
    latitude,
    longitude,
    altitudeMeters,
    timestampMs,
    accuracyMeters,
    speedMetersPerSecond,
    headingDegrees,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackPoint &&
          other.id == this.id &&
          other.trackId == this.trackId &&
          other.sequence == this.sequence &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitudeMeters == this.altitudeMeters &&
          other.timestampMs == this.timestampMs &&
          other.accuracyMeters == this.accuracyMeters &&
          other.speedMetersPerSecond == this.speedMetersPerSecond &&
          other.headingDegrees == this.headingDegrees);
}

class TrackPointsCompanion extends UpdateCompanion<TrackPoint> {
  final Value<int> id;
  final Value<int> trackId;
  final Value<int> sequence;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<double?> altitudeMeters;
  final Value<int> timestampMs;
  final Value<double?> accuracyMeters;
  final Value<double?> speedMetersPerSecond;
  final Value<double?> headingDegrees;
  const TrackPointsCompanion({
    this.id = const Value.absent(),
    this.trackId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitudeMeters = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.accuracyMeters = const Value.absent(),
    this.speedMetersPerSecond = const Value.absent(),
    this.headingDegrees = const Value.absent(),
  });
  TrackPointsCompanion.insert({
    this.id = const Value.absent(),
    required int trackId,
    required int sequence,
    required double latitude,
    required double longitude,
    this.altitudeMeters = const Value.absent(),
    required int timestampMs,
    this.accuracyMeters = const Value.absent(),
    this.speedMetersPerSecond = const Value.absent(),
    this.headingDegrees = const Value.absent(),
  }) : trackId = Value(trackId),
       sequence = Value(sequence),
       latitude = Value(latitude),
       longitude = Value(longitude),
       timestampMs = Value(timestampMs);
  static Insertable<TrackPoint> custom({
    Expression<int>? id,
    Expression<int>? trackId,
    Expression<int>? sequence,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? altitudeMeters,
    Expression<int>? timestampMs,
    Expression<double>? accuracyMeters,
    Expression<double>? speedMetersPerSecond,
    Expression<double>? headingDegrees,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (trackId != null) 'track_id': trackId,
      if (sequence != null) 'sequence': sequence,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitudeMeters != null) 'altitude_meters': altitudeMeters,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      if (speedMetersPerSecond != null)
        'speed_meters_per_second': speedMetersPerSecond,
      if (headingDegrees != null) 'heading_degrees': headingDegrees,
    });
  }

  TrackPointsCompanion copyWith({
    Value<int>? id,
    Value<int>? trackId,
    Value<int>? sequence,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<double?>? altitudeMeters,
    Value<int>? timestampMs,
    Value<double?>? accuracyMeters,
    Value<double?>? speedMetersPerSecond,
    Value<double?>? headingDegrees,
  }) {
    return TrackPointsCompanion(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      sequence: sequence ?? this.sequence,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      timestampMs: timestampMs ?? this.timestampMs,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      speedMetersPerSecond: speedMetersPerSecond ?? this.speedMetersPerSecond,
      headingDegrees: headingDegrees ?? this.headingDegrees,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<int>(trackId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitudeMeters.present) {
      map['altitude_meters'] = Variable<double>(altitudeMeters.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (accuracyMeters.present) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters.value);
    }
    if (speedMetersPerSecond.present) {
      map['speed_meters_per_second'] = Variable<double>(
        speedMetersPerSecond.value,
      );
    }
    if (headingDegrees.present) {
      map['heading_degrees'] = Variable<double>(headingDegrees.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrackPointsCompanion(')
          ..write('id: $id, ')
          ..write('trackId: $trackId, ')
          ..write('sequence: $sequence, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitudeMeters: $altitudeMeters, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('accuracyMeters: $accuracyMeters, ')
          ..write('speedMetersPerSecond: $speedMetersPerSecond, ')
          ..write('headingDegrees: $headingDegrees')
          ..write(')'))
        .toString();
  }
}

class $CachedMapCellsTable extends CachedMapCells
    with TableInfo<$CachedMapCellsTable, CachedMapCell> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMapCellsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cellKeyMeta = const VerificationMeta(
    'cellKey',
  );
  @override
  late final GeneratedColumn<String> cellKey = GeneratedColumn<String>(
    'cell_key',
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
  static const VerificationMeta _featuresJsonMeta = const VerificationMeta(
    'featuresJson',
  );
  @override
  late final GeneratedColumn<String> featuresJson = GeneratedColumn<String>(
    'features_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [cellKey, fetchedAt, featuresJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_map_cells';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMapCell> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cell_key')) {
      context.handle(
        _cellKeyMeta,
        cellKey.isAcceptableOrUnknown(data['cell_key']!, _cellKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cellKeyMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('features_json')) {
      context.handle(
        _featuresJsonMeta,
        featuresJson.isAcceptableOrUnknown(
          data['features_json']!,
          _featuresJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_featuresJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cellKey};
  @override
  CachedMapCell map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMapCell(
      cellKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cell_key'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
      featuresJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}features_json'],
      )!,
    );
  }

  @override
  $CachedMapCellsTable createAlias(String alias) {
    return $CachedMapCellsTable(attachedDatabase, alias);
  }
}

class CachedMapCell extends DataClass implements Insertable<CachedMapCell> {
  final String cellKey;
  final DateTime fetchedAt;
  final String featuresJson;
  const CachedMapCell({
    required this.cellKey,
    required this.fetchedAt,
    required this.featuresJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cell_key'] = Variable<String>(cellKey);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    map['features_json'] = Variable<String>(featuresJson);
    return map;
  }

  CachedMapCellsCompanion toCompanion(bool nullToAbsent) {
    return CachedMapCellsCompanion(
      cellKey: Value(cellKey),
      fetchedAt: Value(fetchedAt),
      featuresJson: Value(featuresJson),
    );
  }

  factory CachedMapCell.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMapCell(
      cellKey: serializer.fromJson<String>(json['cellKey']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
      featuresJson: serializer.fromJson<String>(json['featuresJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cellKey': serializer.toJson<String>(cellKey),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
      'featuresJson': serializer.toJson<String>(featuresJson),
    };
  }

  CachedMapCell copyWith({
    String? cellKey,
    DateTime? fetchedAt,
    String? featuresJson,
  }) => CachedMapCell(
    cellKey: cellKey ?? this.cellKey,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    featuresJson: featuresJson ?? this.featuresJson,
  );
  CachedMapCell copyWithCompanion(CachedMapCellsCompanion data) {
    return CachedMapCell(
      cellKey: data.cellKey.present ? data.cellKey.value : this.cellKey,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      featuresJson: data.featuresJson.present
          ? data.featuresJson.value
          : this.featuresJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMapCell(')
          ..write('cellKey: $cellKey, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('featuresJson: $featuresJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cellKey, fetchedAt, featuresJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMapCell &&
          other.cellKey == this.cellKey &&
          other.fetchedAt == this.fetchedAt &&
          other.featuresJson == this.featuresJson);
}

class CachedMapCellsCompanion extends UpdateCompanion<CachedMapCell> {
  final Value<String> cellKey;
  final Value<DateTime> fetchedAt;
  final Value<String> featuresJson;
  final Value<int> rowid;
  const CachedMapCellsCompanion({
    this.cellKey = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.featuresJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMapCellsCompanion.insert({
    required String cellKey,
    required DateTime fetchedAt,
    required String featuresJson,
    this.rowid = const Value.absent(),
  }) : cellKey = Value(cellKey),
       fetchedAt = Value(fetchedAt),
       featuresJson = Value(featuresJson);
  static Insertable<CachedMapCell> custom({
    Expression<String>? cellKey,
    Expression<DateTime>? fetchedAt,
    Expression<String>? featuresJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cellKey != null) 'cell_key': cellKey,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (featuresJson != null) 'features_json': featuresJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMapCellsCompanion copyWith({
    Value<String>? cellKey,
    Value<DateTime>? fetchedAt,
    Value<String>? featuresJson,
    Value<int>? rowid,
  }) {
    return CachedMapCellsCompanion(
      cellKey: cellKey ?? this.cellKey,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      featuresJson: featuresJson ?? this.featuresJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cellKey.present) {
      map['cell_key'] = Variable<String>(cellKey.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (featuresJson.present) {
      map['features_json'] = Variable<String>(featuresJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMapCellsCompanion(')
          ..write('cellKey: $cellKey, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('featuresJson: $featuresJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineAreasTable extends OfflineAreas
    with TableInfo<$OfflineAreasTable, OfflineArea> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineAreasTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _southWestLatMeta = const VerificationMeta(
    'southWestLat',
  );
  @override
  late final GeneratedColumn<double> southWestLat = GeneratedColumn<double>(
    'south_west_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _southWestLngMeta = const VerificationMeta(
    'southWestLng',
  );
  @override
  late final GeneratedColumn<double> southWestLng = GeneratedColumn<double>(
    'south_west_lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _northEastLatMeta = const VerificationMeta(
    'northEastLat',
  );
  @override
  late final GeneratedColumn<double> northEastLat = GeneratedColumn<double>(
    'north_east_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _northEastLngMeta = const VerificationMeta(
    'northEastLng',
  );
  @override
  late final GeneratedColumn<double> northEastLng = GeneratedColumn<double>(
    'north_east_lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
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
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _requestedAtMeta = const VerificationMeta(
    'requestedAt',
  );
  @override
  late final GeneratedColumn<DateTime> requestedAt = GeneratedColumn<DateTime>(
    'requested_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    southWestLat,
    southWestLng,
    northEastLat,
    northEastLng,
    status,
    progress,
    requestedAt,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_areas';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineArea> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('south_west_lat')) {
      context.handle(
        _southWestLatMeta,
        southWestLat.isAcceptableOrUnknown(
          data['south_west_lat']!,
          _southWestLatMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_southWestLatMeta);
    }
    if (data.containsKey('south_west_lng')) {
      context.handle(
        _southWestLngMeta,
        southWestLng.isAcceptableOrUnknown(
          data['south_west_lng']!,
          _southWestLngMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_southWestLngMeta);
    }
    if (data.containsKey('north_east_lat')) {
      context.handle(
        _northEastLatMeta,
        northEastLat.isAcceptableOrUnknown(
          data['north_east_lat']!,
          _northEastLatMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_northEastLatMeta);
    }
    if (data.containsKey('north_east_lng')) {
      context.handle(
        _northEastLngMeta,
        northEastLng.isAcceptableOrUnknown(
          data['north_east_lng']!,
          _northEastLngMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_northEastLngMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
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
    } else if (isInserting) {
      context.missing(_requestedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineArea map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineArea(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      southWestLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}south_west_lat'],
      )!,
      southWestLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}south_west_lng'],
      )!,
      northEastLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}north_east_lat'],
      )!,
      northEastLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}north_east_lng'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      requestedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}requested_at'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $OfflineAreasTable createAlias(String alias) {
    return $OfflineAreasTable(attachedDatabase, alias);
  }
}

class OfflineArea extends DataClass implements Insertable<OfflineArea> {
  final int id;
  final String name;
  final double southWestLat;
  final double southWestLng;
  final double northEastLat;
  final double northEastLng;
  final String status;
  final double progress;
  final DateTime requestedAt;
  final DateTime? completedAt;
  const OfflineArea({
    required this.id,
    required this.name,
    required this.southWestLat,
    required this.southWestLng,
    required this.northEastLat,
    required this.northEastLng,
    required this.status,
    required this.progress,
    required this.requestedAt,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['south_west_lat'] = Variable<double>(southWestLat);
    map['south_west_lng'] = Variable<double>(southWestLng);
    map['north_east_lat'] = Variable<double>(northEastLat);
    map['north_east_lng'] = Variable<double>(northEastLng);
    map['status'] = Variable<String>(status);
    map['progress'] = Variable<double>(progress);
    map['requested_at'] = Variable<DateTime>(requestedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  OfflineAreasCompanion toCompanion(bool nullToAbsent) {
    return OfflineAreasCompanion(
      id: Value(id),
      name: Value(name),
      southWestLat: Value(southWestLat),
      southWestLng: Value(southWestLng),
      northEastLat: Value(northEastLat),
      northEastLng: Value(northEastLng),
      status: Value(status),
      progress: Value(progress),
      requestedAt: Value(requestedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory OfflineArea.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineArea(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      southWestLat: serializer.fromJson<double>(json['southWestLat']),
      southWestLng: serializer.fromJson<double>(json['southWestLng']),
      northEastLat: serializer.fromJson<double>(json['northEastLat']),
      northEastLng: serializer.fromJson<double>(json['northEastLng']),
      status: serializer.fromJson<String>(json['status']),
      progress: serializer.fromJson<double>(json['progress']),
      requestedAt: serializer.fromJson<DateTime>(json['requestedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'southWestLat': serializer.toJson<double>(southWestLat),
      'southWestLng': serializer.toJson<double>(southWestLng),
      'northEastLat': serializer.toJson<double>(northEastLat),
      'northEastLng': serializer.toJson<double>(northEastLng),
      'status': serializer.toJson<String>(status),
      'progress': serializer.toJson<double>(progress),
      'requestedAt': serializer.toJson<DateTime>(requestedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  OfflineArea copyWith({
    int? id,
    String? name,
    double? southWestLat,
    double? southWestLng,
    double? northEastLat,
    double? northEastLng,
    String? status,
    double? progress,
    DateTime? requestedAt,
    Value<DateTime?> completedAt = const Value.absent(),
  }) => OfflineArea(
    id: id ?? this.id,
    name: name ?? this.name,
    southWestLat: southWestLat ?? this.southWestLat,
    southWestLng: southWestLng ?? this.southWestLng,
    northEastLat: northEastLat ?? this.northEastLat,
    northEastLng: northEastLng ?? this.northEastLng,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    requestedAt: requestedAt ?? this.requestedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  OfflineArea copyWithCompanion(OfflineAreasCompanion data) {
    return OfflineArea(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      southWestLat: data.southWestLat.present
          ? data.southWestLat.value
          : this.southWestLat,
      southWestLng: data.southWestLng.present
          ? data.southWestLng.value
          : this.southWestLng,
      northEastLat: data.northEastLat.present
          ? data.northEastLat.value
          : this.northEastLat,
      northEastLng: data.northEastLng.present
          ? data.northEastLng.value
          : this.northEastLng,
      status: data.status.present ? data.status.value : this.status,
      progress: data.progress.present ? data.progress.value : this.progress,
      requestedAt: data.requestedAt.present
          ? data.requestedAt.value
          : this.requestedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineArea(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('southWestLat: $southWestLat, ')
          ..write('southWestLng: $southWestLng, ')
          ..write('northEastLat: $northEastLat, ')
          ..write('northEastLng: $northEastLng, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    southWestLat,
    southWestLng,
    northEastLat,
    northEastLng,
    status,
    progress,
    requestedAt,
    completedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineArea &&
          other.id == this.id &&
          other.name == this.name &&
          other.southWestLat == this.southWestLat &&
          other.southWestLng == this.southWestLng &&
          other.northEastLat == this.northEastLat &&
          other.northEastLng == this.northEastLng &&
          other.status == this.status &&
          other.progress == this.progress &&
          other.requestedAt == this.requestedAt &&
          other.completedAt == this.completedAt);
}

class OfflineAreasCompanion extends UpdateCompanion<OfflineArea> {
  final Value<int> id;
  final Value<String> name;
  final Value<double> southWestLat;
  final Value<double> southWestLng;
  final Value<double> northEastLat;
  final Value<double> northEastLng;
  final Value<String> status;
  final Value<double> progress;
  final Value<DateTime> requestedAt;
  final Value<DateTime?> completedAt;
  const OfflineAreasCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.southWestLat = const Value.absent(),
    this.southWestLng = const Value.absent(),
    this.northEastLat = const Value.absent(),
    this.northEastLng = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.requestedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
  });
  OfflineAreasCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required double southWestLat,
    required double southWestLng,
    required double northEastLat,
    required double northEastLng,
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    required DateTime requestedAt,
    this.completedAt = const Value.absent(),
  }) : name = Value(name),
       southWestLat = Value(southWestLat),
       southWestLng = Value(southWestLng),
       northEastLat = Value(northEastLat),
       northEastLng = Value(northEastLng),
       requestedAt = Value(requestedAt);
  static Insertable<OfflineArea> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<double>? southWestLat,
    Expression<double>? southWestLng,
    Expression<double>? northEastLat,
    Expression<double>? northEastLng,
    Expression<String>? status,
    Expression<double>? progress,
    Expression<DateTime>? requestedAt,
    Expression<DateTime>? completedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (southWestLat != null) 'south_west_lat': southWestLat,
      if (southWestLng != null) 'south_west_lng': southWestLng,
      if (northEastLat != null) 'north_east_lat': northEastLat,
      if (northEastLng != null) 'north_east_lng': northEastLng,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (requestedAt != null) 'requested_at': requestedAt,
      if (completedAt != null) 'completed_at': completedAt,
    });
  }

  OfflineAreasCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<double>? southWestLat,
    Value<double>? southWestLng,
    Value<double>? northEastLat,
    Value<double>? northEastLng,
    Value<String>? status,
    Value<double>? progress,
    Value<DateTime>? requestedAt,
    Value<DateTime?>? completedAt,
  }) {
    return OfflineAreasCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      southWestLat: southWestLat ?? this.southWestLat,
      southWestLng: southWestLng ?? this.southWestLng,
      northEastLat: northEastLat ?? this.northEastLat,
      northEastLng: northEastLng ?? this.northEastLng,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      requestedAt: requestedAt ?? this.requestedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (southWestLat.present) {
      map['south_west_lat'] = Variable<double>(southWestLat.value);
    }
    if (southWestLng.present) {
      map['south_west_lng'] = Variable<double>(southWestLng.value);
    }
    if (northEastLat.present) {
      map['north_east_lat'] = Variable<double>(northEastLat.value);
    }
    if (northEastLng.present) {
      map['north_east_lng'] = Variable<double>(northEastLng.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (requestedAt.present) {
      map['requested_at'] = Variable<DateTime>(requestedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineAreasCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('southWestLat: $southWestLat, ')
          ..write('southWestLng: $southWestLng, ')
          ..write('northEastLat: $northEastLat, ')
          ..write('northEastLng: $northEastLng, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('requestedAt: $requestedAt, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$WildBitDatabase extends GeneratedDatabase {
  _$WildBitDatabase(QueryExecutor e) : super(e);
  $WildBitDatabaseManager get managers => $WildBitDatabaseManager(this);
  late final $TracksTable tracks = $TracksTable(this);
  late final $TrackPointsTable trackPoints = $TrackPointsTable(this);
  late final $CachedMapCellsTable cachedMapCells = $CachedMapCellsTable(this);
  late final $OfflineAreasTable offlineAreas = $OfflineAreasTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tracks,
    trackPoints,
    cachedMapCells,
    offlineAreas,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'tracks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('track_points', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$TracksTableCreateCompanionBuilder =
    TracksCompanion Function({
      Value<int> id,
      required String name,
      required DateTime createdAt,
      Value<double> distanceMeters,
      Value<int> durationSeconds,
      Value<double> elevationGainMeters,
      required String source,
    });
typedef $$TracksTableUpdateCompanionBuilder =
    TracksCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<double> distanceMeters,
      Value<int> durationSeconds,
      Value<double> elevationGainMeters,
      Value<String> source,
    });

final class $$TracksTableReferences
    extends BaseReferences<_$WildBitDatabase, $TracksTable, Track> {
  $$TracksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TrackPointsTable, List<TrackPoint>>
  _trackPointsRefsTable(_$WildBitDatabase db) => MultiTypedResultKey.fromTable(
    db.trackPoints,
    aliasName: 'tracks__id__track_points__track_id',
  );

  $$TrackPointsTableProcessedTableManager get trackPointsRefs {
    final manager = $$TrackPointsTableTableManager(
      $_db,
      $_db.trackPoints,
    ).filter((f) => f.trackId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_trackPointsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TracksTableFilterComposer
    extends Composer<_$WildBitDatabase, $TracksTable> {
  $$TracksTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get elevationGainMeters => $composableBuilder(
    column: $table.elevationGainMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> trackPointsRefs(
    Expression<bool> Function($$TrackPointsTableFilterComposer f) f,
  ) {
    final $$TrackPointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackPoints,
      getReferencedColumn: (t) => t.trackId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackPointsTableFilterComposer(
            $db: $db,
            $table: $db.trackPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TracksTableOrderingComposer
    extends Composer<_$WildBitDatabase, $TracksTable> {
  $$TracksTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get elevationGainMeters => $composableBuilder(
    column: $table.elevationGainMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TracksTableAnnotationComposer
    extends Composer<_$WildBitDatabase, $TracksTable> {
  $$TracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<double> get distanceMeters => $composableBuilder(
    column: $table.distanceMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<double> get elevationGainMeters => $composableBuilder(
    column: $table.elevationGainMeters,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  Expression<T> trackPointsRefs<T extends Object>(
    Expression<T> Function($$TrackPointsTableAnnotationComposer a) f,
  ) {
    final $$TrackPointsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.trackPoints,
      getReferencedColumn: (t) => t.trackId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TrackPointsTableAnnotationComposer(
            $db: $db,
            $table: $db.trackPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TracksTableTableManager
    extends
        RootTableManager<
          _$WildBitDatabase,
          $TracksTable,
          Track,
          $$TracksTableFilterComposer,
          $$TracksTableOrderingComposer,
          $$TracksTableAnnotationComposer,
          $$TracksTableCreateCompanionBuilder,
          $$TracksTableUpdateCompanionBuilder,
          (Track, $$TracksTableReferences),
          Track,
          PrefetchHooks Function({bool trackPointsRefs})
        > {
  $$TracksTableTableManager(_$WildBitDatabase db, $TracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<double> distanceMeters = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<double> elevationGainMeters = const Value.absent(),
                Value<String> source = const Value.absent(),
              }) => TracksCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                elevationGainMeters: elevationGainMeters,
                source: source,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required DateTime createdAt,
                Value<double> distanceMeters = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<double> elevationGainMeters = const Value.absent(),
                required String source,
              }) => TracksCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                elevationGainMeters: elevationGainMeters,
                source: source,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TracksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({trackPointsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (trackPointsRefs) db.trackPoints],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (trackPointsRefs)
                    await $_getPrefetchedData<Track, $TracksTable, TrackPoint>(
                      currentTable: table,
                      referencedTable: $$TracksTableReferences
                          ._trackPointsRefsTable(db),
                      managerFromTypedResult: (p0) => $$TracksTableReferences(
                        db,
                        table,
                        p0,
                      ).trackPointsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.trackId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TracksTableProcessedTableManager =
    ProcessedTableManager<
      _$WildBitDatabase,
      $TracksTable,
      Track,
      $$TracksTableFilterComposer,
      $$TracksTableOrderingComposer,
      $$TracksTableAnnotationComposer,
      $$TracksTableCreateCompanionBuilder,
      $$TracksTableUpdateCompanionBuilder,
      (Track, $$TracksTableReferences),
      Track,
      PrefetchHooks Function({bool trackPointsRefs})
    >;
typedef $$TrackPointsTableCreateCompanionBuilder =
    TrackPointsCompanion Function({
      Value<int> id,
      required int trackId,
      required int sequence,
      required double latitude,
      required double longitude,
      Value<double?> altitudeMeters,
      required int timestampMs,
      Value<double?> accuracyMeters,
      Value<double?> speedMetersPerSecond,
      Value<double?> headingDegrees,
    });
typedef $$TrackPointsTableUpdateCompanionBuilder =
    TrackPointsCompanion Function({
      Value<int> id,
      Value<int> trackId,
      Value<int> sequence,
      Value<double> latitude,
      Value<double> longitude,
      Value<double?> altitudeMeters,
      Value<int> timestampMs,
      Value<double?> accuracyMeters,
      Value<double?> speedMetersPerSecond,
      Value<double?> headingDegrees,
    });

final class $$TrackPointsTableReferences
    extends BaseReferences<_$WildBitDatabase, $TrackPointsTable, TrackPoint> {
  $$TrackPointsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TracksTable _trackIdTable(_$WildBitDatabase db) =>
      db.tracks.createAlias('track_points__track_id__tracks__id');

  $$TracksTableProcessedTableManager get trackId {
    final $_column = $_itemColumn<int>('track_id')!;

    final manager = $$TracksTableTableManager(
      $_db,
      $_db.tracks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_trackIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TrackPointsTableFilterComposer
    extends Composer<_$WildBitDatabase, $TrackPointsTable> {
  $$TrackPointsTableFilterComposer({
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

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
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

  ColumnFilters<double> get altitudeMeters => $composableBuilder(
    column: $table.altitudeMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMetersPerSecond => $composableBuilder(
    column: $table.speedMetersPerSecond,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get headingDegrees => $composableBuilder(
    column: $table.headingDegrees,
    builder: (column) => ColumnFilters(column),
  );

  $$TracksTableFilterComposer get trackId {
    final $$TracksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackId,
      referencedTable: $db.tracks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableFilterComposer(
            $db: $db,
            $table: $db.tracks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableOrderingComposer
    extends Composer<_$WildBitDatabase, $TrackPointsTable> {
  $$TrackPointsTableOrderingComposer({
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

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
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

  ColumnOrderings<double> get altitudeMeters => $composableBuilder(
    column: $table.altitudeMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMetersPerSecond => $composableBuilder(
    column: $table.speedMetersPerSecond,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get headingDegrees => $composableBuilder(
    column: $table.headingDegrees,
    builder: (column) => ColumnOrderings(column),
  );

  $$TracksTableOrderingComposer get trackId {
    final $$TracksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackId,
      referencedTable: $db.tracks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableOrderingComposer(
            $db: $db,
            $table: $db.tracks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableAnnotationComposer
    extends Composer<_$WildBitDatabase, $TrackPointsTable> {
  $$TrackPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get altitudeMeters => $composableBuilder(
    column: $table.altitudeMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => column,
  );

  GeneratedColumn<double> get speedMetersPerSecond => $composableBuilder(
    column: $table.speedMetersPerSecond,
    builder: (column) => column,
  );

  GeneratedColumn<double> get headingDegrees => $composableBuilder(
    column: $table.headingDegrees,
    builder: (column) => column,
  );

  $$TracksTableAnnotationComposer get trackId {
    final $$TracksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.trackId,
      referencedTable: $db.tracks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TracksTableAnnotationComposer(
            $db: $db,
            $table: $db.tracks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TrackPointsTableTableManager
    extends
        RootTableManager<
          _$WildBitDatabase,
          $TrackPointsTable,
          TrackPoint,
          $$TrackPointsTableFilterComposer,
          $$TrackPointsTableOrderingComposer,
          $$TrackPointsTableAnnotationComposer,
          $$TrackPointsTableCreateCompanionBuilder,
          $$TrackPointsTableUpdateCompanionBuilder,
          (TrackPoint, $$TrackPointsTableReferences),
          TrackPoint,
          PrefetchHooks Function({bool trackId})
        > {
  $$TrackPointsTableTableManager(_$WildBitDatabase db, $TrackPointsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TrackPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TrackPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TrackPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> trackId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<double?> altitudeMeters = const Value.absent(),
                Value<int> timestampMs = const Value.absent(),
                Value<double?> accuracyMeters = const Value.absent(),
                Value<double?> speedMetersPerSecond = const Value.absent(),
                Value<double?> headingDegrees = const Value.absent(),
              }) => TrackPointsCompanion(
                id: id,
                trackId: trackId,
                sequence: sequence,
                latitude: latitude,
                longitude: longitude,
                altitudeMeters: altitudeMeters,
                timestampMs: timestampMs,
                accuracyMeters: accuracyMeters,
                speedMetersPerSecond: speedMetersPerSecond,
                headingDegrees: headingDegrees,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int trackId,
                required int sequence,
                required double latitude,
                required double longitude,
                Value<double?> altitudeMeters = const Value.absent(),
                required int timestampMs,
                Value<double?> accuracyMeters = const Value.absent(),
                Value<double?> speedMetersPerSecond = const Value.absent(),
                Value<double?> headingDegrees = const Value.absent(),
              }) => TrackPointsCompanion.insert(
                id: id,
                trackId: trackId,
                sequence: sequence,
                latitude: latitude,
                longitude: longitude,
                altitudeMeters: altitudeMeters,
                timestampMs: timestampMs,
                accuracyMeters: accuracyMeters,
                speedMetersPerSecond: speedMetersPerSecond,
                headingDegrees: headingDegrees,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TrackPointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({trackId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (trackId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.trackId,
                                referencedTable: $$TrackPointsTableReferences
                                    ._trackIdTable(db),
                                referencedColumn: $$TrackPointsTableReferences
                                    ._trackIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TrackPointsTableProcessedTableManager =
    ProcessedTableManager<
      _$WildBitDatabase,
      $TrackPointsTable,
      TrackPoint,
      $$TrackPointsTableFilterComposer,
      $$TrackPointsTableOrderingComposer,
      $$TrackPointsTableAnnotationComposer,
      $$TrackPointsTableCreateCompanionBuilder,
      $$TrackPointsTableUpdateCompanionBuilder,
      (TrackPoint, $$TrackPointsTableReferences),
      TrackPoint,
      PrefetchHooks Function({bool trackId})
    >;
typedef $$CachedMapCellsTableCreateCompanionBuilder =
    CachedMapCellsCompanion Function({
      required String cellKey,
      required DateTime fetchedAt,
      required String featuresJson,
      Value<int> rowid,
    });
typedef $$CachedMapCellsTableUpdateCompanionBuilder =
    CachedMapCellsCompanion Function({
      Value<String> cellKey,
      Value<DateTime> fetchedAt,
      Value<String> featuresJson,
      Value<int> rowid,
    });

class $$CachedMapCellsTableFilterComposer
    extends Composer<_$WildBitDatabase, $CachedMapCellsTable> {
  $$CachedMapCellsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cellKey => $composableBuilder(
    column: $table.cellKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get featuresJson => $composableBuilder(
    column: $table.featuresJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMapCellsTableOrderingComposer
    extends Composer<_$WildBitDatabase, $CachedMapCellsTable> {
  $$CachedMapCellsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cellKey => $composableBuilder(
    column: $table.cellKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get featuresJson => $composableBuilder(
    column: $table.featuresJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMapCellsTableAnnotationComposer
    extends Composer<_$WildBitDatabase, $CachedMapCellsTable> {
  $$CachedMapCellsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cellKey =>
      $composableBuilder(column: $table.cellKey, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<String> get featuresJson => $composableBuilder(
    column: $table.featuresJson,
    builder: (column) => column,
  );
}

class $$CachedMapCellsTableTableManager
    extends
        RootTableManager<
          _$WildBitDatabase,
          $CachedMapCellsTable,
          CachedMapCell,
          $$CachedMapCellsTableFilterComposer,
          $$CachedMapCellsTableOrderingComposer,
          $$CachedMapCellsTableAnnotationComposer,
          $$CachedMapCellsTableCreateCompanionBuilder,
          $$CachedMapCellsTableUpdateCompanionBuilder,
          (
            CachedMapCell,
            BaseReferences<
              _$WildBitDatabase,
              $CachedMapCellsTable,
              CachedMapCell
            >,
          ),
          CachedMapCell,
          PrefetchHooks Function()
        > {
  $$CachedMapCellsTableTableManager(
    _$WildBitDatabase db,
    $CachedMapCellsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMapCellsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMapCellsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMapCellsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cellKey = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<String> featuresJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMapCellsCompanion(
                cellKey: cellKey,
                fetchedAt: fetchedAt,
                featuresJson: featuresJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cellKey,
                required DateTime fetchedAt,
                required String featuresJson,
                Value<int> rowid = const Value.absent(),
              }) => CachedMapCellsCompanion.insert(
                cellKey: cellKey,
                fetchedAt: fetchedAt,
                featuresJson: featuresJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMapCellsTableProcessedTableManager =
    ProcessedTableManager<
      _$WildBitDatabase,
      $CachedMapCellsTable,
      CachedMapCell,
      $$CachedMapCellsTableFilterComposer,
      $$CachedMapCellsTableOrderingComposer,
      $$CachedMapCellsTableAnnotationComposer,
      $$CachedMapCellsTableCreateCompanionBuilder,
      $$CachedMapCellsTableUpdateCompanionBuilder,
      (
        CachedMapCell,
        BaseReferences<_$WildBitDatabase, $CachedMapCellsTable, CachedMapCell>,
      ),
      CachedMapCell,
      PrefetchHooks Function()
    >;
typedef $$OfflineAreasTableCreateCompanionBuilder =
    OfflineAreasCompanion Function({
      Value<int> id,
      required String name,
      required double southWestLat,
      required double southWestLng,
      required double northEastLat,
      required double northEastLng,
      Value<String> status,
      Value<double> progress,
      required DateTime requestedAt,
      Value<DateTime?> completedAt,
    });
typedef $$OfflineAreasTableUpdateCompanionBuilder =
    OfflineAreasCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<double> southWestLat,
      Value<double> southWestLng,
      Value<double> northEastLat,
      Value<double> northEastLng,
      Value<String> status,
      Value<double> progress,
      Value<DateTime> requestedAt,
      Value<DateTime?> completedAt,
    });

class $$OfflineAreasTableFilterComposer
    extends Composer<_$WildBitDatabase, $OfflineAreasTable> {
  $$OfflineAreasTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get southWestLat => $composableBuilder(
    column: $table.southWestLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get southWestLng => $composableBuilder(
    column: $table.southWestLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get northEastLat => $composableBuilder(
    column: $table.northEastLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get northEastLng => $composableBuilder(
    column: $table.northEastLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineAreasTableOrderingComposer
    extends Composer<_$WildBitDatabase, $OfflineAreasTable> {
  $$OfflineAreasTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get southWestLat => $composableBuilder(
    column: $table.southWestLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get southWestLng => $composableBuilder(
    column: $table.southWestLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get northEastLat => $composableBuilder(
    column: $table.northEastLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get northEastLng => $composableBuilder(
    column: $table.northEastLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineAreasTableAnnotationComposer
    extends Composer<_$WildBitDatabase, $OfflineAreasTable> {
  $$OfflineAreasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get southWestLat => $composableBuilder(
    column: $table.southWestLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get southWestLng => $composableBuilder(
    column: $table.southWestLng,
    builder: (column) => column,
  );

  GeneratedColumn<double> get northEastLat => $composableBuilder(
    column: $table.northEastLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get northEastLng => $composableBuilder(
    column: $table.northEastLng,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<DateTime> get requestedAt => $composableBuilder(
    column: $table.requestedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );
}

class $$OfflineAreasTableTableManager
    extends
        RootTableManager<
          _$WildBitDatabase,
          $OfflineAreasTable,
          OfflineArea,
          $$OfflineAreasTableFilterComposer,
          $$OfflineAreasTableOrderingComposer,
          $$OfflineAreasTableAnnotationComposer,
          $$OfflineAreasTableCreateCompanionBuilder,
          $$OfflineAreasTableUpdateCompanionBuilder,
          (
            OfflineArea,
            BaseReferences<_$WildBitDatabase, $OfflineAreasTable, OfflineArea>,
          ),
          OfflineArea,
          PrefetchHooks Function()
        > {
  $$OfflineAreasTableTableManager(
    _$WildBitDatabase db,
    $OfflineAreasTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineAreasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineAreasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineAreasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> southWestLat = const Value.absent(),
                Value<double> southWestLng = const Value.absent(),
                Value<double> northEastLat = const Value.absent(),
                Value<double> northEastLng = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<DateTime> requestedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
              }) => OfflineAreasCompanion(
                id: id,
                name: name,
                southWestLat: southWestLat,
                southWestLng: southWestLng,
                northEastLat: northEastLat,
                northEastLng: northEastLng,
                status: status,
                progress: progress,
                requestedAt: requestedAt,
                completedAt: completedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required double southWestLat,
                required double southWestLng,
                required double northEastLat,
                required double northEastLng,
                Value<String> status = const Value.absent(),
                Value<double> progress = const Value.absent(),
                required DateTime requestedAt,
                Value<DateTime?> completedAt = const Value.absent(),
              }) => OfflineAreasCompanion.insert(
                id: id,
                name: name,
                southWestLat: southWestLat,
                southWestLng: southWestLng,
                northEastLat: northEastLat,
                northEastLng: northEastLng,
                status: status,
                progress: progress,
                requestedAt: requestedAt,
                completedAt: completedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineAreasTableProcessedTableManager =
    ProcessedTableManager<
      _$WildBitDatabase,
      $OfflineAreasTable,
      OfflineArea,
      $$OfflineAreasTableFilterComposer,
      $$OfflineAreasTableOrderingComposer,
      $$OfflineAreasTableAnnotationComposer,
      $$OfflineAreasTableCreateCompanionBuilder,
      $$OfflineAreasTableUpdateCompanionBuilder,
      (
        OfflineArea,
        BaseReferences<_$WildBitDatabase, $OfflineAreasTable, OfflineArea>,
      ),
      OfflineArea,
      PrefetchHooks Function()
    >;

class $WildBitDatabaseManager {
  final _$WildBitDatabase _db;
  $WildBitDatabaseManager(this._db);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db, _db.tracks);
  $$TrackPointsTableTableManager get trackPoints =>
      $$TrackPointsTableTableManager(_db, _db.trackPoints);
  $$CachedMapCellsTableTableManager get cachedMapCells =>
      $$CachedMapCellsTableTableManager(_db, _db.cachedMapCells);
  $$OfflineAreasTableTableManager get offlineAreas =>
      $$OfflineAreasTableTableManager(_db, _db.offlineAreas);
}
