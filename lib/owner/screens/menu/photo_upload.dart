import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api.dart';
import '../../../core/theme.dart';

const _types = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif'};

/// Lets the owner pick (or shoot) a photo, uploads it, and returns its `/media/...` URL.
Future<String?> pickAndUploadPhoto(BuildContext context, ApiClient api) async {
  var source = ImageSource.gallery;
  if (!kIsWeb) {
    final picked = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AlsColors.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AlsColors.brown),
              title: Text('Choose from photos', style: AlsText.body(15, weight: FontWeight.w800)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AlsColors.brown),
              title: Text('Take a photo', style: AlsText.body(15, weight: FontWeight.w800)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return null;
    source = picked;
  }
  final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
  if (file == null) return null;
  final type = file.mimeType ?? _types[file.name.split('.').last.toLowerCase()];
  if (type == null || !_types.containsValue(type)) throw const ApiException(400, 'Use a JPG, PNG or WebP photo');
  final bytes = await file.readAsBytes();
  final res = await api.post('/owner/media', {'contentType': type, 'data': base64Encode(bytes)});
  return res['url'] as String;
}

Future<String?> askPhotoLink(BuildContext context, String? current) {
  final c = TextEditingController(text: current?.startsWith('http') == true ? current : '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Photo link', style: AlsText.display(20)),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: 'https://…/pizza.jpg'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Use photo')),
      ],
    ),
  );
}
