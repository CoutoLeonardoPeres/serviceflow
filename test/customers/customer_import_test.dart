import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/customers/domain/customer.dart';
import 'package:serviceflow/features/customers/domain/customer_import.dart';

void main() {
  test('parseCustomerImportCsv le cabecalho com ponto e virgula', () {
    const csv = '''
tipo;nome;cpf_cnpj;telefone;contato;contato_telefone;cep;logradouro;numero;bairro;cidade;uf;observacoes
Pessoa Fisica;Ana Lima;12345678909;27999998888;Ana Lima;27999998888;29160000;Rua A;100;Centro;Serra;ES;Cliente VIP
Empresa;Frio Total;11222333000181;2733334444;Carlos;27999990000;29000000;Av B;200;Jardim;Vitoria;ES;Contrato anual
''';

    final preview = parseCustomerImportCsv(csv);

    expect(preview.rows, hasLength(2));
    expect(preview.issues, isEmpty);
    expect(preview.rows.first.type, CustomerType.person);
    expect(preview.rows.first.name, 'Ana Lima');
    expect(preview.rows.first.document, '12345678909');
    expect(preview.rows.first.phone, '27999998888');
    expect(preview.rows.first.city, 'Serra');
    expect(preview.rows.last.type, CustomerType.company);
    expect(preview.rows.last.document, '11222333000181');
  });

  test('parseCustomerImportCsv marca linha com documento invalido', () {
    const csv = '''
nome,cpf_cnpj,telefone
Cliente Invalido,123,27999998888
''';

    final preview = parseCustomerImportCsv(csv);

    expect(preview.rows, isEmpty);
    expect(preview.issues, hasLength(1));
    expect(preview.issues.single.rowNumber, 2);
    expect(preview.issues.single.message, 'CPF/CNPJ inválido.');
  });
}
