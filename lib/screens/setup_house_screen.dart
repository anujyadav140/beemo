import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import 'dash_screen.dart';

class SetupHouseScreen extends StatefulWidget {
  const SetupHouseScreen({super.key});

  @override
  State<SetupHouseScreen> createState() => _SetupHouseScreenState();
}

class _SetupHouseScreenState extends State<SetupHouseScreen> {
  final TextEditingController _houseNameController = TextEditingController();
  final TextEditingController _bedroomsController = TextEditingController();
  final TextEditingController _bathroomsController = TextEditingController();
  bool _isFinishPressed = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _houseNameController.addListener(() {
      setState(() {});
    });
    _bedroomsController.addListener(() {
      setState(() {});
    });
    _bathroomsController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _houseNameController.dispose();
    _bedroomsController.dispose();
    _bathroomsController.dispose();
    super.dispose();
  }

  Future<void> _handleFinish() async {
    if (_houseNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a house name')),
      );
      return;
    }

    if (_bedroomsController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter number of bedrooms')),
      );
      return;
    }

    if (_bathroomsController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter number of bathrooms')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);

    // Get user name from Firebase user display name or email
    String userName = authProvider.user?.displayName ??
                     authProvider.user?.email?.split('@')[0] ??
                     'User';

    String? houseId = await houseProvider.createHouse(
      name: _houseNameController.text.trim(),
      bedrooms: int.parse(_bedroomsController.text),
      bathrooms: int.parse(_bathroomsController.text),
      userName: userName,
    );

    setState(() {
      _isLoading = false;
    });

    if (houseId != null && mounted) {
      // Successfully created house, navigate to dash screen
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashScreen()),
        (route) => false,
      );
    } else if (mounted) {
      // Failed to create house
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(houseProvider.error ?? 'Failed to create house'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 40),
                        // Title
                        const Text(
                          "let's set up your\nVirtual house.",
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // House name question
                        const Text(
                          'What do you want to name\nyour house?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTextInputField(_houseNameController, 'My Awesome House'),
                        const SizedBox(height: 32),

                        // Bedrooms question
                        const Text(
                          'How many bedrooms do you\nhave?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(_bedroomsController),
                        const SizedBox(height: 32),

                        // Bathrooms question
                        const Text(
                          'How many bathrooms do you\nhave?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(_bathroomsController),
                      ],
                    ),
                  ),
                ),

                // Bottom design with circular sections
                SizedBox(
                  height: 280,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Black circle (left)
                      Positioned(
                        left: -150,
                        bottom: -200,
                        child: Container(
                          width: 400,
                          height: 400,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      // Cyan circle (right/center)
                      Positioned(
                        right: -80,
                        bottom: -150,
                        child: Container(
                          width: 400,
                          height: 400,
                          decoration: const BoxDecoration(
                            color: Color(0xFF16A3D0),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      // Finish button
                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Color(0xFF7CB342),
                                )
                              : GestureDetector(
                                  onTapDown: (_) {
                                    setState(() {
                                      _isFinishPressed = true;
                                    });
                                  },
                                  onTapUp: (_) async {
                                    setState(() {
                                      _isFinishPressed = false;
                                    });
                                    await _handleFinish();
                                  },
                                  onTapCancel: () {
                                    setState(() {
                                      _isFinishPressed = false;
                                    });
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(40),
                                    ),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 100),
                                      curve: Curves.easeOut,
                                      margin: EdgeInsets.only(
                                        bottom: _isFinishPressed ? 0 : 5,
                                        right: _isFinishPressed ? 0 : 5,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 64,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7CB342),
                                        borderRadius: BorderRadius.circular(40),
                                        border: Border.all(color: Colors.black, width: 3),
                                      ),
                                      child: const Text(
                                        'Finish',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          fontStyle: FontStyle.italic,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInputField(TextEditingController controller, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Colors.black26,
                  fontSize: 18,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                fillColor: Colors.transparent,
                filled: true,
              ),
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() {
                  controller.clear();
                });
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF4D8D),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.black, width: 3),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: const InputDecoration(
                hintText: '1 to 10',
                hintStyle: TextStyle(
                  color: Colors.black26,
                  fontSize: 18,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                fillColor: Colors.transparent,
                filled: true,
              ),
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() {
                  controller.clear();
                });
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF4D8D),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
