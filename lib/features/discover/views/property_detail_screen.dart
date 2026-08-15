import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/property.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_toast.dart';

/// A premium, highly interactive Property Detail Screen for Landa OS.
/// Features a Hero image header, a specifications amenities grid,
/// a custom vertical 5-step Landa verification timeline, and a sticky bottom bar.
class PropertyDetailScreen extends StatefulWidget {
  final Property property;

  const PropertyDetailScreen({super.key, required this.property});

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  bool _isFavorite = false;

  // Helper method to format currency
  String _formatCurrency(double amount) {
    final currencyFormatter = NumberFormat.compactCurrency(
      symbol: '₦',
      decimalDigits: 1,
      locale: 'en_NG',
    );
    return currencyFormatter.format(amount);
  }

  // Generates custom realistic descriptions based on property properties
  String _getPropertyDescription() {
    return 'Located in the most sought-after precinct of ${widget.property.location}, this exceptional ${widget.property.bedrooms}-bedroom property represents the pinnacle of premium residential rentals in Nigeria.\n\nVerified directly by Landa’s institutional audit team, this home offers robust smart security, 24/7 serviced power weight multipliers, fully upgraded AC fixtures, and high-end finished materials. Perfect for corporate executives and discerning modern families seeking a secure, fraud-free tenancy.';
  }

  @override
  Widget build(BuildContext context) {
    final property = widget.property;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      body: Stack(
        children: [
          // 1. Main scrollable details view
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(
              bottom: 110,
            ), // Bottom padding for sticky navbar
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1.1 Hero Image Header
                Stack(
                  children: [
                    Hero(
                      tag: 'property_${property.id}',
                      child: Image.network(
                        property.imageUrl,
                        height: 380,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Gradient overlay to protect the top header buttons
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Floating Landa Verified Badge
                    if (property.isVerified)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                Icons.verified,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'LANDA VERIFIED',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // 1.2 Property Description & Stats Section
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Subtitle/Location tag
                      Text(
                        property.location.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.actionColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Title
                      Text(
                        property.title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Price & Pricing Info Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _formatCurrency(property.price),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryColor,
                              letterSpacing: -1,
                            ),
                          ),
                          const Text(
                            '/year',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          // Escrow Protected Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F1FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  color: AppTheme.actionColor,
                                  size: 12,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'ESCROW SECURE',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.actionColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // 1.3 Specs Amenities Grid
                      const Text(
                        'PROPERTY SPECIFICATIONS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 2.3,
                        children: [
                          _buildSpecCard(
                            Icons.king_bed_rounded,
                            '${property.bedrooms} Bedrooms',
                            'Fully Serviced',
                          ),
                          _buildSpecCard(
                            Icons.bathtub_rounded,
                            '${property.bathrooms} Bathrooms',
                            'Premium Fittings',
                          ),
                          _buildSpecCard(
                            Icons.electric_bolt_rounded,
                            '24/7 Power',
                            '1.5 Weight Mult.',
                          ),
                          _buildSpecCard(
                            Icons.verified_user_rounded,
                            'Biometric Lock',
                            'Landa Monitored',
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // 1.4 Detailed Text Description
                      const Text(
                        'ABOUT THIS RESIDENCE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _getPropertyDescription(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 1.5 Landa Escrow 5-Step Verification Timeline
                      const Text(
                        'LANDA SECURE VERIFICATION TIMELINE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildTimelineItem(
                        step: '01',
                        title: 'Ownership & Identity Verified',
                        description:
                            'Land Registry title deeds and biometric identity checked for verified corporate transparency.',
                        isFirst: true,
                      ),
                      _buildTimelineItem(
                        step: '02',
                        title: 'Rigorous 5-Step Physical Audit',
                        description:
                            'Full inspection of appliance weight multipliers, plumbing, utility metrics, and foundations.',
                      ),
                      _buildTimelineItem(
                        step: '03',
                        title: 'Escrow Account Activated',
                        description:
                            'Tenancy funds protected in secure Landa Escrow until legal signatures and handover matches.',
                      ),
                      _buildTimelineItem(
                        step: '04',
                        title: 'Digital Tenancy Framework Ready',
                        description:
                            'Institutional-grade encryption secure digital contract formatted and prepared for signature.',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Custom Glassmorphic Sticky Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                    ),

                    // Share & Favorite Buttons
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            LandaToast.info(
                              context,
                              'Listing link copied to clipboard',
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.ios_share_rounded,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isFavorite = !_isFavorite;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_outline_rounded,
                              color: _isFavorite
                                  ? Colors.red
                                  : AppTheme.primaryColor,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Sticky Bottom Action Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Contact Agent Button
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        LandaToast.info(
                          context,
                          'Connecting to a Landa OS verified representative...',
                        );
                      },
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Contact Agent'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: const BorderSide(
                          color: AppTheme.primaryColor,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Apply to Rent Button
                  Expanded(
                    flex: 1,
                    child: ElevatedButton(
                      onPressed: () => _showApplyEscrowModal(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Apply to Rent',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Specs Card Helper ---
  Widget _buildSpecCard(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Icon(icon, color: AppTheme.actionColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Vertical Timeline Item Helper ---
  Widget _buildTimelineItem({
    required String step,
    required String title,
    required String description,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step Circle and vertical drawing line
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5), // light emerald green
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    step,
                    style: const TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1.5, color: const Color(0xFFE2E8F0)),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0.0 : 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.secondaryColor,
                        size: 14,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Secure Application Modal Sheet ---
  void _showApplyEscrowModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pull-down handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Row(
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    color: AppTheme.actionColor,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Landa Secure Escrow',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'To secure this property, Landa OS sets up a protected escrow account. Your rental payment is safely kept by Landa until legal keys are certified.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.profileColor,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              // Transaction Overview details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  children: [
                    _buildModalOverviewRow(
                      'Yearly Rent',
                      _formatCurrency(widget.property.price),
                    ),
                    const SizedBox(height: 10),
                    _buildModalOverviewRow(
                      'Verification Escrow Audit',
                      '₦10,000',
                    ),
                    const SizedBox(height: 10),
                    _buildModalOverviewRow(
                      'Refundable Security Deposit',
                      '₦250,000',
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Estimated Setup Fee',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        Text(
                          _formatCurrency(widget.property.price + 260000),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Action buttons in modal
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel Request'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        LandaToast.success(
                          context,
                          'Secure Escrow initialized! Tenancy Application generated.',
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.actionColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Initialize Setup'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalOverviewRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
