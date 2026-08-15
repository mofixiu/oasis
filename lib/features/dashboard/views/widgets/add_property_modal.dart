import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../../properties/controllers/landlord_controller.dart';
import '../../../properties/views/widgets/property_location_picker.dart';

class AddPropertyModal extends StatefulWidget {
  const AddPropertyModal({super.key});

  @override
  State<AddPropertyModal> createState() => _AddPropertyModalState();
}

class _AddPropertyModalState extends State<AddPropertyModal> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: 'Lagos');
  final _stateCtrl = TextEditingController(text: 'Lagos');
  final _picker = ImagePicker();
  final List<File> _photos = [];
  File? _verificationVideo;
  File? _deed;
  LatLng? _pin;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked.isNotEmpty && mounted) {
          setState(
            () => _photos.addAll(picked.map((image) => File(image.path))),
          );
        }
      } else {
        final picked = await _picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked != null && mounted) {
          setState(() => _photos.add(File(picked.path)));
        }
      }
    } catch (error) {
      if (mounted) {
        LandaToast.error(context, 'Unable to select photos: $error');
      }
    }
  }

  Future<void> _recordVerificationVideo() async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
      if (video != null && mounted) {
        setState(() => _verificationVideo = File(video.path));
      }
    } catch (error) {
      if (mounted) {
        LandaToast.error(context, 'Unable to record video: $error');
      }
    }
  }

  Future<void> _pickDeed() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (result?.files.single.path != null && mounted) {
        setState(() => _deed = File(result!.files.single.path!));
      }
    } catch (error) {
      if (mounted) {
        LandaToast.error(context, 'Unable to select deed: $error');
      }
    }
  }

  Future<void> _submitProperty() async {
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    if (name.isEmpty || address.isEmpty) {
      LandaToast.error(context, 'Enter the property name and street address.');
      return;
    }
    if (_pin == null) {
      LandaToast.error(context, 'Drop a pin on the property location.');
      return;
    }
    if (_verificationVideo == null || _deed == null) {
      LandaToast.error(
        context,
        'A live verification video and deed are required.',
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final property = await context.read<LandlordController>().createProperty(
      name: name,
      address: address,
      city: _cityCtrl.text.trim(),
      state: _stateCtrl.text.trim(),
      latitude: _pin!.latitude,
      longitude: _pin!.longitude,
      photos: _photos,
      verificationVideo: _verificationVideo!,
      deedFile: _deed!,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (property == null) {
      LandaToast.error(
        context,
        context.read<LandlordController>().errorMessage ??
            'Could not submit property.',
      );
      return;
    }
    Navigator.pop(context);
    LandaToast.success(context, '${property.name} submitted for verification.');
  }

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: Colors.grey,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.add_location_alt_outlined,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Add verified property',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Pin the property, record a live walkthrough and attach proof of ownership.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Property name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Street address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _stateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'State',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            PropertyLocationPicker(onChanged: (pin) => _pin = pin),
            const SizedBox(height: 20),
            _sectionLabel('PROPERTY PHOTOS (OPTIONAL)'),
            const SizedBox(height: 8),
            if (_photos.isNotEmpty)
              SizedBox(
                height: 84,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _photos[index],
                            width: 84,
                            height: 84,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          child: IconButton(
                            icon: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                            onPressed: () =>
                                setState(() => _photos.removeAt(index)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhotos(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt, size: 17),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickPhotos(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library, size: 17),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionLabel('LIVE OWNERSHIP CHECK (REQUIRED)'),
            const SizedBox(height: 8),
            _EvidenceTile(
              icon: Icons.videocam_outlined,
              title: _verificationVideo == null
                  ? 'Record live walkthrough'
                  : 'Live walkthrough recorded',
              subtitle: _verificationVideo == null
                  ? 'Record up to 60 seconds showing the exterior and your presence.'
                  : _verificationVideo!.path.split('/').last,
              action: _verificationVideo == null ? 'Record' : 'Re-record',
              onTap: _recordVerificationVideo,
              complete: _verificationVideo != null,
            ),
            const SizedBox(height: 10),
            _EvidenceTile(
              icon: Icons.description_outlined,
              title: _deed == null
                  ? 'Attach deed or proof of ownership'
                  : 'Proof of ownership attached',
              subtitle: _deed == null
                  ? 'PDF, JPG or PNG. This is reviewed with the live video.'
                  : _deed!.path.split('/').last,
              action: _deed == null ? 'Attach' : 'Replace',
              onTap: _pickDeed,
              complete: _deed != null,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitProperty,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Submit property for review',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;
  final bool complete;

  const _EvidenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    required this.complete,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: complete ? Colors.green.shade50 : const Color(0xfff8f9fb),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: complete ? Colors.green.shade200 : Colors.grey.shade300,
      ),
    ),
    child: Row(
      children: [
        Icon(
          complete ? Icons.check_circle : icon,
          color: complete ? Colors.green : AppTheme.actionColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    ),
  );
}
