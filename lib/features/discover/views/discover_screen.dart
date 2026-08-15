import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/discover_controller.dart';
import 'widgets/property_card.dart';
import '../../profile/views/profile_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch properties on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiscoverController>().fetchProperties();
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        title: Image.asset('assets/images/newlogonobackground.png', height: 40),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                radius: 18,
                backgroundImage: const AssetImage(
                  'assets/images/profile_avatar.png',
                ),
                backgroundColor: Colors.grey.shade300,
              ),
            ),
          ),
        ],
      ),
      body: Consumer<DiscoverController>(
        builder: (context, controller, child) {
          return RefreshIndicator(
            onRefresh: controller.fetchProperties,
            child: CustomScrollView(
              slivers: [
                // Search Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Column(
                      children: [
                        // Search Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceColor(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.borderColor(context),
                            ),
                          ),
                          child: TextField(
                            style: TextStyle(
                              color: AppTheme.profileTextColor(context),
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search areas, property types...',
                              border: InputBorder.none,
                              icon: Icon(
                                Icons.search,
                                color: AppTheme.mutedTextColor(context),
                              ),
                              hintStyle: TextStyle(
                                color: AppTheme.mutedTextColor(context),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Filter and Search Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.tune, size: 18),
                                label: const Text('Filters'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryColor,
                                  side: BorderSide(
                                    color: AppTheme.borderColor(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.actionColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text(
                                  'Search',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Verification Banner
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successSurfaceColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.verified_user_outlined,
                            color: AppTheme.successColor,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'ALL LISTINGS ARE LANDA-VERIFIED FOR FRAUD PROTECTION',
                              style: TextStyle(
                                color: AppTheme.successColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Property List
                if (controller.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (controller.errorMessage != null)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        controller.errorMessage!,
                        style: TextStyle(color: secondaryTextColor),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        return PropertyCard(
                          property: controller.properties[index],
                        );
                      }, childCount: controller.properties.length),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
