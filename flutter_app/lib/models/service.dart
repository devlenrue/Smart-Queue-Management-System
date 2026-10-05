import 'model_helpers.dart';

class ServiceModel {
  const ServiceModel({
    required this.id,
    required this.name,
    this.description,
    required this.averageServiceMinutes,
    required this.isActive,
  });

  final int id;
  final String name;
  final String? description;
  final double averageServiceMinutes;
  final bool isActive;

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    return ServiceModel(
      id: asInt(json['id']),
      name: json['name'] as String,
      description: json['description'] as String?,
      averageServiceMinutes: asDouble(json['averageServiceMinutes']),
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}
