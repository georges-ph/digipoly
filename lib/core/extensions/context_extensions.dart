import 'package:flutter/material.dart';

extension ContextExtensions on BuildContext {
  void showSnackBar(SnackBar snackBar) {
    ScaffoldMessenger.of(this)
      ..clearSnackBars()
      ..showSnackBar(snackBar);
  }

  void push(Widget destination) {
    Navigator.of(this).push(MaterialPageRoute(builder: (_) => destination));
  }
}
