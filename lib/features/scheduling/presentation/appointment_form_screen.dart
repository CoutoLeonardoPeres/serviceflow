import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/error_view.dart';
import '../../service_requests/application/service_request_list_notifier.dart';
import '../../service_requests/data/service_request_repository.dart';
import '../../service_requests/domain/service_request.dart';
import '../application/appointment_form_notifier.dart';
import '../application/appointment_list_notifier.dart';
import '../domain/technician.dart';

final _schedulableRequestsProvider =
    FutureProvider.autoDispose<List<ServiceRequest>>((ref) async {
  final repo = ref.read(serviceRequestRepositoryProvider);
  final result = await repo.listPaged(
    filter: const ServiceRequestFilter(),
  );
  return result.items
      .where((request) => !request.status.isTerminal)
      .take(20)
      .toList();
});

class AppointmentFormScreen extends ConsumerStatefulWidget {
  const AppointmentFormScreen({super.key});

  @override
  ConsumerState<AppointmentFormScreen> createState() =>
      _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends ConsumerState<AppointmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  ServiceRequest? _selectedRequest;
  String? _professionalId;
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().add(const Duration(hours: 1));
    _start = DateTime(now.year, now.month, now.day, now.hour);
    _end = _start.add(const Duration(hours: 2));
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    setState(() {
      _start =
          DateTime(date.year, date.month, date.day, _start.hour, _start.minute);
      _end = DateTime(date.year, date.month, date.day, _end.hour, _end.minute);
    });
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null) return;
    setState(() {
      _start = DateTime(
          _start.year, _start.month, _start.day, time.hour, time.minute);
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(hours: 2));
      }
    });
  }

  Future<void> _pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_end),
    );
    if (time == null) return;
    setState(() {
      _end = DateTime(_end.year, _end.month, _end.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final request = _selectedRequest;
    final professionalId = _professionalId;
    if (request == null || professionalId == null) return;

    // O usuário só existe para profissional com login; parceiro externo é
    // identificado pelo cadastro de profissional.
    final technicianUserId = ref
        .read(techniciansProvider)
        .maybeWhen(
          data: (items) => items
              .cast<Technician?>()
              .firstWhere(
                (t) => t?.professionalId == professionalId,
                orElse: () => null,
              )
              ?.userId,
          orElse: () => null,
        );

    await ref.read(appointmentFormProvider.notifier).scheduleVisit(
          serviceRequestId: request.id,
          customerId: request.customerId,
          addressId: request.addressId,
          professionalId: professionalId,
          technicianUserId: technicianUserId,
          scheduledStart: _start,
          scheduledEnd: _end,
          notes: _notesController.text,
        );

    final state = ref.read(appointmentFormProvider);
    if (!mounted) return;
    if (state is AppointmentFormSuccess) {
      context.go(AppRoutes.appointmentDetail(state.appointment.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(_schedulableRequestsProvider);
    final technicians = ref.watch(techniciansProvider);
    final formState = ref.watch(appointmentFormProvider);
    final isLoading = formState is AppointmentFormLoading;
    final date = DateFormat('dd/MM/yyyy', 'pt_BR');
    final time = DateFormat('HH:mm', 'pt_BR');

    return Scaffold(
      appBar: AppBar(title: const Text('Novo agendamento')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (formState is AppointmentFormError)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ErrorView(message: formState.error.userMessage),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Agenda da visita',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 16),
                    requests.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Chamados indisponíveis.'),
                      data: (items) => DropdownButtonFormField<ServiceRequest>(
                        initialValue: _selectedRequest,
                        decoration: const InputDecoration(labelText: 'Chamado'),
                        items: items
                            .map(
                              (request) => DropdownMenuItem(
                                value: request,
                                child: Text(
                                  '${request.displayNumber} · ${request.title}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isLoading
                            ? null
                            : (value) =>
                                setState(() => _selectedRequest = value),
                        validator: (value) =>
                            value == null ? 'Selecione um chamado.' : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    technicians.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Técnicos indisponíveis.'),
                      data: (items) => DropdownButtonFormField<String>(
                        initialValue: _professionalId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Profissional',
                        ),
                        items: items
                            .map(
                              (technician) => DropdownMenuItem(
                                value: technician.professionalId,
                                child: Text(
                                  technician.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isLoading
                            ? null
                            : (value) =>
                                setState(() => _professionalId = value),
                        validator: (value) => value == null
                            ? 'Selecione um profissional.'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _pickDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(date.format(_start)),
                        ),
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _pickStartTime,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(time.format(_start)),
                        ),
                        OutlinedButton.icon(
                          onPressed: isLoading ? null : _pickEndTime,
                          icon: const Icon(Icons.stop),
                          label: Text(time.format(_end)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Observações',
                        hintText: 'Ex.: confirmar portaria antes da visita',
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isLoading ? null : _submit,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Salvar agendamento'),
            ),
          ],
        ),
      ),
    );
  }
}
