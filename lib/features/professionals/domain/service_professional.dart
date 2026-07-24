import '../../settings/domain/schedule_models.dart';

class ServiceProfessional {
  const ServiceProfessional({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.category,
    required this.name,
    required this.hourlyRateCents,
    required this.transportCostCents,
    required this.mealCostCents,
    required this.travelCostCents,
    required this.lodgingCostCents,
    required this.otherCostCents,
    required this.weeklyAvailability,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.linkedUserId,
    this.email,
    this.phone,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String kind;
  final String category;
  final String name;
  final int hourlyRateCents;
  final int transportCostCents;
  final int mealCostCents;
  final int travelCostCents;
  final int lodgingCostCents;
  final int otherCostCents;
  final Map<String, DaySchedule> weeklyAvailability;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? linkedUserId;
  final String? email;
  final String? phone;
  final String? notes;

  bool get isInternal => kind == 'internal';

  String get kindLabel => isInternal ? 'Interno' : 'Parceiro';

  ServiceProfessional copyWithAvailability(
    Map<String, DaySchedule> availability,
  ) {
    return ServiceProfessional(
      id: id,
      tenantId: tenantId,
      linkedUserId: linkedUserId,
      kind: kind,
      category: category,
      name: name,
      hourlyRateCents: hourlyRateCents,
      transportCostCents: transportCostCents,
      mealCostCents: mealCostCents,
      travelCostCents: travelCostCents,
      lodgingCostCents: lodgingCostCents,
      otherCostCents: otherCostCents,
      weeklyAvailability: availability,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      email: email,
      phone: phone,
      notes: notes,
    );
  }

  Map<String, dynamic> toInsertPayload() => {
        'tenant_id': tenantId,
        'linked_user_id': linkedUserId,
        'kind': kind,
        'category': category.trim(),
        'name': name.trim(),
        'email': _emptyToNull(email),
        'phone': _emptyToNull(phone),
        'notes': _emptyToNull(notes),
        'hourly_rate_cents': hourlyRateCents,
        'transport_cost_cents': transportCostCents,
        'meal_cost_cents': mealCostCents,
        'travel_cost_cents': travelCostCents,
        'lodging_cost_cents': lodgingCostCents,
        'other_cost_cents': otherCostCents,
        'availability': weeklyScheduleToJson(weeklyAvailability),
        'is_active': isActive,
      };

  Map<String, dynamic> toUpdatePayload() => {
        'linked_user_id': linkedUserId,
        'kind': kind,
        'category': category.trim(),
        'name': name.trim(),
        'email': _emptyToNull(email),
        'phone': _emptyToNull(phone),
        'notes': _emptyToNull(notes),
        'hourly_rate_cents': hourlyRateCents,
        'transport_cost_cents': transportCostCents,
        'meal_cost_cents': mealCostCents,
        'travel_cost_cents': travelCostCents,
        'lodging_cost_cents': lodgingCostCents,
        'other_cost_cents': otherCostCents,
        'availability': weeklyScheduleToJson(weeklyAvailability),
        'is_active': isActive,
      };
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

ServiceProfessional serviceProfessionalFromRow(Map<String, dynamic> row) {
  return ServiceProfessional(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    linkedUserId: row['linked_user_id'] as String?,
    kind: row['kind'] as String? ?? 'partner',
    category: row['category'] as String? ?? 'Geral',
    name: row['name'] as String? ?? 'Profissional',
    hourlyRateCents: (row['hourly_rate_cents'] as num?)?.toInt() ?? 0,
    transportCostCents: (row['transport_cost_cents'] as num?)?.toInt() ?? 0,
    mealCostCents: (row['meal_cost_cents'] as num?)?.toInt() ?? 0,
    travelCostCents: (row['travel_cost_cents'] as num?)?.toInt() ?? 0,
    lodgingCostCents: (row['lodging_cost_cents'] as num?)?.toInt() ?? 0,
    otherCostCents: (row['other_cost_cents'] as num?)?.toInt() ?? 0,
    weeklyAvailability: weeklyScheduleFromJson(row['availability']),
    email: row['email'] as String?,
    phone: row['phone'] as String?,
    notes: row['notes'] as String?,
    isActive: row['is_active'] as bool? ?? true,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}

class TechnicianUserOption {
  const TechnicianUserOption({
    required this.userId,
    required this.name,
    this.email,
    this.phone,
  });

  final String userId;
  final String name;
  final String? email;
  final String? phone;
}

TechnicianUserOption technicianUserOptionFromRow(Map<String, dynamic> row) {
  return TechnicianUserOption(
    userId: row['user_id'] as String,
    name: row['name'] as String? ?? 'Técnico',
    email: row['email'] as String?,
    phone: row['phone'] as String?,
  );
}
