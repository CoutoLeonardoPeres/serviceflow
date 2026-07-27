import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/communications/domain/message_template.dart';

void main() {
  group('MessageChannel', () {
    test('fromString mapeia todos os valores', () {
      expect(messageChannelFromString('whatsapp'), MessageChannel.whatsapp);
      expect(messageChannelFromString('email'), MessageChannel.email);
      expect(messageChannelFromString('phone'), MessageChannel.phone);
      expect(messageChannelFromString('generic'), MessageChannel.generic);
      expect(messageChannelFromString('desconhecido'), MessageChannel.generic);
    });

    test('label retorna string legível', () {
      expect(MessageChannel.whatsapp.label, 'WhatsApp');
      expect(MessageChannel.email.label, 'E-mail');
      expect(MessageChannel.generic.label, 'Geral');
      expect(MessageChannel.phone.label, 'Ligação');
    });
  });

  group('MessageTemplate.resolveBody', () {
    final tpl = MessageTemplate(
      id: 'tpl-1',
      name: 'Orçamento enviado',
      channel: MessageChannel.whatsapp,
      body:
          'Olá, {{customer_name}}! Orçamento nº {{quotation_number}} no valor de R\$ {{amount}}. Link: {{link}} — {{company_name}}',
      isActive: true,
      createdAt: _epoch,
    );

    test('substitui todas as variáveis corretamente', () {
      final result = tpl.resolveBody({
        'customer_name': 'João Silva',
        'quotation_number': '42',
        'amount': '1.500,00',
        'link': 'https://app.com/orcamento/abc',
        'company_name': 'Eletroceu',
      });

      expect(result, contains('João Silva'));
      expect(result, contains('42'));
      expect(result, contains('1.500,00'));
      expect(result, contains('https://app.com/orcamento/abc'));
      expect(result, contains('Eletroceu'));
      expect(result, isNot(contains('{{customer_name}}')));
      expect(result, isNot(contains('{{quotation_number}}')));
    });

    test('deixa variáveis sem correspondência intactas', () {
      final result = tpl.resolveBody({'customer_name': 'Maria'});
      expect(result, contains('Maria'));
      expect(result, contains('{{quotation_number}}'));
    });

    test('funciona com mapa vazio', () {
      final result = tpl.resolveBody({});
      expect(result, contains('{{customer_name}}'));
    });
  });

  group('MessageTemplate.resolveSubject', () {
    final tpl = MessageTemplate(
      id: 'tpl-2',
      name: 'E-mail de orçamento',
      channel: MessageChannel.email,
      subject: 'Orçamento {{quotation_number}} — {{company_name}}',
      body: 'Corpo',
      isActive: true,
      createdAt: _epoch,
    );

    test('substitui variáveis no assunto', () {
      final subject = tpl.resolveSubject({
        'quotation_number': '007',
        'company_name': 'Acme',
      });
      expect(subject, 'Orçamento 007 — Acme');
    });

    test('retorna null quando subject é null', () {
      final noSubject = MessageTemplate(
        id: 'tpl-3',
        name: 'Sem assunto',
        channel: MessageChannel.whatsapp,
        body: 'corpo',
        isActive: true,
        createdAt: _epoch,
      );
      expect(noSubject.resolveSubject({}), isNull);
    });
  });

  group('TemplateVars', () {
    test('all contém todas as chaves esperadas', () {
      expect(TemplateVars.all, contains(TemplateVars.customerName));
      expect(TemplateVars.all, contains(TemplateVars.companyName));
      expect(TemplateVars.all, contains(TemplateVars.quotationNumber));
      expect(TemplateVars.all, contains(TemplateVars.workOrderNumber));
      expect(TemplateVars.all, contains(TemplateVars.amount));
      expect(TemplateVars.all, contains(TemplateVars.link));
    });

    test('label retorna string não vazia para todas as chaves', () {
      for (final key in TemplateVars.all) {
        expect(TemplateVars.label(key), isNotEmpty);
      }
    });
  });

  group('messageTemplateFromRow', () {
    test('desserializa row corretamente', () {
      final row = {
        'id': 'id-1',
        'name': 'Confirmação',
        'channel': 'whatsapp',
        'subject': null,
        'body': 'Olá {{customer_name}}',
        'is_active': true,
        'created_at': '2026-07-25T10:00:00Z',
      };

      final tpl = messageTemplateFromRow(row);
      expect(tpl.id, 'id-1');
      expect(tpl.name, 'Confirmação');
      expect(tpl.channel, MessageChannel.whatsapp);
      expect(tpl.subject, isNull);
      expect(tpl.body, 'Olá {{customer_name}}');
      expect(tpl.isActive, isTrue);
    });

    test('is_active assume true quando null', () {
      final row = {
        'id': 'id-2',
        'name': 'T',
        'channel': 'email',
        'subject': null,
        'body': 'B',
        'is_active': null,
        'created_at': '2026-07-25T10:00:00Z',
      };
      final tpl = messageTemplateFromRow(row);
      expect(tpl.isActive, isTrue);
    });
  });
}

// Auxiliar para não depender de DateTime.now()
final _epoch = DateTime.utc(2026, 1, 1);
