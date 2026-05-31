import 'package:flutter/material.dart';

import 'app/main_app.dart';
import 'core/injectors/service_locator.dart';

void main() async {
  await ServiceLocator.init();
  runApp(const MainApp());
}
