import 'package:flutter_test/flutter_test.dart';
import 'package:oasis_app/features/vault/models/vault_allocations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tenant renting two places saves for both out of one balance. Before this,
/// every rent card measured against the whole vault, so ₦10,000 saved for one
/// flat read as ₦10,000 saved for the other one too.
///
/// The plan is local and the balance is the truth, so the failure that matters
/// most is claiming more is set aside than actually exists.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('two goals split one balance instead of double-counting it', () {
    final plan = const VaultAllocations.empty()
        .plus('agreement-1', '10000.00')
        .plus('agreement-2', '20000.00');

    expect(plan.setAsideFor('agreement-1', '30000.00'), '10000.00');
    expect(plan.setAsideFor('agreement-2', '30000.00'), '20000.00');
    // A bill with nothing put towards it says so, rather than borrowing the
    // balance the other two are using.
    expect(plan.setAsideFor('agreement-3', '30000.00'), '0.00');
  });

  test('never claims more is set aside than the vault holds', () {
    // Money set aside for rent was spent on a short stay. The plan has to give
    // way to the balance: telling someone they are covered when they are not
    // sends them into a payment that gets declined.
    final plan = const VaultAllocations.empty()
        .plus('agreement-1', '10000.00')
        .plus('agreement-2', '10000.00');

    expect(plan.exceedsBalance('5000.00'), isTrue);
    // Scaled evenly rather than draining one goal to keep the other whole.
    expect(plan.setAsideFor('agreement-1', '5000.00'), '2500.00');
    expect(plan.setAsideFor('agreement-2', '5000.00'), '2500.00');
  });

  test('an empty vault sets nothing aside', () {
    final plan = const VaultAllocations.empty().plus('agreement-1', '10000.00');
    expect(plan.setAsideFor('agreement-1', '0.00'), '0.00');
  });

  test('adding to the same goal accumulates', () {
    final plan = const VaultAllocations.empty()
        .plus('agreement-1', '10000.00')
        .plus('agreement-1', '5000.00');

    expect(plan.setAsideFor('agreement-1', '50000.00'), '15000.00');
  });

  test('a paid bill drops its goal', () {
    // Left in place, the tenant keeps seeing progress towards rent they have
    // already paid.
    final plan = const VaultAllocations.empty()
        .plus('agreement-1', '10000.00')
        .plus('agreement-2', '20000.00');

    final after = plan.without('agreement-1');
    expect(after.setAsideFor('agreement-1', '30000.00'), '0.00');
    expect(after.setAsideFor('agreement-2', '30000.00'), '20000.00');
  });

  test('nonsense amounts are ignored rather than stored', () {
    final plan = const VaultAllocations.empty()
        .plus('agreement-1', 'not money')
        .plus('', '10000.00')
        .plus('agreement-2', '0.00');

    expect(plan.isEmpty, isTrue);
  });

  test('the plan survives a restart, and belongs to one user', () async {
    await const VaultAllocations.empty()
        .plus('agreement-1', '10000.00')
        .save('user-a');

    final reloaded = await VaultAllocations.load('user-a');
    expect(reloaded.setAsideFor('agreement-1', '50000.00'), '10000.00');

    // Someone else signing in on the same phone starts clean.
    final other = await VaultAllocations.load('user-b');
    expect(other.isEmpty, isTrue);

    await VaultAllocations.clearFor('user-a');
    expect((await VaultAllocations.load('user-a')).isEmpty, isTrue);
  });

  test('an unreadable stored plan degrades to none, not a crash', () async {
    SharedPreferences.setMockInitialValues({
      'vault_allocations_user-a': 'not json',
    });
    expect((await VaultAllocations.load('user-a')).isEmpty, isTrue);
  });
}
