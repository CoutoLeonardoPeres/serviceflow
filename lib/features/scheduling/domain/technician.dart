class Technician {
  const Technician({
    required this.professionalId,
    required this.name,
    required this.category,
    required this.kind,
    this.userId,
    this.email,
    this.phone,
  });

  final String professionalId;
  final String? userId;
  final String name;
  final String category;
  final String kind;
  final String? email;
  final String? phone;
}

Technician technicianFromRow(Map<String, dynamic> row) {
  return Technician(
    professionalId:
        row['professional_id'] as String? ?? row['user_id'] as String? ?? '',
    userId: row['user_id'] as String?,
    name: row['name'] as String? ?? 'Técnico',
    category: row['category'] as String? ?? 'Geral',
    kind: row['kind'] as String? ?? 'internal',
    email: row['email'] as String?,
    phone: row['phone'] as String?,
  );
}
