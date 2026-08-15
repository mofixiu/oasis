
/// Represents a property listing in Landa OS.
class Property {
  final String id;
  final String title;
  final String location;
  final double price;
  final String imageUrl;
  final int bedrooms;
  final int bathrooms;
  final bool isVerified;

  const Property({
    required this.id,
    required this.title,
    required this.location,
    required this.price,
    required this.imageUrl,
    required this.bedrooms,
    required this.bathrooms,
    this.isVerified = true,
  });
}
