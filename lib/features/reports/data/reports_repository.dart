import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_error.dart';
import '../domain/reports_snapshot.dart';

class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _db {
    final client = _client;
    if (client == null) {
      throw StateError('SupabaseClient nao configurado.');
    }
    return client;
  }

  Future<ReportsSnapshot> loadSnapshot({
    ReportsPeriod period = ReportsPeriod.last30Days,
  }) async {
    try {
      final customers =
          await _selectRows('customers', 'id, name, is_active, created_at');
      final profiles = await _selectRows('profiles', 'id, full_name');
      final categories = await _selectRows('service_categories', 'id, name');
      final requests = await _selectRows(
        'service_requests',
        'id, customer_id, category_id, number, title, status, created_at',
      );
      final appointments = await _selectRows(
        'appointments',
        'id, status, scheduled_start, created_at',
      );
      final quotations = await _selectRows(
        'quotations',
        'status, total_cents, created_at',
      );
      final workOrders = await _selectRows(
        'work_orders',
        'id, customer_id, number, title, status, total_cents, created_at',
      );
      final receivables = await _selectRows(
        'receivables',
        'id, customer_id, description, status, amount_cents, balance_cents, due_date, created_at',
      );
      final appointmentAssignments = await _selectRows(
        'appointment_assignments',
        'appointment_id, technician_user_id, assigned_at, revoked_at',
      );
      final timeEntries = await _selectRows(
        'work_order_time_entries',
        'work_order_id, technician_id, duration_minutes, created_at',
      );
      final satisfactionRows = await _selectRows(
        'work_order_satisfaction',
        'rating, created_at',
      );

      final now = DateTime.now();
      final customersInPeriod = _filterByPeriod(customers, period, now);
      final requestsInPeriod = _filterByPeriod(requests, period, now);
      final appointmentsInPeriod = _filterByPeriod(appointments, period, now);
      final quotationsInPeriod = _filterByPeriod(quotations, period, now);
      final workOrdersInPeriod = _filterByPeriod(workOrders, period, now);
      final receivablesInPeriod = _filterByPeriod(receivables, period, now);
      final satisfactionInPeriod =
          _filterByPeriod(satisfactionRows, period, now);
      final appointmentAssignmentsInPeriod = _filterByDateKey(
        appointmentAssignments,
        period,
        now,
        'assigned_at',
      );
      final timeEntriesInPeriod = _filterByPeriod(timeEntries, period, now);

      final activeCustomers =
          customersInPeriod.where((row) => row['is_active'] == true).length;

      final openRequests = requestsInPeriod.where((row) {
        final status = row['status'] as String?;
        return status != null && !{'cancelled', 'closed'}.contains(status);
      }).length;

      final scheduledAppointments = appointmentsInPeriod.where((row) {
        final status = row['status'] as String?;
        return status != null &&
            !{'cancelled', 'no_show', 'done'}.contains(status);
      }).length;

      final pendingQuoteRows = quotationsInPeriod.where((row) {
        final status = row['status'] as String?;
        return status != null &&
            {'draft', 'sent', 'viewed', 'changes_requested'}.contains(status);
      }).toList();
      final approvedQuoteRows = quotationsInPeriod
          .where((row) => row['status'] == 'approved')
          .toList();

      final openWorkOrders = workOrdersInPeriod.where((row) {
        final status = row['status'] as String?;
        return status != null && !{'done', 'cancelled'}.contains(status);
      }).length;
      final doneWorkOrders =
          workOrdersInPeriod.where((row) => row['status'] == 'done').length;
      final satisfactionCount = satisfactionInPeriod.length;
      final criticalSatisfactionCount = satisfactionInPeriod
          .where((row) => _intValue(row['rating']) <= 2)
          .length;

      var openReceivablesCents = 0;
      var overdueReceivablesCents = 0;
      var paidReceivablesCents = 0;
      for (final row in receivablesInPeriod) {
        final status = row['status'] as String?;
        final amount = _intValue(row['amount_cents']);
        final balance = _intValue(row['balance_cents']);
        if (status == 'paid') {
          paidReceivablesCents += amount;
          continue;
        }
        if (status == 'cancelled') continue;
        openReceivablesCents += balance;
        final dueDateValue = row['due_date'];
        if (dueDateValue is String) {
          final dueDate = DateTime.tryParse(dueDateValue);
          if (dueDate != null &&
              dueDate.isBefore(DateTime(now.year, now.month, now.day))) {
            overdueReceivablesCents += balance;
          }
        }
      }

      return ReportsSnapshot(
        period: period,
        monthlyTrend: _buildMonthlyTrend(
          requestsInPeriod: requestsInPeriod,
          workOrdersInPeriod: workOrdersInPeriod,
          receivablesInPeriod: receivablesInPeriod,
        ),
        customerRanking: _buildCustomerRanking(
          customersInPeriod: customersInPeriod,
          requestsInPeriod: requestsInPeriod,
          workOrdersInPeriod: workOrdersInPeriod,
          receivablesInPeriod: receivablesInPeriod,
        ),
        categoryRanking: _buildCategoryRanking(
          categories: categories,
          requestsInPeriod: requestsInPeriod,
        ),
        technicianRanking: _buildTechnicianRanking(
          profiles: profiles,
          appointmentsInPeriod: appointmentsInPeriod,
          appointmentAssignmentsInPeriod: appointmentAssignmentsInPeriod,
          timeEntriesInPeriod: timeEntriesInPeriod,
        ),
        totalCustomers: customersInPeriod.length,
        activeCustomers: activeCustomers,
        openServiceRequests: openRequests,
        scheduledAppointments: scheduledAppointments,
        pendingQuotations: pendingQuoteRows.length,
        pendingQuotationsCents: _sumCents(pendingQuoteRows, 'total_cents'),
        approvedQuotations: approvedQuoteRows.length,
        approvedQuotationsCents: _sumCents(approvedQuoteRows, 'total_cents'),
        openWorkOrders: openWorkOrders,
        doneWorkOrders: doneWorkOrders,
        openReceivablesCents: openReceivablesCents,
        overdueReceivablesCents: overdueReceivablesCents,
        paidReceivablesCents: paidReceivablesCents,
        satisfactionCount: satisfactionCount,
        averageSatisfaction: _averageRating(satisfactionInPeriod),
        criticalSatisfactionCount: criticalSatisfactionCount,
        updatedAt: now,
      );
    } on PostgrestException catch (e) {
      throw _mapError(e);
    } catch (e) {
      throw UnexpectedError(
        'Erro ao carregar relatorios.',
        e.toString(),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _selectRows(
    String table,
    String columns,
  ) async {
    final rows = await _db.from(table).select(columns).limit(1000);
    return (rows as List<dynamic>).cast<Map<String, dynamic>>();
  }

  int _sumCents(List<Map<String, dynamic>> rows, String key) =>
      rows.fold(0, (total, row) => total + _intValue(row[key]));

  int _intValue(dynamic value) => value is num ? value.toInt() : 0;

  double _averageRating(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 0;
    final total =
        rows.fold<int>(0, (sum, row) => sum + _intValue(row['rating']));
    return total / rows.length;
  }

  String _textValue(dynamic value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
    return fallback;
  }

  DateTime? _dateValue(dynamic value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  List<ReportDetailItem> _latestDetails(List<ReportDetailItem> details) {
    final sorted = [...details]..sort((a, b) {
        final aDate = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    return sorted.take(8).toList();
  }

  List<Map<String, dynamic>> _filterByPeriod(
    List<Map<String, dynamic>> rows,
    ReportsPeriod period,
    DateTime now,
  ) {
    final start = period.startAt(now);
    if (start == null) return rows;
    return rows.where((row) {
      final value = row['created_at'];
      if (value is! String) return false;
      final createdAt = DateTime.tryParse(value);
      return createdAt != null && !createdAt.isBefore(start);
    }).toList();
  }

  List<Map<String, dynamic>> _filterByDateKey(
    List<Map<String, dynamic>> rows,
    ReportsPeriod period,
    DateTime now,
    String key,
  ) {
    final start = period.startAt(now);
    if (start == null) return rows;
    return rows.where((row) {
      final value = row[key];
      if (value is! String) return false;
      final date = DateTime.tryParse(value);
      return date != null && !date.isBefore(start);
    }).toList();
  }

  List<MonthlyReportPoint> _buildMonthlyTrend({
    required List<Map<String, dynamic>> requestsInPeriod,
    required List<Map<String, dynamic>> workOrdersInPeriod,
    required List<Map<String, dynamic>> receivablesInPeriod,
  }) {
    final buckets = <DateTime, _MonthlyAccumulator>{};

    _MonthlyAccumulator bucketFor(DateTime month) =>
        buckets.putIfAbsent(month, _MonthlyAccumulator.new);

    for (final row in requestsInPeriod) {
      final month = _monthFromCreatedAt(row);
      if (month != null) bucketFor(month).serviceRequests++;
    }

    for (final row in workOrdersInPeriod) {
      if (row['status'] != 'done') continue;
      final month = _monthFromCreatedAt(row);
      if (month != null) bucketFor(month).doneWorkOrders++;
    }

    for (final row in receivablesInPeriod) {
      if (row['status'] != 'paid') continue;
      final month = _monthFromCreatedAt(row);
      if (month != null) {
        bucketFor(month).paidReceivablesCents += _intValue(row['amount_cents']);
      }
    }

    final months = buckets.keys.toList()..sort();
    return months
        .map(
          (month) => MonthlyReportPoint(
            month: month,
            serviceRequests: buckets[month]!.serviceRequests,
            doneWorkOrders: buckets[month]!.doneWorkOrders,
            paidReceivablesCents: buckets[month]!.paidReceivablesCents,
          ),
        )
        .toList();
  }

  DateTime? _monthFromCreatedAt(Map<String, dynamic> row) {
    final value = row['created_at'];
    if (value is! String) return null;
    final createdAt = DateTime.tryParse(value);
    if (createdAt == null) return null;
    return DateTime(createdAt.year, createdAt.month);
  }

  List<CustomerReportPoint> _buildCustomerRanking({
    required List<Map<String, dynamic>> customersInPeriod,
    required List<Map<String, dynamic>> requestsInPeriod,
    required List<Map<String, dynamic>> workOrdersInPeriod,
    required List<Map<String, dynamic>> receivablesInPeriod,
  }) {
    final customersById = <String, String>{};
    for (final row in customersInPeriod) {
      final id = row['id'];
      if (id is String) {
        customersById[id] = row['name'] as String? ?? 'Cliente';
      }
    }

    final buckets = <String, _CustomerAccumulator>{};
    _CustomerAccumulator bucketFor(String customerId) => buckets.putIfAbsent(
          customerId,
          () => _CustomerAccumulator(
            customerName: customersById[customerId] ?? 'Cliente',
          ),
        );

    for (final row in requestsInPeriod) {
      final customerId = row['customer_id'];
      if (customerId is String) {
        final bucket = bucketFor(customerId);
        bucket.serviceRequests++;
        bucket.details.add(
          ReportDetailItem(
            kind: 'Chamado',
            title:
                '#${_textValue(row['number'], '-')} · ${_textValue(row['title'], 'Chamado')}',
            status: _textValue(row['status'], 'sem status'),
            date: _dateValue(row['created_at']),
            routePath: row['id'] is String ? '/chamados/${row['id']}' : null,
          ),
        );
      }
    }

    for (final row in workOrdersInPeriod) {
      final customerId = row['customer_id'];
      if (customerId is String) {
        final bucket = bucketFor(customerId);
        bucket.workOrders++;
        bucket.details.add(
          ReportDetailItem(
            kind: 'OS',
            title:
                '#${_textValue(row['number'], '-')} · ${_textValue(row['title'], 'Ordem de serviço')}',
            status: _textValue(row['status'], 'sem status'),
            date: _dateValue(row['created_at']),
            amountCents: _intValue(row['total_cents']),
            routePath:
                row['id'] is String ? '/ordens-servico/${row['id']}' : null,
          ),
        );
      }
    }

    for (final row in receivablesInPeriod) {
      final customerId = row['customer_id'];
      if (customerId is! String) continue;
      final bucket = bucketFor(customerId);
      final status = row['status'] as String?;
      if (status == 'paid') {
        bucket.receivedCents += _intValue(row['amount_cents']);
      } else if (status != 'cancelled') {
        bucket.openReceivablesCents += _intValue(row['balance_cents']);
      }
      bucket.details.add(
        ReportDetailItem(
          kind: 'Financeiro',
          title: _textValue(row['description'], 'Recebível'),
          status: status ?? 'sem status',
          date: _dateValue(row['due_date']) ?? _dateValue(row['created_at']),
          amountCents: status == 'paid'
              ? _intValue(row['amount_cents'])
              : _intValue(row['balance_cents']),
          routePath: '/financeiro',
        ),
      );
    }

    final ranking = buckets.entries
        .map(
          (entry) => CustomerReportPoint(
            customerId: entry.key,
            customerName: entry.value.customerName,
            serviceRequests: entry.value.serviceRequests,
            workOrders: entry.value.workOrders,
            receivedCents: entry.value.receivedCents,
            openReceivablesCents: entry.value.openReceivablesCents,
            details: _latestDetails(entry.value.details),
          ),
        )
        .where((point) => point.totalInteractions > 0 || point.totalCents > 0)
        .toList()
      ..sort((a, b) {
        final valueComparison = b.totalCents.compareTo(a.totalCents);
        if (valueComparison != 0) return valueComparison;
        return b.totalInteractions.compareTo(a.totalInteractions);
      });

    return ranking.take(5).toList();
  }

  List<CategoryReportPoint> _buildCategoryRanking({
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> requestsInPeriod,
  }) {
    final categoryNamesById = <String, String>{};
    for (final row in categories) {
      final id = row['id'];
      if (id is String) {
        categoryNamesById[id] = row['name'] as String? ?? 'Categoria';
      }
    }

    final buckets = <String, _CategoryAccumulator>{};
    _CategoryAccumulator bucketFor(String categoryId) => buckets.putIfAbsent(
          categoryId,
          () => _CategoryAccumulator(
            categoryName: categoryNamesById[categoryId] ?? 'Sem categoria',
          ),
        );

    for (final row in requestsInPeriod) {
      final categoryId = row['category_id'] as String? ?? 'uncategorized';
      final status = row['status'] as String?;
      final bucket = bucketFor(categoryId);
      bucket.totalRequests++;
      if (status == 'cancelled' || status == 'closed') {
        bucket.closedRequests++;
      } else {
        bucket.openRequests++;
      }
      bucket.details.add(
        ReportDetailItem(
          kind: 'Chamado',
          title:
              '#${_textValue(row['number'], '-')} · ${_textValue(row['title'], 'Chamado')}',
          status: status ?? 'sem status',
          date: _dateValue(row['created_at']),
          routePath: row['id'] is String ? '/chamados/${row['id']}' : null,
        ),
      );
    }

    final ranking = buckets.entries
        .map(
          (entry) => CategoryReportPoint(
            categoryId: entry.key,
            categoryName: entry.value.categoryName,
            totalRequests: entry.value.totalRequests,
            openRequests: entry.value.openRequests,
            closedRequests: entry.value.closedRequests,
            details: _latestDetails(entry.value.details),
          ),
        )
        .toList()
      ..sort((a, b) {
        final totalComparison = b.totalRequests.compareTo(a.totalRequests);
        if (totalComparison != 0) return totalComparison;
        return b.openRequests.compareTo(a.openRequests);
      });

    return ranking.take(5).toList();
  }

  List<TechnicianReportPoint> _buildTechnicianRanking({
    required List<Map<String, dynamic>> profiles,
    required List<Map<String, dynamic>> appointmentsInPeriod,
    required List<Map<String, dynamic>> appointmentAssignmentsInPeriod,
    required List<Map<String, dynamic>> timeEntriesInPeriod,
  }) {
    final profileNamesById = <String, String>{};
    for (final row in profiles) {
      final id = row['id'];
      if (id is String) {
        profileNamesById[id] = row['full_name'] as String? ?? 'Técnico';
      }
    }
    final appointmentStatusById = <String, String>{};
    final appointmentDateById = <String, DateTime?>{};
    for (final row in appointmentsInPeriod) {
      final id = row['id'];
      if (id is! String) continue;
      appointmentStatusById[id] = _textValue(row['status'], 'sem status');
      appointmentDateById[id] =
          _dateValue(row['scheduled_start']) ?? _dateValue(row['created_at']);
    }

    final buckets = <String, _TechnicianAccumulator>{};
    _TechnicianAccumulator bucketFor(String technicianId) =>
        buckets.putIfAbsent(
          technicianId,
          () => _TechnicianAccumulator(
            technicianName: profileNamesById[technicianId] ?? 'Técnico',
          ),
        );

    for (final row in appointmentAssignmentsInPeriod) {
      if (row['revoked_at'] != null) continue;
      final technicianId = row['technician_user_id'];
      if (technicianId is String) {
        final bucket = bucketFor(technicianId);
        bucket.appointments++;
        final appointmentId = row['appointment_id'];
        bucket.details.add(
          ReportDetailItem(
            kind: 'Agenda',
            title:
                'Agendamento ${appointmentId is String ? appointmentId.substring(0, 8) : '#'}',
            status: appointmentId is String
                ? appointmentStatusById[appointmentId] ?? 'atribuido'
                : 'atribuido',
            date: appointmentId is String
                ? appointmentDateById[appointmentId]
                : _dateValue(row['assigned_at']),
            routePath:
                appointmentId is String ? '/agenda/$appointmentId' : null,
          ),
        );
      }
    }

    for (final row in timeEntriesInPeriod) {
      final technicianId = row['technician_id'];
      if (technicianId is! String) continue;
      final bucket = bucketFor(technicianId);
      bucket.timeEntries++;
      bucket.minutesWorked += _intValue(row['duration_minutes']);
      final minutes = _intValue(row['duration_minutes']);
      bucket.details.add(
        ReportDetailItem(
          kind: 'Horas',
          title: '${(minutes / 60).toStringAsFixed(1)} h registradas',
          status: 'apontado',
          date: _dateValue(row['created_at']),
          routePath: row['work_order_id'] is String
              ? '/ordens-servico/${row['work_order_id']}'
              : null,
        ),
      );
    }

    final ranking = buckets.entries
        .map(
          (entry) => TechnicianReportPoint(
            technicianId: entry.key,
            technicianName: entry.value.technicianName,
            appointments: entry.value.appointments,
            timeEntries: entry.value.timeEntries,
            minutesWorked: entry.value.minutesWorked,
            details: _latestDetails(entry.value.details),
          ),
        )
        .where((point) => point.totalActivity > 0 || point.minutesWorked > 0)
        .toList()
      ..sort((a, b) {
        final minutesComparison = b.minutesWorked.compareTo(a.minutesWorked);
        if (minutesComparison != 0) return minutesComparison;
        return b.appointments.compareTo(a.appointments);
      });

    return ranking.take(5).toList();
  }

  AppError _mapError(PostgrestException e) {
    if (e.code == '42501' || e.code == 'insufficient_privilege') {
      return const PermissionError(
        'Voce nao tem permissao para acessar relatorios.',
      );
    }
    return UnexpectedError(
      'Nao foi possivel carregar os relatorios.',
      e.message,
    );
  }
}

class _MonthlyAccumulator {
  int serviceRequests = 0;
  int doneWorkOrders = 0;
  int paidReceivablesCents = 0;
}

class _CustomerAccumulator {
  _CustomerAccumulator({required this.customerName});

  final String customerName;
  int serviceRequests = 0;
  int workOrders = 0;
  int receivedCents = 0;
  int openReceivablesCents = 0;
  final details = <ReportDetailItem>[];
}

class _CategoryAccumulator {
  _CategoryAccumulator({required this.categoryName});

  final String categoryName;
  int totalRequests = 0;
  int openRequests = 0;
  int closedRequests = 0;
  final details = <ReportDetailItem>[];
}

class _TechnicianAccumulator {
  _TechnicianAccumulator({required this.technicianName});

  final String technicianName;
  int appointments = 0;
  int timeEntries = 0;
  int minutesWorked = 0;
  final details = <ReportDetailItem>[];
}
