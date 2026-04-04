// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

String? browserLocalStorageGetString(String key) =>
    html.window.localStorage[key];

void browserLocalStorageSetString(String key, String value) {
  html.window.localStorage[key] = value;
}

void browserLocalStorageRemove(String key) {
  html.window.localStorage.remove(key);
}
