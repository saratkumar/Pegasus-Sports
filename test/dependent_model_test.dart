import 'package:fitness_booking/models/dependent_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DependentModel child(DateTime dob) =>
      DependentModel(name: 'Test', dateOfBirth: dob);

  test('age counts whole years, turning over on the birthday', () {
    final c = child(DateTime(2016, 10, 10));
    expect(c.ageOn(DateTime(2026, 10, 9)), 9);
    expect(c.ageOn(DateTime(2026, 10, 10)), 10);
  });

  test('eligible from 6th birthday up to the day before 18th', () {
    final c = child(DateTime(2020, 3, 15));
    expect(c.isEligibleJuniorOn(DateTime(2026, 3, 14)), isFalse); // 5
    expect(c.isEligibleJuniorOn(DateTime(2026, 3, 15)), isTrue); // 6
    expect(c.isEligibleJuniorOn(DateTime(2038, 3, 14)), isTrue); // 17
    expect(c.isEligibleJuniorOn(DateTime(2038, 3, 15)), isFalse); // 18
  });
}
