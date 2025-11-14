import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/house_provider.dart';
import '../models/furniture_item.dart';
import '../services/firestore_service.dart';

class EditHouseWebViewScreen extends StatefulWidget {
  const EditHouseWebViewScreen({super.key});

  @override
  State<EditHouseWebViewScreen> createState() => _EditHouseWebViewScreenState();
}

class _EditHouseWebViewScreenState extends State<EditHouseWebViewScreen> {
  late final WebViewController _webViewController;
  final FirestoreService _firestoreService = FirestoreService();
  int _currentRoomIndex = 0;
  String? _selectedItemId;
  bool _isWebViewReady = false;
  bool _hasLoadedInitialState = false;
  List<Map<String, dynamic>> _currentRoomFurniture = [];

  final List<Map<String, dynamic>> _rooms = [
    {'name': 'Living Room'},
    {'name': 'Bedroom'},
    {'name': 'Kitchen'},
    {'name': 'Bathroom'},
  ];

  // Available furniture items matching the Next.js app
  final List<FurnitureItem> _allFurnitureItems = [
    FurnitureItem(
      id: 'couch',
      name: 'Couch',
      type: 'furniture',
      emoji: '🛋️',
      imageUrl: 'assets/images/furniture/couch.png',
    ),
    FurnitureItem(
      id: 'table',
      name: 'Table',
      type: 'furniture',
      emoji: '🪑',
      imageUrl: 'assets/images/furniture/table.png',
    ),
    FurnitureItem(
      id: 'bookshelf',
      name: 'Bookshelf',
      type: 'furniture',
      emoji: '📚',
      imageUrl: 'assets/images/furniture/bookshelf.png',
    ),
    FurnitureItem(
      id: 'desk',
      name: 'Desk',
      type: 'furniture',
      emoji: '🖥️',
      imageUrl: 'assets/images/furniture/desk.png',
    ),
    FurnitureItem(
      id: 'sofa',
      name: 'Sofa',
      type: 'furniture',
      emoji: '🛋️',
      imageUrl: 'assets/images/furniture/sofa.png',
    ),
    FurnitureItem(
      id: 'rug',
      name: 'Rug',
      type: 'decor',
      emoji: '🟥',
      imageUrl: 'assets/images/furniture/rug.png',
    ),
    FurnitureItem(
      id: 'lamp',
      name: 'Lamp',
      type: 'decor',
      emoji: '💡',
      imageUrl: 'assets/images/furniture/lamp.png',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    // Initialize WebView controller
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isWebViewReady = true;
            });
            // Note: State loading is handled by the READY message from WebView
            // No need to load here to avoid duplicate loads
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleWebViewMessage(message.message);
        },
      )
      ..loadRequest(Uri.parse('https://beemo-house.netlify.app/'));
  }

  void _handleWebViewMessage(String message) {
    // Handle messages from the WebView
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      print('📨 Received from WebView: $type');

      switch (type) {
        case 'ITEM_PLACED':
          _handleItemPlaced(data);
          break;
        case 'ITEM_MOVED':
          _handleItemMoved(data);
          break;
        case 'ITEM_REMOVED':
          _handleItemRemoved(data);
          break;
        case 'READY':
          _handleWebViewReady();
          break;
        default:
          print('Unknown message type: $type');
      }
    } catch (e) {
      print('❌ Error handling WebView message: $e');
    }
  }

  void _handleItemPlaced(Map<String, dynamic> data) async {
    final item = data['item'] as Map<String, dynamic>?;
    if (item == null) return;

    // Add to current state
    setState(() {
      _currentRoomFurniture.add(item);
    });

    // Save to Firebase
    await _saveCurrentRoomState();
  }

  void _handleItemMoved(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    final x = data['x'] as num?;
    final y = data['y'] as num?;

    if (id == null || x == null || y == null) return;

    // Update in current state
    setState(() {
      final index = _currentRoomFurniture.indexWhere((item) => item['id'] == id);
      if (index != -1) {
        _currentRoomFurniture[index]['x'] = x;
        _currentRoomFurniture[index]['y'] = y;
      }
    });

    // Save to Firebase
    await _saveCurrentRoomState();
  }

  void _handleItemRemoved(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (id == null) return;

    // Remove from current state
    setState(() {
      _currentRoomFurniture.removeWhere((item) => item['id'] == id);
    });

    // Save to Firebase
    await _saveCurrentRoomState();
  }

  void _handleWebViewReady() {
    if (!_hasLoadedInitialState) {
      print('✅ WebView is ready, loading initial room state...');
      _hasLoadedInitialState = true;
      _loadCurrentRoomState();
    } else {
      print('⚠️  WebView sent READY again, ignoring to avoid duplicate load');
    }
  }

  Future<void> _saveCurrentRoomState() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId == null) {
      print('⚠️  No house ID available, skipping save');
      return;
    }

    final roomName = _getRoomKey(_currentRoomIndex);

    try {
      await _firestoreService.saveRoomFurnitureState(
        houseId: houseId,
        roomName: roomName,
        furnitureItems: _currentRoomFurniture,
      );
      print('💾 Saved furniture state for $roomName');
    } catch (e) {
      print('❌ Failed to save room state: $e');
    }
  }

  Future<void> _loadCurrentRoomState() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId == null) {
      print('⚠️  No house ID available, skipping load');
      return;
    }

    final roomName = _getRoomKey(_currentRoomIndex);

    try {
      final furnitureItems = await _firestoreService.loadRoomFurnitureState(
        houseId: houseId,
        roomName: roomName,
      );

      setState(() {
        _currentRoomFurniture = furnitureItems;
      });

      // Send loaded state to WebView
      if (_isWebViewReady) {
        _sendStateToWebView();
      }

      print('📦 Loaded ${furnitureItems.length} items for $roomName');
    } catch (e) {
      print('❌ Failed to load room state: $e');
    }
  }

  void _sendStateToWebView() {
    if (!_isWebViewReady) return;

    final stateJson = jsonEncode({
      'type': 'LOAD_STATE',
      'items': _currentRoomFurniture,
      'currentRoom': _getRoomKey(_currentRoomIndex),
    });

    _webViewController.runJavaScript(
      "window.postMessage($stateJson, '*');",
    );
    print('📤 Sent state to WebView: ${_currentRoomFurniture.length} items');
  }

  String _getRoomKey(int index) {
    final roomNames = ['living_room', 'bedroom', 'kitchen', 'bathroom'];
    return roomNames[index];
  }

  void _selectFurnitureItem(String itemId) {
    setState(() {
      _selectedItemId = itemId;
    });

    if (_isWebViewReady) {
      // Send selection to WebView using window.postMessage
      _webViewController.runJavaScript(
        "window.postMessage(JSON.stringify({ type: 'SELECT_ITEM', itemId: '$itemId' }), '*');",
      );
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedItemId = null;
    });

    if (_isWebViewReady) {
      _webViewController.runJavaScript(
        "window.postMessage(JSON.stringify({ type: 'CLEAR_SELECTION' }), '*');",
      );
    }
  }

  Widget _buildCategoryIconButton(String emoji, Color color) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚧 Work in Progress - More categories coming soon!'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFFFF4D8D),
          ),
        );
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[600]!, width: 2),
        ),
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(fontSize: 24, color: Colors.grey[700]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final currentRoom = _rooms[_currentRoomIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top Bar
                Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  // Back Button
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 2.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Color(0xFFFF4D8D),
                        size: 28,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Coins Display
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC400),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          '500',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: Colors.orange[800],
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 14,
                              height: 14,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF9500),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.orange[900],
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // House Icon
                  StreamBuilder<DocumentSnapshot>(
                    stream: houseProvider.currentHouseId != null
                        ? FirebaseFirestore.instance
                            .collection('houses')
                            .doc(houseProvider.currentHouseId)
                            .snapshots()
                        : null,
                    builder: (context, snapshot) {
                      String houseEmoji = '🏠';
                      Color houseColor = const Color(0xFF00BCD4);

                      if (snapshot.hasData && snapshot.data != null) {
                        final houseData =
                            snapshot.data!.data() as Map<String, dynamic>?;
                        houseEmoji = houseData?['houseEmoji'] ?? '🏠';
                        final houseColorInt = houseData?['houseColor'];
                        if (houseColorInt != null) {
                          houseColor = Color(houseColorInt);
                        }
                      }

                      return Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: houseColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black,
                            width: 2.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            houseEmoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Room Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🚧 Work in Progress - Multiple rooms coming soon!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: Color(0xFFFF4D8D),
                        ),
                      );
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2.5),
                      ),
                      child: const Icon(Icons.chevron_left, size: 28, color: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 60,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4D8D),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black, width: 2.5),
                    ),
                    child: Text(
                      currentRoom['name'],
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🚧 Work in Progress - Multiple rooms coming soon!'),
                          duration: Duration(seconds: 2),
                          backgroundColor: Color(0xFFFF4D8D),
                        ),
                      );
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2.5),
                      ),
                      child: const Icon(Icons.chevron_right, size: 28, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // WebView - Isometric Room
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: _isWebViewReady
                    ? WebViewWidget(controller: _webViewController)
                    : const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF4D8D),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 10),

            // Furniture Slider Container
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
                border: Border.all(color: Colors.black, width: 3),
              ),
              child: Column(
                children: [
                  // Category Icon Buttons (greyed out - work in progress)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildCategoryIconButton('🛋️', Colors.grey[400]!),
                        const SizedBox(width: 8),
                        _buildCategoryIconButton('🌿', Colors.grey[400]!),
                        const SizedBox(width: 8),
                        _buildCategoryIconButton('🎨', Colors.grey[400]!),
                      ],
                    ),
                  ),

                  // Furniture Items Slider
                  SizedBox(
                    height: 140,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _allFurnitureItems.length,
                      itemBuilder: (context, index) {
                        final item = _allFurnitureItems[index];
                        final isSelected = _selectedItemId == item.id;

                        return GestureDetector(
                          onTap: () {
                            _selectFurnitureItem(item.id);
                          },
                          child: Container(
                            width: 110,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFF4D8D)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFFF4D8D) : Colors.black,
                                width: isSelected ? 3 : 2.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: item.imageUrl != null && item.imageUrl!.startsWith("assets/")
                                      ? Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Image.asset(
                                            item.imageUrl!,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Center(
                                                child: Text(
                                                  item.emoji,
                                                  style: const TextStyle(fontSize: 36),
                                                ),
                                              );
                                            },
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            item.emoji,
                                            style: const TextStyle(fontSize: 36),
                                          ),
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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
}
