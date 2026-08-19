import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_app_bar.dart';
import '../../../core/widgets/landa_toast.dart';

class FixesScreen extends StatefulWidget {
  const FixesScreen({super.key});

  @override
  State<FixesScreen> createState() => _FixesScreenState();
}

class _FixesScreenState extends State<FixesScreen> {
  final List<String> _categories = [
    'All Artisans',
    'Plumbing',
    'Electrical',
    'Carpentry',
    'HVAC',
    'Painting',
  ];
  String _selectedCategory = 'All Artisans';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: const LandaAppBar(),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // Header
              const Text(
                'Maintenance & Fixes',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Book verified, top-rated artisans for property repairs.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),

              // Category Chips
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected = category == _selectedCategory;
                    return ChoiceChip(
                      label: Text(category),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        }
                      },
                      selectedColor: AppTheme.primaryColor,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : AppTheme.primaryColor,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? AppTheme.primaryColor
                              : Colors.grey.shade300,
                        ),
                      ),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Featured Artisans Title
              const Text(
                'VERIFIED ARTISANS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),

              // Artisan Cards List
              _buildArtisanCard(
                name: 'Segun Adebayo',
                trade: 'Master Plumber',
                rating: 4.9,
                jobsDone: 142,
                rate: '₦15,000 / visit',
                imagePath: 'assets/images/artisan_segun.png',
                verified: true,
              ),
              const SizedBox(height: 16),
              _buildArtisanCard(
                name: 'Emeka Okafor',
                trade: 'Certified Electrician',
                rating: 4.8,
                jobsDone: 98,
                rate: '₦20,000 / visit',
                imagePath: 'assets/images/artisan_emeka.png',
                verified: true,
              ),
              const SizedBox(height: 16),
              _buildArtisanCard(
                name: 'Bisi Akande',
                trade: 'HVAC & AC Specialist',
                rating: 4.9,
                jobsDone: 215,
                rate: '₦18,000 / visit',
                imagePath: 'assets/images/artisan_bisi.png',
                verified: true,
              ),
              const SizedBox(height: 16),
              _buildArtisanCard(
                name: 'Tunde Bakare',
                trade: 'Carpenter & Woodwork',
                rating: 4.7,
                jobsDone: 84,
                rate: '₦12,000 / visit',
                imagePath: 'assets/images/artisan_tunde.png',
                verified: true,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtisanCard({
    required String name,
    required String trade,
    required double rating,
    required int jobsDone,
    required String rate,
    required String imagePath,
    required bool verified,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              imagePath,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified,
                        color: AppTheme.secondaryColor,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  trade,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$rating ($jobsDone jobs)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rate,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.actionColor,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  LandaToast.success(
                    context,
                    'Request sent to $name. They will contact you shortly.',
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Book',
                  style: TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
