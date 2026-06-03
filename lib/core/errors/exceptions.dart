import 'failures.dart';

abstract class AppException implements Exception {
  final String message;
  const AppException(this.message);
  Failure get toFailure;
}

class UnknownException extends AppException {
  const UnknownException(super.message);

  @override
  Failure get toFailure => UnknownFailure(message);
}

class NetworkException extends AppException {
  const NetworkException(super.message);

  @override
  Failure get toFailure => NetworkFailure(message);
}

class ServerException extends AppException {
  const ServerException(super.message);

  @override
  Failure get toFailure => ServerFailure(message);
}

class DiscoveryException extends AppException {
  const DiscoveryException(super.message);

  @override
  Failure get toFailure => DiscoveryFailure(message);
}

class ClientException extends AppException {
  const ClientException(super.message);

  @override
  Failure get toFailure => ClientFailure(message);
}
