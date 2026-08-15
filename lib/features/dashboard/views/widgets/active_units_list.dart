import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../models/property_unit.dart';

class ActiveUnitsList extends StatelessWidget {
  final List<PropertyUnit> units;

  const ActiveUnitsList({super.key, required this.units});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Active Units',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Row(
                children: [
                  Text('View All'),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...units.map((unit) => Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _ActiveUnitCard(unit: unit),
            )),
      ],
    );
  }
}

class _ActiveUnitCard extends StatelessWidget {
  final PropertyUnit unit;

  const _ActiveUnitCard({required this.unit});

  String formatCurrency(double amount) {
    String res = amount.toInt().toString();
    String formatted = '';
    for (int i = res.length - 1; i >= 0; i--) {
      formatted = res[i] + formatted;
      if ((res.length - i) % 3 == 0 && i != 0) {
        formatted = ',$formatted';
      }
    }
    return '₦ $formatted';
  }

  @override
  Widget build(BuildContext context) {
    final isPaid = unit.status == UnitStatus.paid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.home, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unit.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tenant: ${unit.tenantName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid ? AppTheme.secondaryColor.withOpacity(0.1) : AppTheme.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPaid ? Icons.check_circle_outline : Icons.access_time,
                      size: 12,
                      color: isPaid ? AppTheme.secondaryColor : AppTheme.warningColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPaid ? 'PAID' : 'PENDING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isPaid ? AppTheme.secondaryColor : AppTheme.warningColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RENT AMOUNT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatCurrency(unit.rentAmount)} / yr',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isPaid ? 'NEXT DUE' : 'DUE DATE',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unit.nextDueDate,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPaid ? AppTheme.primaryColor : AppTheme.warningColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
