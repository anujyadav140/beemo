import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/house_provider.dart';
import '../providers/auth_provider.dart';
import '../models/furniture_item.dart';
import '../services/firestore_service.dart';
import '../widgets/coin_display.dart';
import '../widgets/purchase_confirmation_dialog.dart';

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
  bool _isPaintModeActive = false;
  String _selectedFloorColor = '#f5e6d3';
  String _selectedWallColor = '#e8dcc8';
  String _paintCategory = 'floors'; // 'floors' or 'walls'
  StreamSubscription<Map<String, dynamic>>? _roomStateSubscription;

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
    // New furniture items (behind paywall)
    FurnitureItem(
      id: 'arcade',
      name: 'Arcade',
      type: 'furniture',
      emoji: '🕹️',
      imageUrl: 'assets/images/furniture/arcade.png',
    ),
    FurnitureItem(
      id: 'bed',
      name: 'Bed',
      type: 'furniture',
      emoji: '🛏️',
      imageUrl: 'assets/images/furniture/bed.png',
    ),
    FurnitureItem(
      id: 'beemo_box',
      name: 'Beemo Box',
      type: 'decor',
      emoji: '📦',
      imageUrl: 'assets/images/furniture/beemo_box.png',
    ),
    FurnitureItem(
      id: 'chess_table',
      name: 'Chess Table',
      type: 'furniture',
      emoji: '♟️',
      imageUrl: 'assets/images/furniture/chess_table.png',
    ),
    FurnitureItem(
      id: 'computer',
      name: 'Computer',
      type: 'furniture',
      emoji: '💻',
      imageUrl: 'assets/images/furniture/computer.png',
    ),
    FurnitureItem(
      id: 'kitchen',
      name: 'Kitchen',
      type: 'furniture',
      emoji: '🍳',
      imageUrl: 'assets/images/furniture/kitchen.png',
    ),
    FurnitureItem(
      id: 'music_box',
      name: 'Music Box',
      type: 'decor',
      emoji: '🎵',
      imageUrl: 'assets/images/furniture/music_box.png',
    ),
    FurnitureItem(
      id: 'music_system',
      name: 'Music System',
      type: 'furniture',
      emoji: '🔊',
      imageUrl: 'assets/images/furniture/music_system.png',
    ),
    FurnitureItem(
      id: 'music_system_white',
      name: 'Music System White',
      type: 'furniture',
      emoji: '🔈',
      imageUrl: 'assets/images/furniture/music_system_white.png',
    ),
    FurnitureItem(
      id: 'pc_table',
      name: 'PC Table',
      type: 'furniture',
      emoji: '🖥️',
      imageUrl: 'assets/images/furniture/pc_table.png',
    ),
    FurnitureItem(
      id: 'piano',
      name: 'Piano',
      type: 'furniture',
      emoji: '🎹',
      imageUrl: 'assets/images/furniture/piano.png',
    ),
    FurnitureItem(
      id: 'plant',
      name: 'Plant',
      type: 'decor',
      emoji: '🪴',
      imageUrl: 'assets/images/furniture/plant.png',
    ),
    FurnitureItem(
      id: 'tv',
      name: 'TV',
      type: 'furniture',
      emoji: '📺',
      imageUrl: 'assets/images/furniture/tv.png',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _setupRoomStateListener();
  }

  @override
  void dispose() {
    _roomStateSubscription?.cancel();
    super.dispose();
  }

  void _setupRoomStateListener() {
    // Set up listener after first frame to ensure providers are available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final houseProvider = Provider.of<HouseProvider>(context, listen: false);
      final houseId = houseProvider.currentHouseId;

      if (houseId == null) return;

      final roomName = _getRoomKey(_currentRoomIndex);

      _roomStateSubscription = _firestoreService
          .getCompleteRoomStateStream(
            houseId: houseId,
            roomName: roomName,
          )
          .listen((roomState) {
        if (!mounted) return;

        final floorColor = roomState['floor_color'] as String;
        final wallColor = roomState['wall_color'] as String;

        // Only update if colors changed (to avoid circular updates)
        if (floorColor != _selectedFloorColor || wallColor != _selectedWallColor) {
          setState(() {
            _selectedFloorColor = floorColor;
            _selectedWallColor = wallColor;
          });

          // Update webview with new colors (without saving back to Firebase)
          if (_isWebViewReady) {
            _updateWebViewColors(floorColor, wallColor);
          }

          print('🔄 Colors synced from Firebase: floor=$floorColor, wall=$wallColor');
        }
      });
    });
  }

  void _updateWebViewColors(String floorColor, String wallColor) {
    if (!_isWebViewReady) return;

    // Calculate floor color variants
    final darkFloorColor = _darkenColor(floorColor, 0.15);

    _webViewController.runJavaScript(
      "window.postMessage(JSON.stringify({ type: 'CHANGE_FLOOR_COLOR', light: '$floorColor', dark: '$darkFloorColor' }), '*');",
    );

    // Calculate wall color variants
    final topWallColor = _lightenColor(wallColor, 0.1);
    final bottomWallColor = _darkenColor(wallColor, 0.1);

    _webViewController.runJavaScript(
      "window.postMessage(JSON.stringify({ type: 'CHANGE_WALL_COLOR', base: '$wallColor', top: '$topWallColor', bottom: '$bottomWallColor' }), '*');",
    );
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

    // Add to current state and clear selection
    setState(() {
      _currentRoomFurniture.add(item);
      _selectedItemId = null; // Clear selection after placing item
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
      final index = _currentRoomFurniture.indexWhere(
        (item) => item['id'] == id,
      );
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
      final roomState = await _firestoreService.loadCompleteRoomState(
        houseId: houseId,
        roomName: roomName,
      );

      final furnitureItems = roomState['furniture_items'] as List<Map<String, dynamic>>;
      final floorColor = roomState['floor_color'] as String;
      final wallColor = roomState['wall_color'] as String;

      setState(() {
        _currentRoomFurniture = furnitureItems;
        _selectedFloorColor = floorColor;
        _selectedWallColor = wallColor;
      });

      // Send loaded state to WebView including colors
      if (_isWebViewReady) {
        _sendStateToWebView();
        // Also send the colors to update the webview
        _changeFloorColor(floorColor);
        _changeWallColor(wallColor);
      }

      print('📦 Loaded ${furnitureItems.length} items, floor: $floorColor, wall: $wallColor for $roomName');
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

    _webViewController.runJavaScript("window.postMessage($stateJson, '*');");
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

  void _changeFloorColor(String color) {
    setState(() {
      _selectedFloorColor = color;
    });

    if (_isWebViewReady) {
      // Calculate dark variant (15% darker)
      final darkColor = _darkenColor(color, 0.15);

      _webViewController.runJavaScript(
        "window.postMessage(JSON.stringify({ type: 'CHANGE_FLOOR_COLOR', light: '$color', dark: '$darkColor' }), '*');",
      );
    }

    // Save to Firebase
    _saveColorToFirebase();
  }

  void _changeWallColor(String color) {
    setState(() {
      _selectedWallColor = color;
    });

    if (_isWebViewReady) {
      // Calculate variants for wall gradients
      final topColor = _lightenColor(color, 0.1); // Lighter at top
      final bottomColor = _darkenColor(color, 0.1); // Darker at bottom

      _webViewController.runJavaScript(
        "window.postMessage(JSON.stringify({ type: 'CHANGE_WALL_COLOR', base: '$color', top: '$topColor', bottom: '$bottomColor' }), '*');",
      );
    }

    // Save to Firebase
    _saveColorToFirebase();
  }

  Future<void> _saveColorToFirebase() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;

    if (houseId == null) {
      print('⚠️  No house ID available, skipping color save');
      return;
    }

    final roomName = _getRoomKey(_currentRoomIndex);

    try {
      await _firestoreService.saveRoomFurnitureState(
        houseId: houseId,
        roomName: roomName,
        furnitureItems: _currentRoomFurniture,
        floorColor: _selectedFloorColor,
        wallColor: _selectedWallColor,
      );
      print('🎨 Saved colors for $roomName: floor=$_selectedFloorColor, wall=$_selectedWallColor');
    } catch (e) {
      print('❌ Failed to save colors: $e');
    }
  }

  String _darkenColor(String hexColor, double amount) {
    // Remove # if present
    final hex = hexColor.replaceAll('#', '');

    // Parse RGB
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);

    // Darken
    final newR = (r * (1 - amount)).round().clamp(0, 255);
    final newG = (g * (1 - amount)).round().clamp(0, 255);
    final newB = (b * (1 - amount)).round().clamp(0, 255);

    // Convert back to hex
    return '#${newR.toRadixString(16).padLeft(2, '0')}${newG.toRadixString(16).padLeft(2, '0')}${newB.toRadixString(16).padLeft(2, '0')}';
  }

  String _lightenColor(String hexColor, double amount) {
    // Remove # if present
    final hex = hexColor.replaceAll('#', '');

    // Parse RGB
    final r = int.parse(hex.substring(0, 2), radix: 16);
    final g = int.parse(hex.substring(2, 4), radix: 16);
    final b = int.parse(hex.substring(4, 6), radix: 16);

    // Lighten
    final newR = (r + (255 - r) * amount).round().clamp(0, 255);
    final newG = (g + (255 - g) * amount).round().clamp(0, 255);
    final newB = (b + (255 - b) * amount).round().clamp(0, 255);

    // Convert back to hex
    return '#${newR.toRadixString(16).padLeft(2, '0')}${newG.toRadixString(16).padLeft(2, '0')}${newB.toRadixString(16).padLeft(2, '0')}';
  }

  Future<void> _handleColorPurchase(
    String itemId,
    String itemName,
    int currentCoins,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    if (userId == null || houseId == null) return;

    const cost = 50;

    showDialog(
      context: context,
      builder: (context) => PurchaseConfirmationDialog(
        itemName: itemName,
        cost: cost,
        currentCoins: currentCoins,
        onConfirm: () async {
          Navigator.of(context).pop();

          // Show loading indicator
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Processing purchase...'),
              duration: Duration(seconds: 1),
            ),
          );

          // Attempt purchase
          final success = await _firestoreService.purchaseItem(
            houseId: houseId,
            userId: userId,
            itemId: itemId,
            cost: cost,
          );

          if (!mounted) return;

          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$itemName unlocked!'),
                backgroundColor: const Color(0xFF4CAF50),
                duration: const Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Purchase failed. Please try again.'),
                backgroundColor: Color(0xFFE57373),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        onCancel: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _handleFurniturePurchase(
    String itemId,
    String itemName,
    int currentCoins,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    if (userId == null || houseId == null) return;

    const cost = 50;

    showDialog(
      context: context,
      builder: (context) => PurchaseConfirmationDialog(
        itemName: itemName,
        cost: cost,
        currentCoins: currentCoins,
        onConfirm: () async {
          Navigator.of(context).pop();

          // Show loading indicator
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Processing purchase...'),
              duration: Duration(seconds: 1),
            ),
          );

          // Attempt purchase with furniture_itemId format
          final purchaseItemId = 'furniture_$itemId';
          final success = await _firestoreService.purchaseItem(
            houseId: houseId,
            userId: userId,
            itemId: purchaseItemId,
            cost: cost,
          );

          if (!mounted) return;

          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$itemName unlocked!'),
                backgroundColor: const Color(0xFF4CAF50),
                duration: const Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Purchase failed. Please try again.'),
                backgroundColor: Color(0xFFE57373),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        onCancel: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _buildColorOption(
    Map<String, dynamic> option,
    Color color,
    String colorHex,
    bool isSelected,
    bool isFree,
    bool isOwned,
    List<String> purchasedItems,
    int currentCoins,
  ) {
    final isLocked = !isFree && !isOwned;
    final itemName = option['name'] as String;
    final itemId = '${_paintCategory}_$itemName'.toLowerCase().replaceAll(
      ' ',
      '_',
    );

    return GestureDetector(
      onTap: () {
        if (isLocked) {
          // Show purchase dialog
          _handleColorPurchase(itemId, itemName, currentCoins);
        } else {
          // Free or owned - allow color change
          if (_paintCategory == 'floors') {
            _changeFloorColor(colorHex);
          } else {
            _changeWallColor(colorHex);
          }
        }
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF4D8D) : Colors.black,
            width: isSelected ? 3 : 2,
          ),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Color preview circle - centered
                Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                // Color name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3.0),
                  child: Text(
                    itemName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      color: isSelected
                          ? const Color(0xFFFF4D8D)
                          : isLocked
                          ? Colors.grey
                          : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            // Lock icon overlay - top right corner
            if (isLocked)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryIconButton(
    String emoji,
    Color color, {
    required bool isLeft,
    bool isRight = false,
    bool isMiddle = false,
  }) {
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
          borderRadius: isLeft
              ? const BorderRadius.only(topLeft: Radius.circular(12))
              : isRight
              ? const BorderRadius.only(topRight: Radius.circular(12))
              : BorderRadius.zero,
          border: Border(
            top: const BorderSide(color: Colors.black, width: 2),
            left: isLeft
                ? const BorderSide(color: Colors.black, width: 2)
                : BorderSide.none,
            right: !isMiddle
                ? const BorderSide(color: Colors.black, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
      ),
    );
  }

  Widget _buildPaintIconButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isPaintModeActive = !_isPaintModeActive;
        });
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFFF4D8D),
          borderRadius: const BorderRadius.only(topRight: Radius.circular(12)),
          border: Border.all(
            color: _isPaintModeActive ? Colors.white : Colors.black,
            width: _isPaintModeActive ? 3 : 2,
          ),
          boxShadow: _isPaintModeActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF4D8D).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            '🎨',
            style: TextStyle(fontSize: _isPaintModeActive ? 26 : 24),
          ),
        ),
      ),
    );
  }

  Widget _buildFurnitureList() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    // If user is not logged in or no house, show all items as unlocked
    if (userId == null || houseId == null) {
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: _allFurnitureItems.length,
        itemBuilder: (context, index) {
          final item = _allFurnitureItems[index];
          final isSelected = _selectedItemId == item.id;
          final isFree = index < 7; // First 7 items are free

          return _buildFurnitureItem(item, isSelected, isFree, false, [], 0);
        },
      );
    }

    // Use StreamBuilder to check ownership
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('houses')
          .doc(houseId)
          .snapshots(),
      builder: (context, snapshot) {
        List<String> purchasedItems = [];
        int currentCoins = 0;

        if (snapshot.hasData && snapshot.data != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;

          // Handle both Map and List formats for members
          final membersData = data?['members'];
          Map<String, dynamic>? members;

          if (membersData is Map<String, dynamic>) {
            members = membersData;
          } else if (membersData is List) {
            members = {};
          }

          final userMember = members?[userId] as Map<String, dynamic>?;
          purchasedItems = List<String>.from(
            userMember?['purchasedItems'] ?? [],
          );
          currentCoins = (userMember?['coins'] ?? 0) as int;
        }

        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          itemCount: _allFurnitureItems.length,
          itemBuilder: (context, index) {
            final item = _allFurnitureItems[index];
            final isSelected = _selectedItemId == item.id;
            final isFree = index < 7; // First 7 items are free
            final itemId = 'furniture_${item.id}';
            final isOwned = purchasedItems.contains(itemId);

            return _buildFurnitureItem(
              item,
              isSelected,
              isFree,
              isOwned,
              purchasedItems,
              currentCoins,
            );
          },
        );
      },
    );
  }

  Widget _buildFurnitureItem(
    FurnitureItem item,
    bool isSelected,
    bool isFree,
    bool isOwned,
    List<String> purchasedItems,
    int currentCoins,
  ) {
    final isLocked = !isFree && !isOwned;

    return GestureDetector(
      onTap: () {
        if (isLocked) {
          // Show purchase dialog
          _handleFurniturePurchase(item.id, item.name, currentCoins);
        } else {
          // Free or owned - allow selection
          _selectFurnitureItem(item.id);
        }
      },
      child: Container(
        width: 115,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF4D8D)
              : isLocked
              ? Colors.grey[200]
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF4D8D)
                : Colors.black,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: item.imageUrl != null && item.imageUrl!.startsWith("assets/")
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Opacity(
                              opacity: isLocked ? 0.3 : 1.0,
                              child: Image.asset(
                                item.imageUrl!,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      item.emoji,
                                      style: const TextStyle(fontSize: 40),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Opacity(
                            opacity: isLocked ? 0.3 : 1.0,
                            child: Text(
                              item.emoji,
                              style: const TextStyle(fontSize: 40),
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14.0),
                  child: Text(
                    item.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? Colors.white
                          : isLocked
                          ? Colors.grey
                          : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            // Lock icon overlay - top right corner
            if (isLocked)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final userId = authProvider.user?.uid;
    final houseId = houseProvider.currentHouseId;

    // Floor color/texture options
    final List<Map<String, dynamic>> floorOptions = [
      {'name': 'Light Wood', 'color': '#f5e6d3'},
      {'name': 'Dark Wood', 'color': '#8B4513'},
      {'name': 'White Tile', 'color': '#f0f0f0'},
      {'name': 'Gray Tile', 'color': '#a0a0a0'},
      {'name': 'Black Tile', 'color': '#2c2c2c'},
      {'name': 'Marble', 'color': '#e8e8e8'},
      {'name': 'Stone', 'color': '#b8a896'},
      {'name': 'Concrete', 'color': '#95958c'},
      {'name': 'Oak', 'color': '#c19a6b'},
      {'name': 'Cherry', 'color': '#d2691e'},
      {'name': 'Walnut', 'color': '#5c4033'},
      {'name': 'Bamboo', 'color': '#e0c097'},
      {'name': 'Terracotta', 'color': '#d4775d'},
      {'name': 'Slate', 'color': '#708090'},
      {'name': 'Cream', 'color': '#fffdd0'},
    ];

    // Wall color/texture options
    final List<Map<String, dynamic>> wallOptions = [
      {'name': 'Beige', 'color': '#e8dcc8'},
      {'name': 'White', 'color': '#f5f5f5'},
      {'name': 'Light Gray', 'color': '#d3d3d3'},
      {'name': 'Warm Gray', 'color': '#a8a8a8'},
      {'name': 'Cream', 'color': '#faf0e6'},
      {'name': 'Ivory', 'color': '#fffff0'},
      {'name': 'Peach', 'color': '#ffe5d4'},
      {'name': 'Light Blue', 'color': '#d4e8f0'},
      {'name': 'Sage', 'color': '#c8d4c0'},
      {'name': 'Lavender', 'color': '#e6e6fa'},
      {'name': 'Light Pink', 'color': '#ffd4e0'},
      {'name': 'Mint', 'color': '#d4f0e8'},
      {'name': 'Tan', 'color': '#d2b48c'},
      {'name': 'Sand', 'color': '#f4e4c0'},
      {'name': 'Light Brown', 'color': '#c0b090'},
    ];

    final options = _paintCategory == 'floors' ? floorOptions : wallOptions;
    final selectedColor = _paintCategory == 'floors'
        ? _selectedFloorColor
        : _selectedWallColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Category selector (Walls / Floors) - Compact version
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _paintCategory = 'floors';
                    });
                  },
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: _paintCategory == 'floors'
                          ? const Color(0xFFFF4D8D)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _paintCategory == 'floors'
                            ? const Color(0xFFFF4D8D)
                            : Colors.black,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'FLOORS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: _paintCategory == 'floors'
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _paintCategory = 'walls';
                    });
                  },
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      color: _paintCategory == 'walls'
                          ? const Color(0xFFFF4D8D)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _paintCategory == 'walls'
                            ? const Color(0xFFFF4D8D)
                            : Colors.black,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'WALLS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: _paintCategory == 'walls'
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Color options - Scrollable horizontal list
        Expanded(
          child: userId == null || houseId == null
              ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final colorHex = option['color'] as String;
                    final colorValue = int.parse(
                      colorHex.replaceAll('#', 'ff'),
                      radix: 16,
                    );
                    final color = Color(colorValue);
                    final isSelected = selectedColor == colorHex;
                    final isFree = index < 3;

                    return _buildColorOption(
                      option,
                      color,
                      colorHex,
                      isSelected,
                      isFree,
                      false,
                      [],
                      0,
                    );
                  },
                )
              : StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('houses')
                      .doc(houseId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    List<String> purchasedItems = [];
                    int currentCoins = 0;

                    if (snapshot.hasData && snapshot.data != null) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>?;

                      // Handle both Map and List formats for members
                      final membersData = data?['members'];
                      Map<String, dynamic>? members;

                      if (membersData is Map<String, dynamic>) {
                        members = membersData;
                      } else if (membersData is List) {
                        // If it's a List, we can't access by userId, use empty map
                        members = {};
                      }

                      final userMember =
                          members?[userId] as Map<String, dynamic>?;
                      purchasedItems = List<String>.from(
                        userMember?['purchasedItems'] ?? [],
                      );
                      currentCoins = (userMember?['coins'] ?? 0) as int;
                    }

                    return ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final colorHex = option['color'] as String;
                        final colorValue = int.parse(
                          colorHex.replaceAll('#', 'ff'),
                          radix: 16,
                        );
                        final color = Color(colorValue);
                        final isSelected = selectedColor == colorHex;
                        final isFree = index < 3;
                        final itemId = '${_paintCategory}_${option['name']}'
                            .toLowerCase()
                            .replaceAll(' ', '_');
                        final isOwned = purchasedItems.contains(itemId);

                        return _buildColorOption(
                          option,
                          color,
                          colorHex,
                          isSelected,
                          isFree,
                          isOwned,
                          purchasedItems,
                          currentCoins,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
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
                            border: Border.all(color: Colors.black, width: 2.5),
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
                      Consumer2<HouseProvider, AuthProvider>(
                        builder: (context, houseProvider, authProvider, _) {
                          final userId = authProvider.user?.uid;
                          final houseId = houseProvider.currentHouseId;

                          if (userId == null || houseId == null) {
                            return const CoinDisplay(
                              points: 0,
                              fontSize: 18,
                              coinSize: 22,
                              fontWeight: FontWeight.bold,
                              showBorder: true,
                            );
                          }

                          return CoinDisplay(
                            userId: userId,
                            houseId: houseId,
                            fontSize: 18,
                            coinSize: 22,
                            fontWeight: FontWeight.bold,
                            showBorder: true,
                          );
                        },
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
                Opacity(
                  opacity: 0.4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '🚧 Work in Progress - Multiple rooms coming soon!',
                                ),
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
                              border: Border.all(
                                color: Colors.black,
                                width: 2.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.chevron_left,
                              size: 28,
                              color: Colors.black,
                            ),
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
                                content: Text(
                                  '🚧 Work in Progress - Multiple rooms coming soon!',
                                ),
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
                              border: Border.all(
                                color: Colors.black,
                                width: 2.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.chevron_right,
                              size: 28,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
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

                // Category Buttons and Furniture Slider
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Icon Buttons on top left (horizontal, stuck together)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Opacity(
                          opacity: 0.5,
                          child: _buildCategoryIconButton(
                            '🛋️',
                            const Color(0xFFFFC400),
                            isLeft: true,
                          ),
                        ),
                        Opacity(
                          opacity: 0.5,
                          child: _buildCategoryIconButton(
                            '🌿',
                            const Color(0xFF00D9A3),
                            isLeft: false,
                            isMiddle: true,
                          ),
                        ),
                        _buildPaintIconButton(),
                      ],
                    ),

                    // Furniture Items Slider or Color Picker (based on mode)
                    Container(
                      height: 160,
                      margin: const EdgeInsets.only(right: 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(0),
                          topRight: Radius.circular(30),
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                        border: Border(
                          top: BorderSide(color: Colors.black, width: 2),
                        ),
                      ),
                      child: _isPaintModeActive
                          ? _buildColorPicker()
                          : _buildFurnitureList(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
