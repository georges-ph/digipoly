abstract class Failure {
  final String message;
  const Failure(this.message);
}

class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class DiscoveryFailure extends Failure {
  const DiscoveryFailure(super.message);
}
