import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/features/professionals/domain/professional_categories.dart';

void main() {
  test('professionalCategories já vem ordenada de A a Z', () {
    final sorted = [...professionalCategories]..sort(compareCategoryNames);
    expect(professionalCategories, sorted);
  });

  test('compareCategoryNames ignora acento e caixa', () {
    final list = ['Ácido', 'zebra', 'Élder', 'abelha', 'Çeda']
      ..sort(compareCategoryNames);
    expect(list, ['abelha', 'Ácido', 'Çeda', 'Élder', 'zebra']);
  });
}
