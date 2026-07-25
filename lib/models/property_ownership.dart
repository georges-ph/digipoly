/// Who owns a property in a running game, and how built-up it is.
/// Lives in game state (not on the board template, which is shared data).
class PropertyOwnership {
  const PropertyOwnership({
    required this.propertyId,
    required this.ownerId,
    this.houses = 0,
    this.mortgaged = false,
  });

  final String propertyId;
  final String ownerId;

  /// 0..4 houses; 5 means hotel. Only meaningful for streets.
  final int houses;

  /// Mortgaged to the bank: the owner took the mortgage value and the
  /// property collects no rent until the mortgage is lifted.
  final bool mortgaged;

  static const int hotel = 5;

  Map<String, dynamic> toJson() => {
        'propertyId': propertyId,
        'ownerId': ownerId,
        'houses': houses,
        'mortgaged': mortgaged,
      };

  factory PropertyOwnership.fromJson(Map<String, dynamic> json) =>
      PropertyOwnership(
        propertyId: json['propertyId'] as String,
        ownerId: json['ownerId'] as String,
        houses: json['houses'] as int? ?? 0,
        mortgaged: json['mortgaged'] as bool? ?? false,
      );

  PropertyOwnership copyWith({String? ownerId, int? houses, bool? mortgaged}) =>
      PropertyOwnership(
        propertyId: propertyId,
        ownerId: ownerId ?? this.ownerId,
        houses: houses ?? this.houses,
        mortgaged: mortgaged ?? this.mortgaged,
      );
}
