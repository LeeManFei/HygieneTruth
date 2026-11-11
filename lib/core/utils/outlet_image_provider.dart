import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/painting.dart';

/// Read the image formats stored by restaurant creation without changing callers' layout.
ImageProvider outletImageProvider(String source) {
  final value = source.trim();
  if (value.startsWith('data:image/')) {
    try {
      return MemoryImage(UriData.parse(value).contentAsBytes());
    } on FormatException {
      return MemoryImage(Uint8List(0));
    }
  }
  if (value.startsWith('assets/')) return AssetImage(value);
  if (value.startsWith('http://') || value.startsWith('https://')) return NetworkImage(value);
  return FileImage(File(value.startsWith('file:') ? Uri.parse(value).toFilePath() : value));
}
