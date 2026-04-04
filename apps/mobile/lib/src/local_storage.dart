import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_local_storage_stub.dart'
    if (dart.library.html) 'browser_local_storage_web.dart'
    as browser_storage;

final Map<String, String> _memoryFallbackStorage = <String, String>{};

Future<String?> loadStoredString(String key) async {
  if (kIsWeb) {
    return browser_storage.browserLocalStorageGetString(key);
  }

  try {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  } on MissingPluginException {
    return _memoryFallbackStorage[key];
  }
}

Future<void> saveStoredString(String key, String value) async {
  if (kIsWeb) {
    browser_storage.browserLocalStorageSetString(key, value);
    return;
  }

  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, value);
  } on MissingPluginException {
    _memoryFallbackStorage[key] = value;
  }
}

Future<void> removeStoredString(String key) async {
  if (kIsWeb) {
    browser_storage.browserLocalStorageRemove(key);
    return;
  }

  try {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  } on MissingPluginException {
    _memoryFallbackStorage.remove(key);
  }
}

@visibleForTesting
void debugResetStoredStringFallback() {
  _memoryFallbackStorage.clear();
}
