/// A live, table-held auction for an unowned property: anyone can start
/// one, everyone watching sees the current bid update live, and anyone can
/// close it — selling to the top bidder at their bid, or cancelling if
/// nobody bid. Lives only in server memory for the running session (not
/// persisted to the DB); a late-joining or reconnecting client picks up
/// whatever's still running via the snapshot.
class PropertyAuction {
  const PropertyAuction({
    required this.propertyId,
    required this.startedBy,
    this.currentBid = 0,
    this.currentBidderId,
  });

  final String propertyId;
  final String startedBy;

  /// 0 until the first bid is placed.
  final int currentBid;
  final String? currentBidderId;

  Map<String, dynamic> toJson() => {
        'propertyId': propertyId,
        'startedBy': startedBy,
        'currentBid': currentBid,
        if (currentBidderId != null) 'currentBidderId': currentBidderId,
      };

  factory PropertyAuction.fromJson(Map<String, dynamic> json) =>
      PropertyAuction(
        propertyId: json['propertyId'] as String,
        startedBy: json['startedBy'] as String,
        currentBid: json['currentBid'] as int? ?? 0,
        currentBidderId: json['currentBidderId'] as String?,
      );

  PropertyAuction copyWith({int? currentBid, String? currentBidderId}) =>
      PropertyAuction(
        propertyId: propertyId,
        startedBy: startedBy,
        currentBid: currentBid ?? this.currentBid,
        currentBidderId: currentBidderId ?? this.currentBidderId,
      );
}
