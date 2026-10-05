int asInt(dynamic value) => value is int ? value : int.parse(value.toString());

double asDouble(dynamic value) => value is double ? value : double.parse(value.toString());

int? asNullableInt(dynamic value) => value == null ? null : asInt(value);

String? asNullableString(dynamic value) => value?.toString();
