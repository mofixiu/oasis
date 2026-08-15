import '../models/property.dart';

/// Abstract interface for the Discover service.
abstract class IDiscoverService {
  Future<List<Property>> getProperties();
}

/// Mock implementation of the Discover service.
/// Returns realistic dummy data for the property listings.
class MockDiscoverService implements IDiscoverService {
  @override
  Future<List<Property>> getProperties() async {
    // Simulate network delay as per project rules
    await Future.delayed(const Duration(seconds: 2));

    return [
      const Property(
        id: '1',
        title: '2-Bedroom, Lekki Phase 1',
        location: 'Lekki, Lagos, Nigeria',
        price: 4500000,
        imageUrl: 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=800&q=80',
        bedrooms: 2,
        bathrooms: 2,
        isVerified: true,
      ),
      const Property(
        id: '2',
        title: 'Luxury Studio, Victoria Island',
        location: 'VI, Lagos, Nigeria',
        price: 2800000,
        imageUrl: 'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&w=800&q=80',
        bedrooms: 1,
        bathrooms: 1,
        isVerified: true,
      ),
      const Property(
        id: '3',
        title: 'Executive Penthouse, Ikoyi',
        location: 'Old Ikoyi, Lagos',
        price: 12000000,
        imageUrl: 'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80',
        bedrooms: 4,
        bathrooms: 5,
        isVerified: true,
      ),
      const Property(
        id: '4',
        title: 'Cozy 1-BR, Gbagada Phase 2',
        location: 'Gbagada, Lagos',
        price: 1500000,
        imageUrl: 'https://images.unsplash.com/photo-1493809842364-78817add7ffb?auto=format&fit=crop&w=800&q=80',
        bedrooms: 1,
        bathrooms: 1,
        isVerified: true,
      ),
    ];
  }
}
