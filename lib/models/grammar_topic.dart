import 'package:hive/hive.dart';

/// A saved grammar explanation. [body] is a cleanly formatted Markdown-ish
/// template (## sections + - bullets) produced by the model and editable by
/// the user. Hand-written adapter — no build_runner.
class GrammarTopic extends HiveObject {
  GrammarTopic({
    required this.id,
    required this.title,
    required this.body,
    required this.dateAdded,
  });

  String id;
  String title;
  String body;
  DateTime dateAdded;

  GrammarTopic copyWith({String? title, String? body}) => GrammarTopic(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        dateAdded: dateAdded,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'dateAdded': dateAdded.toIso8601String(),
      };
}

class GrammarTopicAdapter extends TypeAdapter<GrammarTopic> {
  @override
  final int typeId = 3;

  @override
  GrammarTopic read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return GrammarTopic(
      id: fields[0] as String,
      title: fields[1] as String,
      body: fields[2] as String,
      dateAdded: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, GrammarTopic obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(3)
      ..write(obj.dateAdded);
  }
}
