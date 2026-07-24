enum ReportsPeriod {
  last30Days,
  currentMonth,
  currentYear,
  all;

  String get label => switch (this) {
        ReportsPeriod.last30Days => '30 dias',
        ReportsPeriod.currentMonth => 'Mês atual',
        ReportsPeriod.currentYear => 'Ano atual',
        ReportsPeriod.all => 'Tudo',
      };

  DateTime? startAt(DateTime now) => switch (this) {
        ReportsPeriod.last30Days => now.subtract(const Duration(days: 30)),
        ReportsPeriod.currentMonth => DateTime(now.year, now.month),
        ReportsPeriod.currentYear => DateTime(now.year),
        ReportsPeriod.all => null,
      };
}

class ReportsSnapshot {
  const ReportsSnapshot({
    required this.period,
    required this.monthlyTrend,
    required this.customerRanking,
    required this.categoryRanking,
    required this.technicianRanking,
    required this.totalCustomers,
    required this.activeCustomers,
    required this.openServiceRequests,
    required this.scheduledAppointments,
    required this.pendingQuotations,
    required this.pendingQuotationsCents,
    required this.approvedQuotations,
    required this.approvedQuotationsCents,
    required this.openWorkOrders,
    required this.doneWorkOrders,
    required this.openReceivablesCents,
    required this.overdueReceivablesCents,
    required this.paidReceivablesCents,
    required this.satisfactionCount,
    required this.averageSatisfaction,
    required this.criticalSatisfactionCount,
    required this.updatedAt,
  });

  final ReportsPeriod period;
  final List<MonthlyReportPoint> monthlyTrend;
  final List<CustomerReportPoint> customerRanking;
  final List<CategoryReportPoint> categoryRanking;
  final List<TechnicianReportPoint> technicianRanking;
  final int totalCustomers;
  final int activeCustomers;
  final int openServiceRequests;
  final int scheduledAppointments;
  final int pendingQuotations;
  final int pendingQuotationsCents;
  final int approvedQuotations;
  final int approvedQuotationsCents;
  final int openWorkOrders;
  final int doneWorkOrders;
  final int openReceivablesCents;
  final int overdueReceivablesCents;
  final int paidReceivablesCents;
  final int satisfactionCount;
  final double averageSatisfaction;
  final int criticalSatisfactionCount;
  final DateTime updatedAt;

  int get inactiveCustomers => totalCustomers - activeCustomers;

  int get totalOperationalItems =>
      openServiceRequests + scheduledAppointments + openWorkOrders;

  int get totalQuotationPipelineCents =>
      pendingQuotationsCents + approvedQuotationsCents;

  int get totalFinancialCents => openReceivablesCents + paidReceivablesCents;

  int get positiveSatisfactionCount =>
      satisfactionCount - criticalSatisfactionCount;

  String get satisfactionScoreLabel {
    if (satisfactionCount == 0) return 'Sem notas';
    return '${averageSatisfaction.toStringAsFixed(1)}/5';
  }

  double get workOrderCompletionRate {
    final total = openWorkOrders + doneWorkOrders;
    if (total == 0) return 0;
    return doneWorkOrders / total;
  }

  static ReportsSnapshot empty({
    ReportsPeriod period = ReportsPeriod.last30Days,
    DateTime? updatedAt,
  }) =>
      ReportsSnapshot(
        period: period,
        monthlyTrend: const [],
        customerRanking: const [],
        categoryRanking: const [],
        technicianRanking: const [],
        totalCustomers: 0,
        activeCustomers: 0,
        openServiceRequests: 0,
        scheduledAppointments: 0,
        pendingQuotations: 0,
        pendingQuotationsCents: 0,
        approvedQuotations: 0,
        approvedQuotationsCents: 0,
        openWorkOrders: 0,
        doneWorkOrders: 0,
        openReceivablesCents: 0,
        overdueReceivablesCents: 0,
        paidReceivablesCents: 0,
        satisfactionCount: 0,
        averageSatisfaction: 0,
        criticalSatisfactionCount: 0,
        updatedAt: updatedAt ?? DateTime.now(),
      );
}

class TechnicianReportPoint {
  const TechnicianReportPoint({
    required this.technicianId,
    required this.technicianName,
    required this.appointments,
    required this.timeEntries,
    required this.minutesWorked,
    this.details = const [],
  });

  final String technicianId;
  final String technicianName;
  final int appointments;
  final int timeEntries;
  final int minutesWorked;
  final List<ReportDetailItem> details;

  double get hoursWorked => minutesWorked / 60;

  int get totalActivity => appointments + timeEntries;
}

class CategoryReportPoint {
  const CategoryReportPoint({
    required this.categoryId,
    required this.categoryName,
    required this.totalRequests,
    required this.openRequests,
    required this.closedRequests,
    this.details = const [],
  });

  final String categoryId;
  final String categoryName;
  final int totalRequests;
  final int openRequests;
  final int closedRequests;
  final List<ReportDetailItem> details;

  double get openRate {
    if (totalRequests == 0) return 0;
    return openRequests / totalRequests;
  }
}

class CustomerReportPoint {
  const CustomerReportPoint({
    required this.customerId,
    required this.customerName,
    required this.serviceRequests,
    required this.workOrders,
    required this.receivedCents,
    required this.openReceivablesCents,
    this.details = const [],
  });

  final String customerId;
  final String customerName;
  final int serviceRequests;
  final int workOrders;
  final int receivedCents;
  final int openReceivablesCents;
  final List<ReportDetailItem> details;

  int get totalCents => receivedCents + openReceivablesCents;

  int get totalInteractions => serviceRequests + workOrders;
}

class MonthlyReportPoint {
  const MonthlyReportPoint({
    required this.month,
    required this.serviceRequests,
    required this.doneWorkOrders,
    required this.paidReceivablesCents,
  });

  final DateTime month;
  final int serviceRequests;
  final int doneWorkOrders;
  final int paidReceivablesCents;

  int get totalActivity => serviceRequests + doneWorkOrders;
}

class ReportDetailItem {
  const ReportDetailItem({
    required this.kind,
    required this.title,
    required this.status,
    this.date,
    this.amountCents,
    this.routePath,
  });

  final String kind;
  final String title;
  final String status;
  final DateTime? date;
  final int? amountCents;
  final String? routePath;
}
