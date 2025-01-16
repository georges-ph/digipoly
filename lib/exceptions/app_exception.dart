class AppException implements Exception {
  final String message;

  AppException([this.message = "Something went wrong"]);
}
