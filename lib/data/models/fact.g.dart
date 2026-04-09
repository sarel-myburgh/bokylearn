// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fact.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FactAdapter extends TypeAdapter<Fact> {
  @override
  final int typeId = 0;

  @override
  Fact read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Fact(
      id: fields[0] as String,
      text: fields[1] as String,
      tags: (fields[2] as List).cast<String>(),
      credit: fields[3] as String?,
      mature: fields[4] as bool,
      scrapedAt: fields[5] as String?,
      readMoreUrl: fields[6] as String?,
      readMoreSource: fields[7] as String?,
      imageUrl: fields[8] as String?,
      imageSource: fields[9] as String?,
      imageCaption: fields[10] as String?,
      creditUrl: fields[11] as String?,
      creditLogoUrl: fields[12] as String?,
      furtherReadingUrls: (fields[13] as List?)?.cast<String>() ?? [],
      furtherReadingTitles: (fields[14] as List?)?.cast<String>() ?? [],
      source: fields[15] as String?,
      tihMonth: fields[16] as int?,
      tihDay: fields[17] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, Fact obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.text)
      ..writeByte(2)
      ..write(obj.tags)
      ..writeByte(3)
      ..write(obj.credit)
      ..writeByte(4)
      ..write(obj.mature)
      ..writeByte(5)
      ..write(obj.scrapedAt)
      ..writeByte(6)
      ..write(obj.readMoreUrl)
      ..writeByte(7)
      ..write(obj.readMoreSource)
      ..writeByte(8)
      ..write(obj.imageUrl)
      ..writeByte(9)
      ..write(obj.imageSource)
      ..writeByte(10)
      ..write(obj.imageCaption)
      ..writeByte(11)
      ..write(obj.creditUrl)
      ..writeByte(12)
      ..write(obj.creditLogoUrl)
      ..writeByte(13)
      ..write(obj.furtherReadingUrls)
      ..writeByte(14)
      ..write(obj.furtherReadingTitles)
      ..writeByte(15)
      ..write(obj.source)
      ..writeByte(16)
      ..write(obj.tihMonth)
      ..writeByte(17)
      ..write(obj.tihDay);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FactAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
