enum DiscoveredRoomEvent { found, lost }

class DiscoveredRoom {
  final String name;
  final String address;
  final int port;
  final DiscoveredRoomEvent event;

  DiscoveredRoom({
    required this.name,
    required this.address,
    required this.port,
    required this.event,
  });

  @override
  String toString() {
    return 'DiscoveredRoom(name: $name, address: $address, port: $port, event: ${event.name})';
  }

  @override
  bool operator ==(covariant DiscoveredRoom other) {
    if (identical(this, other)) return true;
    return other.name == name && other.address == address && other.port == port;
  }

  @override
  int get hashCode {
    return name.hashCode ^ address.hashCode ^ port.hashCode;
  }
}
