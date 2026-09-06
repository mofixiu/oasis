import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/landa_currency.dart';

/// How much of the vault the tenant is putting towards each unit.
///
/// A tenant renting two places saves for both out of one balance. Without
/// this, every rent card measured its progress against the *whole* vault, so
/// ₦10,000 saved for one flat read as ₦10,000 saved for the other one too:
/// the same money counted twice, and a tenant told they were halfway to two
/// bills they could only pay one of.
///
/// This is a plan, not a second account. The backend has one vault with one
/// balance and knows nothing about these splits; money set aside here can
/// still be spent on anything. Everything below is worded and capped to keep
/// that true rather than implying the money is ring-fenced.
///
/// Stored on the device and scoped to the signed-in user, because it is a
/// personal intention rather than a fact about the money: there is no
/// endpoint to put it behind.
class VaultAllocations {
  /// Minor units (kobo) set aside per agreement id.
  final Map<String, int> _byAgreement;

  const VaultAllocations._(this._byAgreement);

  const VaultAllocations.empty() : _byAgreement = const {};

  static String _storageKey(String userId) => 'vault_allocations_$userId';

  /// Reads a user's allocations. Returns empty rather than throwing when the
  /// stored value is missing or unreadable: a lost savings plan is a nuisance,
  /// a crash on the payments screen is not recoverable.
  static Future<VaultAllocations> load(String userId) async {
    if (userId.isEmpty) return const VaultAllocations.empty();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId));
      if (raw == null || raw.isEmpty) return const VaultAllocations.empty();

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const VaultAllocations.empty();
      return VaultAllocations._({
        for (final entry in decoded.entries)
          if (entry.value is num && (entry.value as num) > 0)
            entry.key.toString(): (entry.value as num).toInt(),
      });
    } catch (e) {
      debugPrint('[VAULT ALLOCATIONS] Could not read: $e');
      return const VaultAllocations.empty();
    }
  }

  Future<void> save(String userId) async {
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey(userId), jsonEncode(_byAgreement));
    } catch (e) {
      debugPrint('[VAULT ALLOCATIONS] Could not save: $e');
    }
  }

  /// Forgets a user's plan entirely. Called on sign-out, so the next person on
  /// the phone does not inherit someone else's savings goals.
  static Future<void> clearFor(String userId) async {
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey(userId));
    } catch (e) {
      debugPrint('[VAULT ALLOCATIONS] Could not clear: $e');
    }
  }

  bool get isEmpty => _byAgreement.isEmpty;

  /// Agreement ids with something set aside, largest first.
  List<String> get agreementIds {
    final ids = _byAgreement.keys.toList();
    ids.sort((a, b) => _byAgreement[b]!.compareTo(_byAgreement[a]!));
    return ids;
  }

  int get totalMinorUnits =>
      _byAgreement.values.fold(0, (sum, value) => sum + value);

  /// What is set aside for [agreementId], as the decimal string the rest of
  /// the app speaks.
  ///
  /// [availableBalance] caps the answer, and is not optional for a reason: the
  /// plan is a local intention while the balance is the truth, and the two
  /// drift the moment money is spent elsewhere. Reporting more set aside than
  /// actually exists would be the one lie this whole class is here to avoid.
  String setAsideFor(String agreementId, String availableBalance) {
    final planned = _byAgreement[agreementId] ?? 0;
    if (planned <= 0) return '0.00';

    final available = LandaCurrency.minorUnits(availableBalance) ?? 0;
    if (available <= 0) return '0.00';
    if (totalMinorUnits <= available) {
      return LandaCurrency.fromMinorUnits(planned);
    }

    // Over-allocated: the balance has fallen below the sum of the plans, so
    // each is scaled back by the same proportion. Trimming one to zero while
    // another stayed whole would be an arbitrary choice about whose savings
    // disappeared.
    return LandaCurrency.fromMinorUnits(
      (planned * available) ~/ totalMinorUnits,
    );
  }

  /// Whether the plans together promise more than the vault holds: true after
  /// money set aside for one thing has been spent on another.
  bool exceedsBalance(String availableBalance) =>
      totalMinorUnits > (LandaCurrency.minorUnits(availableBalance) ?? 0);

  /// Adds [amount] to what is set aside for [agreementId].
  VaultAllocations plus(String agreementId, String amount) {
    final extra = LandaCurrency.minorUnits(amount) ?? 0;
    if (agreementId.isEmpty || extra <= 0) return this;
    return VaultAllocations._({
      ..._byAgreement,
      agreementId: (_byAgreement[agreementId] ?? 0) + extra,
    });
  }

  /// Drops the plan for [agreementId]: the rent it was for has been paid, so
  /// carrying it forward would show savings towards a settled bill.
  VaultAllocations without(String agreementId) {
    if (!_byAgreement.containsKey(agreementId)) return this;
    final next = {..._byAgreement}..remove(agreementId);
    return VaultAllocations._(next);
  }
}
