import '../core/errors/failures.dart';

abstract class Usecase<T, Params> {
  Future<(Failure?, T?)> call(Params params);
}

class NoParams {}
