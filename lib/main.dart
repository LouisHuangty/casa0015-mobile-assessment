import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeFirebaseSafely();
  runApp(const PetTrackerApp());
}

Future<void> _initializeFirebaseSafely() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    // Desktop platforms are not configured in this project yet.
  }
}

final ValueNotifier<bool> _isCompletingRegistration = ValueNotifier<bool>(
  false,
);
final ValueNotifier<UserProfile?> _pendingUserProfile =
    ValueNotifier<UserProfile?>(null);
const String _defaultLastSeenImageUrl =
    'https://firebasestorage.googleapis.com/v0/b/pet-tracker-app-f06a4.firebasestorage.app/o/7d8bbcb3aab048969febd75f6ccdf6ab.jpg?alt=media&token=ba49511e-62bb-436b-b145-624cbc5ca47b';

const String _defaultLastSeenEnvironment =
    'Near the garden path, next to the wooden fence.';
const Duration _bleSignalStaleTimeout = Duration(seconds: 8);
const Duration _captureUiWatchdogTimeout = Duration(seconds: 6);
const String _defaultCameraBaseUrl = 'http://192.168.3.53';

enum PetKind {
  dog('dog', 'Dog', '🐶'),
  cat('cat', 'Cat', '🐱');

  const PetKind(this.storageValue, this.label, this.emoji);

  final String storageValue;
  final String label;
  final String emoji;

  static PetKind fromStorageValue(String? value) {
    return switch (value) {
      'cat' => PetKind.cat,
      _ => PetKind.dog,
    };
  }
}

class PetTrackerApp extends StatelessWidget {
  const PetTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const shell = Color(0xFFF5F1E8);
    const ink = Color(0xFF1E2A2F);
    const accent = Color(0xFFB97745);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pet Beacon',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
          surface: shell,
        ),
        scaffoldBackgroundColor: shell,
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
      ),
      home: const AppGate(),
    );
  }
}

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isCompletingRegistration,
      builder: (context, isCompletingRegistration, child) {
        if (isCompletingRegistration) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!_supportsFirebaseAuthOnThisPlatform) {
          return const TrackerShell();
        }

        if (Firebase.apps.isEmpty) {
          return const AuthPage();
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasData) {
              return const TrackerShell();
            }

            return const AuthPage();
          },
        );
      },
    );
  }
}

bool get _supportsFirebaseAuthOnThisPlatform {
  if (kIsWeb) {
    return true;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => true,
    TargetPlatform.iOS => true,
    _ => false,
  };
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _petNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _isSubmitting = false;
  String? _errorText;
  PetKind _selectedPetKind = PetKind.dog;

  @override
  void dispose() {
    _nameController.dispose();
    _petNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E2A2F), Color(0xFFB97745)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pet Beacon',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            letterSpacing: 1.4,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Sign in to track your pet tag.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(
                                value: true,
                                label: Text('Login'),
                              ),
                              ButtonSegment<bool>(
                                value: false,
                                label: Text('Register'),
                              ),
                            ],
                            selected: {_isLogin},
                            onSelectionChanged: (selection) {
                              setState(() {
                                _isLogin = selection.first;
                                _errorText = null;
                              });
                            },
                          ),
                          const SizedBox(height: 24),
                          if (!_isLogin) ...[
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isLogin) {
                                  return null;
                                }
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _petNameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Pet name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isLogin) {
                                  return null;
                                }
                                if (value == null || value.trim().isEmpty) {
                                  return 'Enter your pet name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Pet type',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SegmentedButton<PetKind>(
                              segments: const [
                                ButtonSegment<PetKind>(
                                  value: PetKind.dog,
                                  label: Text('Dog'),
                                  icon: Text('🐶'),
                                ),
                                ButtonSegment<PetKind>(
                                  value: PetKind.cat,
                                  label: Text('Cat'),
                                  icon: Text('🐱'),
                                ),
                              ],
                              selected: {_selectedPetKind},
                              onSelectionChanged: (selection) {
                                setState(() {
                                  _selectedPetKind = selection.first;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: _isLogin
                                ? TextInputAction.done
                                : TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your password';
                              }
                              if (value.length < 6) {
                                return 'Use at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          if (!_isLogin) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (_isLogin) {
                                  return null;
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ],
                          if (_errorText != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorText!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : Text(_isLogin ? 'Login' : 'Create account'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isLogin
                                ? 'Use your registered Firebase email and password.'
                                : 'A Firestore profile will be created after registration.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      if (_isLogin) {
        final credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
        await _upsertUserProfileDocument(credential.user);
      } else {
        _isCompletingRegistration.value = true;
        _pendingUserProfile.value = UserProfile(
          displayName: _nameController.text.trim(),
          petName: _petNameController.text.trim(),
          petKind: _selectedPetKind,
          lastSeenImageUrl: _defaultLastSeenImageUrl,
          lastSeenEnvironment: _defaultLastSeenEnvironment,
          captureEvents: const [],
        );

        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        final user = credential.user;
        if (user != null) {
          await user.updateDisplayName(_nameController.text.trim());
          await _upsertUserProfileDocument(user);
          await user.reload();
        }
      }
    } on FirebaseAuthException catch (error) {
      setState(() {
        _errorText = _firebaseAuthMessage(error);
      });
    } on FirebaseException catch (error) {
      setState(() {
        _errorText = 'Firestore write failed: ${error.message ?? error.code}';
      });
    } catch (_) {
      setState(() {
        _errorText = 'Something went wrong. Please try again.';
      });
    } finally {
      _isCompletingRegistration.value = false;
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _upsertUserProfileDocument(User? user) async {
    if (user == null) {
      return;
    }

    final pendingProfile = _pendingUserProfile.value;
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final existingDoc = await docRef.get();
    final existingData = existingDoc.data() ?? <String, dynamic>{};

    await docRef.set({
      'email': user.email ?? _emailController.text.trim(),
      'displayName':
          pendingProfile?.displayName ??
          user.displayName ??
          (existingData['displayName'] as String?) ??
          '',
      'petName':
          pendingProfile?.petName ?? (existingData['petName'] as String?) ?? '',
      'petKind':
          (pendingProfile?.petKind ??
                  PetKind.fromStorageValue(existingData['petKind'] as String?))
              .storageValue,
      'lastSeenImageUrl':
          pendingProfile?.lastSeenImageUrl ??
          (existingData['lastSeenImageUrl'] as String?) ??
          _defaultLastSeenImageUrl,
      'lastSeenEnvironment':
          pendingProfile?.lastSeenEnvironment ??
          (existingData['lastSeenEnvironment'] as String?) ??
          _defaultLastSeenEnvironment,
      'captureEvents':
          pendingProfile?.captureEvents.map((event) => event.toMap()).toList() ??
          (existingData['captureEvents'] as List<dynamic>?) ??
          const [],
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': existingData['createdAt'] ?? FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

String _firebaseAuthMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'email-already-in-use':
      return 'This email is already registered.';
    case 'invalid-email':
      return 'That email address is invalid.';
    case 'weak-password':
      return 'Password is too weak.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'network-request-failed':
      return 'Network error. Check your connection.';
    default:
      return error.message ?? 'Authentication failed.';
  }
}

class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.petName,
    required this.petKind,
    required this.lastSeenImageUrl,
    required this.lastSeenEnvironment,
    required this.captureEvents,
  });

  final String displayName;
  final String petName;
  final PetKind petKind;
  final String lastSeenImageUrl;
  final String lastSeenEnvironment;
  final List<CaptureEvent> captureEvents;
}

class BleSelection {
  const BleSelection({
    required this.remoteId,
    required this.deviceName,
    required this.rssi,
    required this.connectable,
    required this.updatedAt,
  });

  final String remoteId;
  final String deviceName;
  final int rssi;
  final bool connectable;
  final DateTime updatedAt;
}

enum PetStatus {
  veryClose('Connected / Very Close', 'Pet is very close', Color(0xFF2D936C)),
  nearby('Nearby', 'Pet is nearby', Color(0xFF3F7CAC)),
  far('Far', 'Pet is far away', Color(0xFFC97C1A));

  const PetStatus(this.label, this.message, this.color);

  final String label;
  final String message;
  final Color color;
}

class PetSnapshot {
  const PetSnapshot({
    required this.petName,
    required this.status,
    required this.rssi,
    required this.lastSeenTime,
    required this.isConnected,
    required this.locationLabel,
    required this.beaconName,
    required this.uuid,
    required this.scanEnabled,
    required this.detectionCount,
  });

  final String petName;
  final PetStatus status;
  final int rssi;
  final String lastSeenTime;
  final bool isConnected;
  final String locationLabel;
  final String beaconName;
  final String uuid;
  final bool scanEnabled;
  final int detectionCount;

  PetSnapshot copyWith({
    String? petName,
    PetStatus? status,
    int? rssi,
    String? lastSeenTime,
    bool? isConnected,
    String? locationLabel,
    String? beaconName,
    String? uuid,
    bool? scanEnabled,
    int? detectionCount,
  }) {
    return PetSnapshot(
      petName: petName ?? this.petName,
      status: status ?? this.status,
      rssi: rssi ?? this.rssi,
      lastSeenTime: lastSeenTime ?? this.lastSeenTime,
      isConnected: isConnected ?? this.isConnected,
      locationLabel: locationLabel ?? this.locationLabel,
      beaconName: beaconName ?? this.beaconName,
      uuid: uuid ?? this.uuid,
      scanEnabled: scanEnabled ?? this.scanEnabled,
      detectionCount: detectionCount ?? this.detectionCount,
    );
  }
}

const List<PetSnapshot> _mockStates = [
  PetSnapshot(
    petName: 'Pet',
    status: PetStatus.veryClose,
    rssi: -49,
    lastSeenTime: '14:32:10',
    isConnected: true,
    locationLabel: 'Living room',
    beaconName: 'Pet Tag',
    uuid: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
    scanEnabled: true,
    detectionCount: 18,
  ),
  PetSnapshot(
    petName: 'Pet',
    status: PetStatus.nearby,
    rssi: -67,
    lastSeenTime: '14:31:42',
    isConnected: true,
    locationLabel: 'Hallway',
    beaconName: 'Pet Tag',
    uuid: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
    scanEnabled: true,
    detectionCount: 12,
  ),
  PetSnapshot(
    petName: 'Pet',
    status: PetStatus.far,
    rssi: -84,
    lastSeenTime: '14:30:05',
    isConnected: true,
    locationLabel: 'Garden gate',
    beaconName: 'Pet Tag',
    uuid: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
    scanEnabled: true,
    detectionCount: 5,
  ),
  PetSnapshot(
    petName: 'Pet',
    status: PetStatus.far,
    rssi: -92,
    lastSeenTime: '14:24:18',
    isConnected: true,
    locationLabel: 'Rear driveway',
    beaconName: 'Pet Tag',
    uuid: 'FDA50693-A4E2-4FB1-AFCF-C6EB07647825',
    scanEnabled: true,
    detectionCount: 2,
  ),
];

class TrackerShell extends StatefulWidget {
  const TrackerShell({super.key});

  @override
  State<TrackerShell> createState() => _TrackerShellState();
}

class _TrackerShellState extends State<TrackerShell> {
  int _currentTab = 0;
  int _selectedMockIndex = 1;
  double _rssiThreshold = -75;
  bool _isEnsuringProfile = false;
  bool _isCaptureRequestInFlight = false;
  bool _isManualCaptureRequestInFlight = false;
  bool _isCameraHealthCheckInFlight = false;
  bool _hasTriggeredFarCaptureInCurrentSession = false;
  bool _wasInAutoFarState = false;
  int _captureRequestId = 0;
  int? _activeCaptureRequestId;
  final List<int> _recentBleRssiValues = <int>[];
  PetStatus _lastStableBleStatus = PetStatus.nearby;
  bool? _isCameraOnline;
  String _cameraBaseUrl = _defaultCameraBaseUrl;
  String? _profileSyncError;
  String? _captureError;
  String? _cameraStatusMessage;
  String? _sessionLastSeenImageUrl;
  String? _sessionLastSeenEnvironment;
  List<CaptureEvent> _captureEvents = const [];
  BleSelection? _selectedBleDevice;
  Timer? _bleRefreshTimer;
  Timer? _captureWatchdogTimer;

  @override
  void initState() {
    super.initState();
    _ensureUserProfileDocument();
    unawaited(_checkCameraHealth());
    _bleRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _selectedBleDevice == null) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _bleRefreshTimer?.cancel();
    _captureWatchdogTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureUserProfileDocument();
  }

  @override
  Widget build(BuildContext context) {
    final user = _supportsFirebaseAuthOnThisPlatform && Firebase.apps.isNotEmpty
        ? FirebaseAuth.instance.currentUser
        : null;

    if (user == null) {
      return _buildTrackerScaffold(
        const UserProfile(
          displayName: '',
          petName: 'Pet',
          petKind: PetKind.dog,
          lastSeenImageUrl: _defaultLastSeenImageUrl,
          lastSeenEnvironment: _defaultLastSeenEnvironment,
          captureEvents: [],
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final pendingProfile = _pendingUserProfile.value;
        final profile = UserProfile(
          displayName:
              (data?['displayName'] as String?) ??
              pendingProfile?.displayName ??
              user.displayName ??
              '',
          petName:
              (data?['petName'] as String?) ??
              pendingProfile?.petName ??
              'Pet',
          petKind: PetKind.fromStorageValue(
            (data?['petKind'] as String?) ??
                pendingProfile?.petKind.storageValue,
          ),
          lastSeenImageUrl:
              (data?['lastSeenImageUrl'] as String?) ??
              pendingProfile?.lastSeenImageUrl ??
              _defaultLastSeenImageUrl,
          lastSeenEnvironment:
              (data?['lastSeenEnvironment'] as String?) ??
              pendingProfile?.lastSeenEnvironment ??
              _defaultLastSeenEnvironment,
          captureEvents: _captureEventsFromData(data?['captureEvents']),
        );

        if (data != null && _pendingUserProfile.value != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _pendingUserProfile.value = null;
          });
        }

        return _buildTrackerScaffold(
          profile,
          profileSyncError: _profileSyncError,
        );
      },
    );
  }

  void _selectScenario(int index) {
    setState(() {
      _selectedMockIndex = index;
    });
  }

  Future<void> _ensureUserProfileDocument() async {
    if (_isEnsuringProfile ||
        !_supportsFirebaseAuthOnThisPlatform ||
        Firebase.apps.isEmpty) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _isEnsuringProfile = true;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final existingDoc = await docRef.get();
      if (!existingDoc.exists) {
        await docRef.set({
          'email': user.email ?? '',
          'displayName': user.displayName ?? '',
          'petName': '',
          'petKind': PetKind.dog.storageValue,
          'lastSeenImageUrl': _defaultLastSeenImageUrl,
          'lastSeenEnvironment': _defaultLastSeenEnvironment,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        setState(() {
          _profileSyncError = null;
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _profileSyncError =
              'Profile sync failed: ${error.message ?? error.code}';
        });
      }
    } finally {
      _isEnsuringProfile = false;
    }
  }

  Widget _buildTrackerScaffold(
    UserProfile profile, {
    String? profileSyncError,
  }) {
    final displayPetName = _displayPetName(profile.petName);
    final snapshot = _selectedBleDevice != null
        ? _liveSnapshotFromBle(profile, _selectedBleDevice!)
        : _mockStates[_selectedMockIndex].copyWith(
            petName: displayPetName,
            beaconName: _beaconNameForPet(displayPetName),
            scanEnabled: _mockStates[_selectedMockIndex].isConnected,
          );
    final effectiveLastSeenImageUrl =
        _sessionLastSeenImageUrl ?? profile.lastSeenImageUrl;
    final effectiveLastSeenEnvironment =
        _sessionLastSeenEnvironment ?? profile.lastSeenEnvironment;
    final effectiveCaptureEvents = _mergedCaptureEvents(profile.captureEvents);
    final latestSuccessfulCapture = effectiveCaptureEvents.where((event) {
      return event.success;
    }).fold<CaptureEvent?>(null, (latest, event) {
      if (latest == null || event.timestamp.isAfter(latest.timestamp)) {
        return event;
      }
      return latest;
    });

    if (_selectedBleDevice != null) {
      _maybeTriggerFarCapture(profile, snapshot);
    }

    final pages = [
      HomePage(
        snapshot: snapshot,
        ownerName: profile.displayName,
        petKind: profile.petKind,
        profileSyncError: _mergeErrorMessages(profileSyncError, _captureError),
        lastSeenImageUrl: effectiveLastSeenImageUrl,
        latestCaptureEvent: latestSuccessfulCapture,
        selectedMockIndex: _selectedMockIndex,
        onScenarioSelected: (index) {
          _selectScenario(index);

          final selectedState = _mockStates[index];
          if (selectedState.status != PetStatus.far) {
            _hasTriggeredFarCaptureInCurrentSession = false;
          }
          if (_selectedBleDevice != null ||
              selectedState.status != PetStatus.far ||
              !_canTriggerFarCapture()) {
            return;
          }

          _hasTriggeredFarCaptureInCurrentSession = true;
          final simulatedSnapshot = selectedState.copyWith(
            petName: displayPetName,
            beaconName: _beaconNameForPet(displayPetName),
            scanEnabled: selectedState.isConnected,
          );
          unawaited(_triggerRaspberryPiCapture(profile, simulatedSnapshot));
        },
        isUsingLiveBle: _selectedBleDevice != null,
      ),
      HistoryPage(
        snapshot: snapshot,
        lastSeenImageUrl: effectiveLastSeenImageUrl,
        lastSeenEnvironment: effectiveLastSeenEnvironment,
        captureEvents: effectiveCaptureEvents,
      ),
      DevicePage(
        snapshot: snapshot,
        rssiThreshold: _rssiThreshold,
        raspberryPiBaseUrl: _cameraBaseUrl,
        isCaptureRequestInFlight: _isManualCaptureRequestInFlight,
        isCameraHealthCheckInFlight: _isCameraHealthCheckInFlight,
        isCameraOnline: _isCameraOnline,
        cameraStatusMessage: _cameraStatusMessage,
        captureError: _captureError,
        lastCapturedImageUrl: _sessionLastSeenImageUrl,
        onTriggerCameraTest: () {
          if (_isManualCaptureRequestInFlight) {
            return;
          }
          unawaited(
            _triggerRaspberryPiCapture(
              profile,
              snapshot,
              isManualTrigger: true,
            ),
          );
        },
        onCheckCameraHealth: () {
          unawaited(_detectCameraService());
        },
        onThresholdChanged: (value) {
          setState(() {
            _rssiThreshold = value;
          });
        },
      ),
      BleDebugPage(
        farThreshold: _rssiThreshold.round(),
        selectedDevice: _selectedBleDevice,
        onSelectedDeviceChanged: (selection) {
          setState(() {
            final previousRemoteId = _selectedBleDevice?.remoteId;
            _selectedBleDevice = selection;
            final nextRemoteId = selection?.remoteId;
            if (previousRemoteId != nextRemoteId) {
              _recentBleRssiValues.clear();
              _hasTriggeredFarCaptureInCurrentSession = false;
              _wasInAutoFarState = false;
              _lastStableBleStatus = PetStatus.nearby;
            }
          });
        },
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          if (_supportsFirebaseAuthOnThisPlatform)
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _currentTab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) {
          setState(() {
            _currentTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_toggle_off),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Device',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth_searching_outlined),
            selectedIcon: Icon(Icons.bluetooth_searching),
            label: 'BLE',
          ),
        ],
      ),
    );
  }

  String? _mergeErrorMessages(String? profileError, String? captureError) {
    if (profileError == null || profileError.isEmpty) {
      return captureError;
    }
    if (captureError == null || captureError.isEmpty) {
      return profileError;
    }
    return '$profileError\n$captureError';
  }

  void _maybeTriggerFarCapture(UserProfile profile, PetSnapshot snapshot) {
    if (snapshot.status != PetStatus.far) {
      _hasTriggeredFarCaptureInCurrentSession = false;
      _wasInAutoFarState = false;
      return;
    }

    if (_wasInAutoFarState || !_canTriggerFarCapture()) {
      return;
    }

    _wasInAutoFarState = true;
    _hasTriggeredFarCaptureInCurrentSession = true;
    unawaited(_triggerRaspberryPiCapture(profile, snapshot));
  }

  bool _canTriggerFarCapture() {
    if (_isCaptureRequestInFlight || _hasTriggeredFarCaptureInCurrentSession) {
      return false;
    }
    return true;
  }

  Future<void> _triggerRaspberryPiCapture(
    UserProfile profile,
    PetSnapshot snapshot,
    {bool isManualTrigger = false}
  ) async {
    String? deferredImageUrl;
    String? deferredEnvironment;
    bool shouldPersistCaptureEvents = false;
    final requestId = ++_captureRequestId;

    setState(() {
      _activeCaptureRequestId = requestId;
      _isCaptureRequestInFlight = true;
      if (isManualTrigger) {
        _isManualCaptureRequestInFlight = true;
      }
      _captureError = null;
      _cameraStatusMessage = 'Requesting a capture from the camera service...';
    });
    _captureWatchdogTimer?.cancel();
    _captureWatchdogTimer = Timer(_captureUiWatchdogTimeout, () {
      if (!mounted || _activeCaptureRequestId != requestId) {
        return;
      }
      setState(() {
        _activeCaptureRequestId = null;
        _isCaptureRequestInFlight = false;
        if (isManualTrigger) {
          _isManualCaptureRequestInFlight = false;
        }
        _captureError = 'Camera capture took too long. You can try again.';
        _cameraStatusMessage = 'Capture timed out locally. Try again.';
      });
    });

    try {
      final response = await http
          .get(Uri.parse('$_cameraBaseUrl/capture-meta'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        throw Exception('Capture request failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final imagePath = data['image_url'] as String?;
      final imageUrl = imagePath == null
          ? null
          : imagePath.startsWith('http')
          ? imagePath
          : '$_cameraBaseUrl$imagePath';

      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('Capture response did not include an image URL.');
      }

      final refreshedImageUrl = _withClientCacheBust(imageUrl);
      final environment =
          'BLE far event at ${snapshot.locationLabel} around ${snapshot.lastSeenTime}.';

      if (_activeCaptureRequestId != requestId) {
        return;
      }

      if (mounted) {
        setState(() {
          _sessionLastSeenImageUrl = refreshedImageUrl;
          _sessionLastSeenEnvironment = environment;
          _captureError = null;
          _isCameraOnline = true;
          _cameraStatusMessage = 'Last capture succeeded just now.';
          _captureEvents = [
            CaptureEvent(
              title: snapshot.status == PetStatus.far
                  ? 'BLE far capture saved'
                  : 'Manual camera test saved',
              detail:
                  '${snapshot.locationLabel} • ${snapshot.rssi} dBm • ${snapshot.lastSeenTime}',
              timestamp: DateTime.now(),
              success: true,
            ),
            ..._captureEvents,
          ];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              snapshot.status == PetStatus.far
                  ? 'BLE far capture succeeded.'
                  : 'Camera test capture succeeded.',
            ),
          ),
        );
      }

      deferredImageUrl = refreshedImageUrl;
      deferredEnvironment = environment;
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_activeCaptureRequestId != requestId) {
        return;
      }
      final message = error is TimeoutException
          ? 'Camera capture timed out. Check camera power and Wi-Fi.'
          : 'Camera capture failed: $error';
      setState(() {
        _captureError = message;
        _isCameraOnline = false;
        _cameraStatusMessage = message;
        _captureEvents = [
          CaptureEvent(
            title: snapshot.status == PetStatus.far
                ? 'BLE far capture failed'
                : 'Manual camera test failed',
            detail: message,
            timestamp: DateTime.now(),
            success: false,
          ),
          ..._captureEvents,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
      shouldPersistCaptureEvents = true;
    } finally {
      if (mounted && _activeCaptureRequestId == requestId) {
        _captureWatchdogTimer?.cancel();
        setState(() {
          _activeCaptureRequestId = null;
          _isCaptureRequestInFlight = false;
          if (isManualTrigger) {
            _isManualCaptureRequestInFlight = false;
          }
        });
      }
    }

    if (deferredImageUrl != null && deferredEnvironment != null) {
      unawaited(_saveLastSeenCapture(profile, deferredImageUrl, deferredEnvironment));
    } else if (shouldPersistCaptureEvents) {
      unawaited(_saveCaptureEvents(profile));
    }
  }

  Future<void> _saveLastSeenCapture(
    UserProfile profile,
    String imageUrl,
    String environment,
  ) async {
    if (!_supportsFirebaseAuthOnThisPlatform || Firebase.apps.isEmpty) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
          'displayName': profile.displayName,
          'petName': profile.petName,
          'petKind': profile.petKind.storageValue,
          'lastSeenImageUrl': imageUrl,
          'lastSeenEnvironment': environment,
          'captureEvents':
              _captureEvents.take(10).map((event) => event.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 5));
  }

  Future<void> _saveCaptureEvents(UserProfile profile) async {
    if (!_supportsFirebaseAuthOnThisPlatform || Firebase.apps.isEmpty) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
          'displayName': profile.displayName,
          'petName': profile.petName,
          'petKind': profile.petKind.storageValue,
          'captureEvents':
              _captureEvents.take(10).map((event) => event.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 5));
  }

  String _withClientCacheBust(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) {
      return '$imageUrl${imageUrl.contains('?') ? '&' : '?'}client_ts=${DateTime.now().millisecondsSinceEpoch}';
    }

    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'client_ts': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    ).toString();
  }

  List<CaptureEvent> _captureEventsFromData(dynamic rawValue) {
    if (rawValue is! List<dynamic>) {
      return const [];
    }

    return rawValue
        .whereType<Map<String, dynamic>>()
        .map(CaptureEvent.fromMap)
        .toList();
  }

  List<CaptureEvent> _mergedCaptureEvents(List<CaptureEvent> persistedEvents) {
    final merged = <CaptureEvent>[];
    final seenKeys = <String>{};

    for (final event in [..._captureEvents, ...persistedEvents]) {
      final key = '${event.timestamp.millisecondsSinceEpoch}-${event.title}';
      if (seenKeys.add(key)) {
        merged.add(event);
      }
    }

    return merged;
  }

  Future<void> _checkCameraHealth() async {
    if (_isCameraHealthCheckInFlight) {
      return;
    }

    if (mounted) {
      setState(() {
        _isCameraHealthCheckInFlight = true;
      });
    } else {
      _isCameraHealthCheckInFlight = true;
    }

    try {
      final data = await _probeCameraHealth(_cameraBaseUrl);
      final ip = data['ip'] as String?;
      final hostname = data['hostname'] as String?;
      final statusMessage =
          switch ((hostname, ip)) {
            (String h, String ipAddr) => 'Online at $h ($ipAddr)',
            (_, String ipAddr) => 'Online at $ipAddr',
            _ => 'Camera service is reachable.',
          };

      if (!mounted) {
        return;
      }
      setState(() {
        _isCameraOnline = true;
        _cameraStatusMessage = statusMessage;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCameraOnline = false;
        _cameraStatusMessage = 'Camera health check failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCameraHealthCheckInFlight = false;
        });
      } else {
        _isCameraHealthCheckInFlight = false;
      }
    }
  }

  Future<void> _detectCameraService() async {
    if (_isCameraHealthCheckInFlight) {
      return;
    }

    setState(() {
      _isCameraHealthCheckInFlight = true;
      _cameraStatusMessage = 'Detecting camera service...';
    });

    final currentUri = Uri.tryParse(_cameraBaseUrl);
    final currentHost = currentUri?.host ?? '';
    final candidates = <String>[
      _cameraBaseUrl,
      'http://timercam.local',
      'http://192.168.4.1',
      'http://192.168.3.53',
    ];

    if (currentHost.isNotEmpty) {
      final parts = currentHost.split('.');
      if (parts.length == 4) {
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (final suffix in [50, 51, 52, 53, 54, 55, 100]) {
          candidates.add('http://$prefix.$suffix');
        }
      }
    }

    final seen = <String>{};
    for (final candidate in candidates) {
      if (!seen.add(candidate)) {
        continue;
      }
      try {
        final data = await _probeCameraHealth(candidate);
        final ip = data['ip'] as String?;
        final resolvedBaseUrl = ip != null && ip.isNotEmpty
            ? 'http://$ip'
            : candidate;

        if (!mounted) {
          return;
        }
        setState(() {
          _cameraBaseUrl = resolvedBaseUrl;
          _isCameraOnline = true;
          _cameraStatusMessage = 'Camera service detected at $resolvedBaseUrl';
          _isCameraHealthCheckInFlight = false;
        });
        return;
      } catch (_) {
        continue;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isCameraOnline = false;
      _cameraStatusMessage = 'Could not detect a camera service on the local network.';
      _isCameraHealthCheckInFlight = false;
    });
  }

  Future<Map<String, dynamic>> _probeCameraHealth(String baseUrl) async {
    final response = await http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 3));

    if (response.statusCode != 200) {
      throw Exception('Health check failed: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  PetSnapshot _liveSnapshotFromBle(
    UserProfile profile,
    BleSelection selection,
  ) {
    final age = DateTime.now().difference(selection.updatedAt);
    final displayPetName = _displayPetName(profile.petName);
    final status = age > _bleSignalStaleTimeout
        ? PetStatus.far
        : _stableStatusFromRssi(selection.rssi);
    return PetSnapshot(
      petName: displayPetName,
      status: status,
      rssi: selection.rssi,
      lastSeenTime: _formatTime(selection.updatedAt),
      isConnected: age <= _bleSignalStaleTimeout,
      locationLabel: age > _bleSignalStaleTimeout
          ? 'Last BLE scan'
          : 'Live BLE scan',
      beaconName: selection.deviceName,
      uuid: selection.remoteId,
      scanEnabled: age <= _bleSignalStaleTimeout,
      detectionCount: 1,
    );
  }

  String _displayPetName(String petName) {
    final trimmedName = petName.trim();
    return trimmedName.isEmpty ? 'Pet' : trimmedName;
  }

  String _beaconNameForPet(String petName) {
    return '$petName Tag';
  }

  PetStatus _stableStatusFromRssi(int rssi) {
    _recentBleRssiValues.add(rssi);
    if (_recentBleRssiValues.length > 4) {
      _recentBleRssiValues.removeAt(0);
    }

    if (rssi >= -60) {
      _lastStableBleStatus = PetStatus.veryClose;
      return PetStatus.veryClose;
    }

    final threshold = _rssiThreshold.round();
    final farHits = _recentBleRssiValues.where((value) => value < threshold).length;
    if (farHits >= 3) {
      _lastStableBleStatus = PetStatus.far;
      return PetStatus.far;
    }

    if (rssi >= threshold) {
      _lastStableBleStatus = PetStatus.nearby;
      return PetStatus.nearby;
    }

    return _lastStableBleStatus;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.snapshot,
    required this.ownerName,
    required this.petKind,
    required this.profileSyncError,
    required this.lastSeenImageUrl,
    required this.latestCaptureEvent,
    required this.selectedMockIndex,
    required this.onScenarioSelected,
    required this.isUsingLiveBle,
  });

  final PetSnapshot snapshot;
  final String ownerName;
  final PetKind petKind;
  final String? profileSyncError;
  final String lastSeenImageUrl;
  final CaptureEvent? latestCaptureEvent;
  final int selectedMockIndex;
  final ValueChanged<int> onScenarioSelected;
  final bool isUsingLiveBle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleScenarioIndexes = <int>[];
    final seenStatuses = <PetStatus>{};
    for (var i = 0; i < _mockStates.length; i++) {
      if (seenStatuses.add(_mockStates[i].status)) {
        visibleScenarioIndexes.add(i);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Text(
          'Pet Beacon',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.black54,
            letterSpacing: 1.4,
          ),
        ),
        if (ownerName.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Owner: $ownerName',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (profileSyncError != null) ...[
          const SizedBox(height: 8),
          Text(
            profileSyncError!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.red.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${snapshot.petName}  ${petKind.emoji}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _SignalBadge(status: snapshot.status),
          ],
        ),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                snapshot.status.color,
                snapshot.status.color.withValues(alpha: 0.78),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.status.message,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Status: ${snapshot.status.label}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        label: 'Signal',
                        value: '${snapshot.rssi} dBm',
                        light: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricTile(
                        label: 'Updated',
                        value: snapshot.lastSeenTime,
                        light: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (latestCaptureEvent != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(
                  'Last Automatic Capture',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Triggered automatically when the BLE signal reaches Far.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  latestCaptureEvent!.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF2E7D32),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Captured automatically at ${latestCaptureEvent!.timestamp.hour.toString().padLeft(2, '0')}:${latestCaptureEvent!.timestamp.minute.toString().padLeft(2, '0')}:${latestCaptureEvent!.timestamp.second.toString().padLeft(2, '0')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  latestCaptureEvent!.detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black87,
                    height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.network(
                        key: ValueKey(lastSeenImageUrl),
                        lastSeenImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return ColoredBox(
                            color: const Color(0xFFF0ECE3),
                            child: Center(
                              child: Text(
                                'Capture preview unavailable',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Connection',
                value: snapshot.isConnected ? 'Scanning' : 'Offline',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: 'Location',
                value: snapshot.locationLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          isUsingLiveBle ? 'BLE Live Tracking' : 'Prototype states',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isUsingLiveBle
              ? 'Home is currently driven by the BLE device you selected on the BLE tab. Clear it there to return to mock states.'
              : 'Use these chips to simulate RSSI-driven state changes before BLE is connected.',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
        ),
        if (!isUsingLiveBle) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: visibleScenarioIndexes.map((index) {
              final state = _mockStates[index].status;
              final selected = index == selectedMockIndex;
              return ChoiceChip(
                label: Text(state.label),
                selected: selected,
                onSelected: (_) => onScenarioSelected(index),
                selectedColor: state.color.withValues(alpha: 0.18),
                side: BorderSide(
                  color: selected ? state.color : Colors.black12,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class CaptureEvent {
  const CaptureEvent({
    required this.title,
    required this.detail,
    required this.timestamp,
    required this.success,
  });

  factory CaptureEvent.fromMap(Map<String, dynamic> data) {
    final rawTimestamp = data['timestamp'];
    final timestamp =
        rawTimestamp is String
        ? DateTime.tryParse(rawTimestamp) ?? DateTime.now()
        : DateTime.now();

    return CaptureEvent(
      title: data['title'] as String? ?? 'Capture event',
      detail: data['detail'] as String? ?? '',
      timestamp: timestamp,
      success: data['success'] as bool? ?? false,
    );
  }

  final String title;
  final String detail;
  final DateTime timestamp;
  final bool success;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'detail': detail,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
    };
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.snapshot,
    required this.lastSeenImageUrl,
    required this.lastSeenEnvironment,
    required this.captureEvents,
  });

  final PetSnapshot snapshot;
  final String lastSeenImageUrl;
  final String lastSeenEnvironment;
  final List<CaptureEvent> captureEvents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Text(
          'Last Seen',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Capture Events',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (captureEvents.isEmpty)
                  Text(
                    'No capture events yet. Trigger a camera test or let BLE loss fire one automatically.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  )
                else
                  Column(
                    children: captureEvents.take(3).map((event) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CaptureEventTile(event: event),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.lastSeenTime,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Status before now: ${snapshot.status.label}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _HistoryRow(label: 'Location', value: snapshot.locationLabel),
                const SizedBox(height: 12),
                _HistoryRow(label: 'Raw RSSI', value: '${snapshot.rssi} dBm'),
                const SizedBox(height: 12),
                _HistoryRow(
                  label: 'Detection count',
                  value: '${snapshot.detectionCount}',
                ),
                const SizedBox(height: 12),
                _HistoryRow(label: 'Environment', value: lastSeenEnvironment),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Seen View',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Image.network(
                      key: ValueKey(lastSeenImageUrl),
                      lastSeenImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8E1D2),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 48,
                              color: Colors.black45,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This placeholder scene is stored as an image URL in Firestore. Later you can replace it with a real camera image.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo note',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This page is where GPS or a richer event log can be added later without changing the home screen.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CaptureEventTile extends StatelessWidget {
  const _CaptureEventTile({required this.event});

  final CaptureEvent event;

  @override
  Widget build(BuildContext context) {
    final color = event.success
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    final time =
        '${event.timestamp.hour.toString().padLeft(2, '0')}:'
        '${event.timestamp.minute.toString().padLeft(2, '0')}:'
        '${event.timestamp.second.toString().padLeft(2, '0')}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              event.success ? Icons.check_circle : Icons.error_outline,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.detail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black87,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DevicePage extends StatelessWidget {
  const DevicePage({
    super.key,
    required this.snapshot,
    required this.rssiThreshold,
    required this.raspberryPiBaseUrl,
    required this.isCaptureRequestInFlight,
    required this.isCameraHealthCheckInFlight,
    required this.isCameraOnline,
    required this.cameraStatusMessage,
    required this.captureError,
    required this.lastCapturedImageUrl,
    required this.onTriggerCameraTest,
    required this.onCheckCameraHealth,
    required this.onThresholdChanged,
  });

  final PetSnapshot snapshot;
  final double rssiThreshold;
  final String raspberryPiBaseUrl;
  final bool isCaptureRequestInFlight;
  final bool isCameraHealthCheckInFlight;
  final bool? isCameraOnline;
  final String? cameraStatusMessage;
  final String? captureError;
  final String? lastCapturedImageUrl;
  final VoidCallback onTriggerCameraTest;
  final VoidCallback onCheckCameraHealth;
  final ValueChanged<double> onThresholdChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cameraStatusColor = switch (isCameraOnline) {
      true => const Color(0xFF2E7D32),
      false => const Color(0xFFC62828),
      null => const Color(0xFF6D6A64),
    };
    final cameraStatusLabel = switch (isCameraOnline) {
      true => 'Online',
      false => 'Offline',
      null => 'Unknown',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Text(
          'Device Settings',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _HistoryRow(label: 'Device name', value: snapshot.beaconName),
                const SizedBox(height: 14),
                _HistoryRow(
                  label: 'Scan status',
                  value: snapshot.scanEnabled ? 'Enabled' : 'Disabled',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Camera Service',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current service endpoint',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Used for health checks, manual test capture, and BLE Far automatic capture.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        raspberryPiBaseUrl,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Chip(
                      label: const Text('In Use'),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: cameraStatusColor.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: Icon(
                        isCameraOnline == true
                            ? Icons.check_circle_outline
                            : isCameraOnline == false
                            ? Icons.error_outline
                            : Icons.help_outline,
                        size: 18,
                        color: cameraStatusColor,
                      ),
                      label: Text(cameraStatusLabel),
                    ),
                    OutlinedButton.icon(
                      onPressed: isCameraHealthCheckInFlight
                          ? null
                          : onCheckCameraHealth,
                      icon: isCameraHealthCheckInFlight
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_outlined),
                      label: const Text('Detect Camera Service'),
                    ),
                  ],
                ),
                if (cameraStatusMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    cameraStatusMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.black87,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: isCaptureRequestInFlight
                      ? null
                      : onTriggerCameraTest,
                  icon: isCaptureRequestInFlight
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    isCaptureRequestInFlight
                        ? 'Capturing...'
                        : 'Test Camera Capture',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Use this to verify the camera service before relying on automatic BLE Far triggers.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
                if (captureError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    captureError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFC62828),
                      height: 1.4,
                    ),
                  ),
                ] else if (lastCapturedImageUrl != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Last capture is ready in History and Last Seen.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF2E7D32),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RSSI threshold',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${rssiThreshold.round()} dBm',
                  style: theme.textTheme.headlineMedium,
                ),
                Slider(
                  value: rssiThreshold,
                  min: -95,
                  max: -40,
                  divisions: 11,
                  label: '${rssiThreshold.round()} dBm',
                  onChanged: onThresholdChanged,
                ),
                Text(
                  'Use this later to decide when Nearby should switch to Far.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BleDebugPage extends StatefulWidget {
  const BleDebugPage({
    super.key,
    required this.farThreshold,
    required this.selectedDevice,
    required this.onSelectedDeviceChanged,
  });

  final int farThreshold;
  final BleSelection? selectedDevice;
  final ValueChanged<BleSelection?> onSelectedDeviceChanged;

  @override
  State<BleDebugPage> createState() => _BleDebugPageState();
}

class _BleDebugPageState extends State<BleDebugPage> {
  late final StreamSubscription<BluetoothAdapterState>
  _adapterStateSubscription;
  late final StreamSubscription<bool> _isScanningSubscription;
  late final StreamSubscription<List<ScanResult>> _scanResultsSubscription;

  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  bool _isSupported = true;
  bool _isScanning = false;
  bool _autoRescanEnabled = false;
  String? _scanError;
  String? _selectedRemoteId;
  List<ScanResult> _scanResults = const [];
  final List<String> _deviceOrder = <String>[];
  Timer? _rescanTimer;

  @override
  void initState() {
    super.initState();
    _selectedRemoteId = widget.selectedDevice?.remoteId;
    _initializeBle();
  }

  @override
  void didUpdateWidget(covariant BleDebugPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDevice?.remoteId != oldWidget.selectedDevice?.remoteId) {
      _selectedRemoteId = widget.selectedDevice?.remoteId;
    }
  }

  Future<void> _initializeBle() async {
    try {
      _isSupported = await FlutterBluePlus.isSupported;

      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
        BluetoothAdapterState state,
      ) {
        if (!mounted) {
          return;
        }
        setState(() {
          _adapterState = state;
        });
      });

      _isScanningSubscription = FlutterBluePlus.isScanning.listen((bool state) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isScanning = state;
        });
        if (!state && _autoRescanEnabled && _selectedRemoteId != null) {
          _scheduleRescan();
        }
      });

      _scanResultsSubscription = FlutterBluePlus.scanResults.listen(
        (List<ScanResult> results) {
          if (!mounted) {
            return;
          }

          setState(() {
            for (final result in results) {
              final remoteId = result.device.remoteId.str;
              if (!_deviceOrder.contains(remoteId)) {
                _deviceOrder.add(remoteId);
              }
            }
            _scanResults = List<ScanResult>.from(results);
            _scanError = null;
            if (_selectedRemoteId != null &&
                !_scanResults.any(
                  (result) => result.device.remoteId.str == _selectedRemoteId,
                )) {
              // Keep tracking the last chosen device; it may simply be
              // temporarily out of range and should settle into Far.
            }
          });

          final selectedResult = _selectedResult;
          if (selectedResult != null) {
            widget.onSelectedDeviceChanged(
              _selectionFromResult(selectedResult),
            );
          }
        },
        onError: (Object error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _scanError = 'Scan error: $error';
          });
        },
      );

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _adapterStateSubscription = const Stream<BluetoothAdapterState>.empty()
          .listen((_) {});
      _isScanningSubscription = const Stream<bool>.empty().listen((_) {});
      _scanResultsSubscription = const Stream<List<ScanResult>>.empty().listen(
        (_) {},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isSupported = false;
        _scanError = 'Bluetooth is unavailable on this platform: $error';
      });
    }
  }

  @override
  void dispose() {
    _rescanTimer?.cancel();
    _adapterStateSubscription.cancel();
    _isScanningSubscription.cancel();
    _scanResultsSubscription.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      _rescanTimer?.cancel();
      setState(() {
        _scanError = null;
        _autoRescanEnabled = true;
      });
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 4),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _scanError = 'Could not start scan: $error';
      });
    }
  }

  Future<void> _stopScan() async {
    try {
      _rescanTimer?.cancel();
      _autoRescanEnabled = false;
      await FlutterBluePlus.stopScan();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _scanError = 'Could not stop scan: $error';
      });
    }
  }

  void _scheduleRescan() {
    _rescanTimer?.cancel();
    _rescanTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _isScanning || !_autoRescanEnabled) {
        return;
      }
      _startScan();
    });
  }

  ScanResult? get _selectedResult {
    if (_selectedRemoteId == null) {
      return null;
    }
    for (final result in _scanResults) {
      if (result.device.remoteId.str == _selectedRemoteId) {
        return result;
      }
    }
    return null;
  }

  List<ScanResult> get _visibleScanResults {
    final filtered = _scanResults.where((ScanResult result) {
      final isSelected = result.device.remoteId.str == _selectedRemoteId;
      final hasName = _deviceNameFor(result) != 'Unnamed BLE device';
      final isConnectable = result.advertisementData.connectable;
      return isSelected || hasName || isConnectable;
    }).toList();

    filtered.sort((a, b) {
      final aSelected = a.device.remoteId.str == _selectedRemoteId;
      final bSelected = b.device.remoteId.str == _selectedRemoteId;
      if (aSelected != bSelected) {
        return aSelected ? -1 : 1;
      }

      final aHasName = _deviceNameFor(a) != 'Unnamed BLE device';
      final bHasName = _deviceNameFor(b) != 'Unnamed BLE device';
      if (aHasName != bHasName) {
        return aHasName ? -1 : 1;
      }

      final aIndex = _deviceOrder.indexOf(a.device.remoteId.str);
      final bIndex = _deviceOrder.indexOf(b.device.remoteId.str);
      if (aIndex != bIndex) {
        return aIndex.compareTo(bIndex);
      }

      return _deviceNameFor(a).compareTo(_deviceNameFor(b));
    });

    return filtered;
  }

  PetStatus _statusFromRssi(int rssi) {
    if (rssi >= -60) {
      return PetStatus.veryClose;
    }
    if (rssi >= widget.farThreshold) {
      return PetStatus.nearby;
    }
    return PetStatus.far;
  }

  BleSelection _selectionFromResult(ScanResult result) {
    return BleSelection(
      remoteId: result.device.remoteId.str,
      deviceName: _deviceNameFor(result),
      rssi: result.rssi,
      connectable: result.advertisementData.connectable,
      updatedAt: DateTime.now(),
    );
  }

  String _deviceNameFor(ScanResult result) {
    final platformName = result.device.platformName.trim();
    if (platformName.isNotEmpty) {
      return platformName;
    }

    final advName = result.advertisementData.advName.trim();
    if (advName.isNotEmpty) {
      return advName;
    }

    return 'Unnamed BLE device';
  }

  String _adapterLabel(BluetoothAdapterState state) {
    return switch (state) {
      BluetoothAdapterState.on => 'Bluetooth On',
      BluetoothAdapterState.off => 'Bluetooth Off',
      BluetoothAdapterState.unavailable => 'Bluetooth Unsupported',
      BluetoothAdapterState.unauthorized => 'Permission Needed',
      BluetoothAdapterState.turningOn => 'Turning On',
      BluetoothAdapterState.turningOff => 'Turning Off',
      _ => 'Checking Bluetooth',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedResult = _selectedResult;
    final selectedStatus = selectedResult == null
        ? PetStatus.far
        : _statusFromRssi(selectedResult.rssi);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Text(
          'BLE Debug',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Use this page to verify that the phone can scan BLE devices, read RSSI, and map signal strength to pet states.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.black54,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SignalBadge(status: selectedStatus),
                    _InfoPill(label: _adapterLabel(_adapterState)),
                    _InfoPill(label: _isScanning ? 'Scanning' : 'Idle'),
                    _InfoPill(label: '${_visibleScanResults.length} shown'),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _isSupported && !_isScanning
                          ? _startScan
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Scan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isScanning ? _stopScan : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                    if (_selectedRemoteId != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _selectedRemoteId = null;
                            _autoRescanEnabled = false;
                          });
                          widget.onSelectedDeviceChanged(null);
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear Device'),
                      ),
                  ],
                ),
                if (_scanError != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _scanError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tracked Result',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedResult == null)
                  Text(
                    'Select a scanned device below to preview how its RSSI maps to Very Close / Nearby / Far.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  )
                else ...[
                  _HistoryRow(
                    label: 'Name',
                    value: _deviceNameFor(selectedResult),
                  ),
                  const SizedBox(height: 12),
                  _HistoryRow(
                    label: 'Device ID',
                    value: selectedResult.device.remoteId.str,
                  ),
                  const SizedBox(height: 12),
                  _HistoryRow(
                    label: 'RSSI',
                    value: '${selectedResult.rssi} dBm',
                  ),
                  const SizedBox(height: 12),
                  _HistoryRow(
                    label: 'Mapped status',
                    value: selectedStatus.label,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nearby BLE Devices',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (_visibleScanResults.isEmpty)
                  Text(
                    'No named or connectable BLE devices yet. Start a scan and keep a BLE device nearby.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  )
                else
                  ..._visibleScanResults.map(_buildScanTile),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanTile(ScanResult result) {
    final isSelected = result.device.remoteId.str == _selectedRemoteId;
    final status = _statusFromRssi(result.rssi);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: ValueKey(result.device.remoteId.str),
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          final selection = _selectionFromResult(result);
          setState(() {
            _selectedRemoteId = selection.remoteId;
            _autoRescanEnabled = true;
          });
          widget.onSelectedDeviceChanged(selection);
          if (!_isScanning) {
            _startScan();
          }
        },
        child: Ink(
          decoration: BoxDecoration(
            color: isSelected
                ? status.color.withValues(alpha: 0.12)
                : const Color(0xFFF7F4EE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? status.color : Colors.black12,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _deviceNameFor(result),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${result.rssi} dBm',
                      style: TextStyle(
                        color: status.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  result.device.remoteId.str,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(label: status.label),
                    _InfoPill(
                      label: result.advertisementData.connectable
                          ? 'Connectable'
                          : 'Non-connectable',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    this.light = false,
  });

  final String label;
  final String value;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final foreground = light ? Colors.white : const Color(0xFF1E2A2F);
    final background = light
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: foreground.withValues(alpha: 0.72),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: foreground,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0EBE0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Color(0xFF4A4A4A),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SignalBadge extends StatelessWidget {
  const _SignalBadge({required this.status});

  final PetStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching, color: status.color, size: 18),
            const SizedBox(width: 8),
            Text(
              status.label,
              style: TextStyle(
                color: status.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
