import 'dart:async';
import 'dart:convert';

import 'package:http/browser_client.dart' as browser_http;

browser_http.BrowserClient getClient() {
  return browser_http.BrowserClient();
}