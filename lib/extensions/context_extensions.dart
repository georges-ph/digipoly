import 'package:flutter/material.dart';

extension ContextExtensions on BuildContext {
  void showSnackBar(SnackBar snackBar) {
    ScaffoldMessenger.of(this).showSnackBar(snackBar);
  }

  void to(Widget destination) {
    Navigator.push(this, MaterialPageRoute(builder: (_) => destination));
  }
}
