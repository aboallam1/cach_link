import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data'; // added
import 'package:cashlink/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  String? _gender;
  File? _idImage;
  File? _userImage;
  XFile? _idImageWeb; // Add for web (kept for compatibility)
  XFile? _userImageWeb; // Add for web (kept for compatibility)
  Uint8List? _idImageBytesWeb; // NEW: bytes for web preview
  Uint8List? _userImageBytesWeb; // NEW: bytes for web preview
  String? _idImageUrl;
  String? _userImageUrl;
  bool _uploading = false;
  int _selectedIndex = 1; // Profile tab

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      final data = doc.data()!;
      _nameController.text = data['name'] ?? '';
      _gender = data['gender'];
      _userImageUrl = data['userImageUrl'];
      _idImageUrl = data['idImageUrl'];
      setState(() {});
    }
  }

  Future<void> _pickImage(bool isUserImage) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      if (kIsWeb) {
        // Read bytes for web preview
        final bytes = await picked.readAsBytes();
        setState(() {
          if (isUserImage) {
            _userImageBytesWeb = bytes;
            _userImageWeb = picked;
            _userImage = null;
          } else {
            _idImageBytesWeb = bytes;
            _idImageWeb = picked;
            _idImage = null;
          }
        });
      } else {
        setState(() {
          if (isUserImage) {
            _userImage = File(picked.path);
            _userImageWeb = null;
            _userImageBytesWeb = null;
          } else {
            _idImage = File(picked.path);
            _idImageWeb = null;
            _idImageBytesWeb = null;
          }
        });
      }
    }
  }

  // Placeholder for upload logic. You must implement actual upload to Firebase Storage.
  Future<String?> _uploadImage(File imageFile, String path) async {
    // On web, File operations are not supported, so skip or use picked.path as a URL if you have a web upload solution.
    if (kIsWeb) return null;
    // TODO: Implement upload to Firebase Storage and return the download URL for mobile/desktop.
    return null;
  }

  Future<void> _submitProfile() async {
    if (_nameController.text.isEmpty || _gender == null) return;
    setState(() => _uploading = true);
    final user = FirebaseAuth.instance.currentUser!;
    String? userImageUrl = _userImageUrl;
    String? idImageUrl = _idImageUrl;

    // Upload images if picked
    if (_userImage != null) {
      userImageUrl = await _uploadImage(_userImage!, 'users/${user.uid}/user.jpg');
    }
    if (_idImage != null) {
      idImageUrl = await _uploadImage(_idImage!, 'users/${user.uid}/id.jpg');
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'userId': user.uid,
      'name': _nameController.text,
      'gender': _gender,
      'phone': user.phoneNumber,
      'rating': 5.0,
      'KYC_verified': true,
      'userImageUrl': userImageUrl,
      'idImageUrl': idImageUrl,
    }, SetOptions(merge: true));
    setState(() => _uploading = false);
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else if (index == 1) {
      // Already on Profile
    } else if (index == 2) {
      Navigator.of(context).pushReplacementNamed('/history');
    } else if (index == 3) {
      Navigator.of(context).pushReplacementNamed('/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    // Fix user image widget for web and mobile
    Widget userImageWidget;
    if (kIsWeb && _userImageBytesWeb != null) {
      // Use memory bytes for reliable web preview
      userImageWidget = ClipOval(
        child: SizedBox(
          width: 96,
          height: 96,
          child: Image.memory(
            _userImageBytesWeb!,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(Icons.person, size: 60, color: theme.primaryColor);
            },
          ),
        ),
      );
    } else if (kIsWeb && _userImageWeb != null && _userImageBytesWeb == null) {
      // fallback if bytes not available
      userImageWidget = ClipOval(
        child: SizedBox(
          width: 96,
          height: 96,
          child: Image.network(
            _userImageWeb!.path,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(Icons.person, size: 60, color: theme.primaryColor);
            },
          ),
        ),
      );
    } else if (!kIsWeb && _userImage != null) {
      userImageWidget = CircleAvatar(
        radius: 48,
        backgroundImage: FileImage(_userImage!),
      );
    } else if (_userImageUrl != null && _userImageUrl!.isNotEmpty) {
      userImageWidget = CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(_userImageUrl!),
        onBackgroundImageError: (exception, stackTrace) {
          debugPrint('Error loading user image: $exception');
        },
      );
    } else {
      userImageWidget = Icon(Icons.person, size: 60, color: theme.primaryColor);
    }

    // Fix ID image widget for web and mobile
    Widget? idImageWidget;
    if (kIsWeb && _idImageBytesWeb != null) {
      idImageWidget = Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            _idImageBytesWeb!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                child: const Icon(Icons.error, size: 40, color: Colors.red),
              );
            },
          ),
        ),
      );
    } else if (kIsWeb && _idImageWeb != null && _idImageBytesWeb == null) {
      idImageWidget = Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            _idImageWeb!.path,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                child: const Icon(Icons.error, size: 40, color: Colors.red),
              );
            },
          ),
        ),
      );
    } else if (!kIsWeb && _idImage != null) {
      idImageWidget = Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            _idImage!,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (_idImageUrl != null && _idImageUrl!.isNotEmpty) {
      idImageWidget = Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            _idImageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                child: const Icon(Icons.error, size: 40, color: Colors.red),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        title: Text(loc.profile),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // User image picker with better web handling
            GestureDetector(
              onTap: () => _pickImage(true),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primaryColor.withOpacity(0.1),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3), width: 2),
                ),
                child: userImageWidget,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _pickImage(true),
              icon: const Icon(Icons.upload),
              label: Text(loc.locale.languageCode == 'ar' ? 'تحميل صورة المستخدم' : 'Upload User Photo'),
            ),
            const SizedBox(height: 12),
            Text(
              loc.profile,
              style: theme.textTheme.titleLarge!.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: loc.name,
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _gender,
                      items: [
                        DropdownMenuItem(value: 'Male', child: Text(loc.male)),
                        DropdownMenuItem(value: 'Female', child: Text(loc.female)),
                      ],
                      onChanged: (v) => setState(() => _gender = v),
                      decoration: InputDecoration(
                        labelText: loc.gender,
                        prefixIcon: const Icon(Icons.wc),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ID image picker with better preview
                    OutlinedButton.icon(
                      onPressed: () => _pickImage(false),
                      icon: const Icon(Icons.upload),
                      label: Text(
                        (_idImage == null && (_idImageUrl == null || _idImageUrl!.isEmpty))
                            ? (loc.locale.languageCode == 'ar' ? 'تحميل صورة الهوية' : 'Upload ID Photo')
                            : (loc.locale.languageCode == 'ar' ? 'تغيير صورة الهوية' : 'Change ID Photo'),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (idImageWidget != null) ...[
                      const SizedBox(height: 16),
                      idImageWidget,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            _uploading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submitProfile,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      loc.save,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
          ],
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          return BottomNavigationBar(
            currentIndex: _selectedIndex,
            selectedItemColor: const Color(0xFFE53935),
            unselectedItemColor: Colors.grey,
            onTap: _onNavTap,
            items: <BottomNavigationBarItem>[
              BottomNavigationBarItem(icon: const Icon(Icons.home), label: loc.home),
              BottomNavigationBarItem(icon: const Icon(Icons.person), label: loc.profile),
              BottomNavigationBarItem(icon: const Icon(Icons.history), label: loc.history),
              BottomNavigationBarItem(icon: const Icon(Icons.settings), label: loc.settings),
            ],
          );
        },
      ),
    );
  }
}
