/// A lightweight success-or-error type built on Dart records.
///
/// Exactly one of [value] or [error] is non-null.
typedef Result<T> = ({T? value, String? error});

Result<T> ok<T>(T value) => (value: value, error: null);

Result<T> err<T>(String error) => (value: null, error: error);

extension ResultX<T> on Result<T> {
  bool get isOk => error == null;

  /// The success value. Only call after checking [isOk].
  T get requireValue => value as T;
}
