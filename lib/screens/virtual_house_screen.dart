import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3, Matrix4;
import '../providers/house_provider.dart';
import '../widgets/beemo_logo.dart';
import '../models/furniture_item.dart';
import 'agenda_screen.dart';

class VirtualHouseScreen extends StatefulWidget {
  const VirtualHouseScreen({super.key});

  @override
  State<VirtualHouseScreen> createState() => _VirtualHouseScreenState();
}

class _VirtualHouseScreenState extends State<VirtualHouseScreen> {
  int _currentRoomIndex = 0;
  List<PlacedFurniture> _placedFurniture = [];
  bool _showFurniturePanel = false;
  FurnitureItem? _selectedFurniture;
  final TransformationController _transformationController = TransformationController();
  double _currentScale = 1.0;
  static const double _gridSize = 40.0;
  bool _showGrid = false;
  Size _roomContainerSize = Size.zero;

  final List<Map<String, dynamic>> _rooms = [
    {
      'name': 'Living Room',
      'color': Color(0xFF9575CD),
      'floorColor': Color(0xFFD1C4E9),
    },
    {
      'name': 'Bedroom',
      'color': Color(0xFFE91E63),
      'floorColor': Color(0xFFF8BBD0),
    },
    {
      'name': 'Kitchen',
      'color': Color(0xFFFFA726),
      'floorColor': Color(0xFFFFE0B2),
    },
    {
      'name': 'Bathroom',
      'color': Color(0xFF29B6F6),
      'floorColor': Color(0xFFB3E5FC),
    },
  ];

  final List<FurnitureItem> _availableFurniture = [
    FurnitureItem(
      id: 'bookshelf',
      name: 'Bookshelf',
      type: 'storage',
      emoji: '📚',
      width: 70,
      height: 90,
    ),
    FurnitureItem(
      id: 'couch',
      name: 'Couch',
      type: 'seating',
      emoji: '🛋️',
      width: 90,
      height: 70,
    ),
    FurnitureItem(
      id: 'desk',
      name: 'Desk',
      type: 'furniture',
      emoji: '🖥️',
      width: 100,
      height: 60,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    setState(() {
      _currentScale = _transformationController.value.getMaxScaleOnAxis();
    });
  }

  void _zoomIn() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.2).clamp(0.5, 3.0);
    _transformationController.value = Matrix4.identity()..scale(newScale, newScale, 1.0);
  }

  void _zoomOut() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.2).clamp(0.5, 3.0);
    _transformationController.value = Matrix4.identity()..scale(newScale, newScale, 1.0);
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Offset _snapToGrid(Offset position) {
    return Offset(
      (position.dx / _gridSize).round() * _gridSize,
      (position.dy / _gridSize).round() * _gridSize,
    );
  }

  // Check if furniture position is on the floor (for floor-only items like couch)
  bool _isPositionOnFloor(Offset position, Size containerSize) {
    final centerX = containerSize.width / 2;
    final centerY = containerSize.height / 2;
    final roomWidth = containerSize.width * 0.8;
    final roomDepth = containerSize.width * 0.6;
    final roomHeight = containerSize.height * 0.5;

    // Floor diamond points
    final bottom = Offset(centerX, centerY + roomHeight * 0.3);
    final right = Offset(centerX + roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);
    final top = Offset(centerX, centerY - roomDepth / 2 + roomHeight * 0.3);
    final left = Offset(centerX - roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);

    // Point in diamond test
    bool sign(Offset p1, Offset p2, Offset p3) {
      return (p1.dx - p3.dx) * (p2.dy - p3.dy) - (p2.dx - p3.dx) * (p1.dy - p3.dy) < 0;
    }

    bool b1 = sign(position, bottom, right);
    bool b2 = sign(position, right, top);
    bool b3 = sign(position, top, left);
    bool b4 = sign(position, left, bottom);

    return ((b1 == b2) && (b2 == b3) && (b3 == b4));
  }

  @override
  Widget build(BuildContext context) {
    final houseProvider = Provider.of<HouseProvider>(context);
    final houseId = houseProvider.currentHouseId;
    final currentRoom = _rooms[_currentRoomIndex];

    // Initialize room container size for floor validation
    final screenSize = MediaQuery.of(context).size;
    if (_roomContainerSize == Size.zero) {
      _roomContainerSize = Size(screenSize.width - 40, screenSize.height * 0.5);
    }

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // House Icon
                      StreamBuilder<DocumentSnapshot>(
                        stream: houseId != null
                            ? FirebaseFirestore.instance
                                .collection('houses')
                                .doc(houseId)
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
                      // Coins Badge
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
                    ],
                  ),
                ),

                // Tool Icons Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showFurniturePanel = !_showFurniturePanel;
                          });
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _showFurniturePanel
                                ? const Color(0xFFFF4D8D)
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black,
                              width: 2.5,
                            ),
                          ),
                          child: Icon(
                            Icons.format_paint,
                            color: _showFurniturePanel
                                ? Colors.white
                                : const Color(0xFFFF4D8D),
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4D8D),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black,
                              width: 2.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.home_work,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Zoom Out Button
                      GestureDetector(
                        onTap: _zoomOut,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.zoom_out,
                            color: Color(0xFFFF4D8D),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Zoom Percentage Display (tap to reset)
                      GestureDetector(
                        onTap: _resetZoom,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            "${(_currentScale * 100).toInt()}%",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Zoom In Button
                      GestureDetector(
                        onTap: _zoomIn,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.zoom_in,
                            color: Color(0xFFFF4D8D),
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Room Navigation
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_currentRoomIndex > 0) {
                            setState(() {
                              _currentRoomIndex--;
                              _loadFurnitureForRoom();
                            });
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2.5),
                          ),
                          child: const Icon(Icons.chevron_left, size: 28),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
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
                          if (_currentRoomIndex < _rooms.length - 1) {
                            setState(() {
                              _currentRoomIndex++;
                              _loadFurnitureForRoom();
                            });
                          }
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2.5),
                          ),
                          child: const Icon(Icons.chevron_right, size: 28),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Isometric Room View
                Expanded(
                  child: GestureDetector(
                    onTapUp: (details) {
                      if (_selectedFurniture != null) {
                        _placeFurniture(details.localPosition);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      minScale: 0.5,
                      maxScale: 3.0,
                      child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Stack(
                        children: [
                          // Room visualization
                          _buildIsometricRoom(currentRoom),
                          // Grid overlay (only show when couch is selected)
                          if (_showGrid)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: GridPainter(_gridSize),
                              ),
                            ),
                          // Placed furniture
                          ..._placedFurniture.map((placed) {
                            final furniture = _availableFurniture.firstWhere(
                              (f) => f.id == placed.furnitureId,
                              orElse: () => _availableFurniture[0],
                            );
                            return Positioned(
                              left: placed.x,
                              top: placed.y,
                              child: Draggable(
                                feedback: _buildFurnitureWidget(furniture, true),
                                childWhenDragging: Container(),
                                onDragEnd: (details) {
                                  _updateFurniturePosition(
                                    placed.placedId,
                                    details.offset.dx,
                                    details.offset.dy,
                                  );
                                },
                                child: _buildFurnitureWidget(furniture, false),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    ), // InteractiveViewer
                  ),
                ),
              ],
            ),

            // Bottom Navigation
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  height: 78,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16213E),
                      borderRadius: BorderRadius.circular(34),
                    ),
                    clipBehavior: Clip.none,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: _buildNavIcon(Icons.view_in_ar_rounded, true),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: _buildBeemoNavIcon(false),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AgendaScreen(),
                              ),
                            );
                          },
                          child: _buildNavIcon(Icons.event_note_rounded, false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Furniture Selection Bottom Panel
            if (_showFurniturePanel)
              Positioned(
                bottom: 120,
                left: 0,
                right: 0,
                child: Container(
                  height: 220,
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
                      // Category Tabs
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            _buildCategoryTab(Icons.chair, true),
                            const SizedBox(width: 12),
                            _buildCategoryTab(Icons.energy_savings_leaf, false),
                            const SizedBox(width: 12),
                            _buildCategoryTab(Icons.image, false),
                          ],
                        ),
                      ),
                      // Furniture Items
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _availableFurniture.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _availableFurniture.length) {
                              return GestureDetector(
                                onTap: () {
                                  // Add more furniture
                                },
                                child: Container(
                                  width: 120,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC400),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.black,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    size: 48,
                                  ),
                                ),
                              );
                            }

                            final furniture = _availableFurniture[index];
                            final isSelected = _selectedFurniture?.id == furniture.id;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedFurniture = furniture;
                                  _showGrid = furniture.id == "couch";
                                });
                              },
                              child: Container(
                                width: 120,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFFF4D8D)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 2.5,
                                  ),
                                ),
                                child: furniture.imageUrl != null && furniture.imageUrl!.startsWith("assets/")
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.asset(
                                          furniture.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Center(
                                              child: Text(
                                                furniture.emoji,
                                                style: const TextStyle(fontSize: 48),
                                              ),
                                            );
                                          },
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          furniture.emoji,
                                          style: const TextStyle(fontSize: 48),
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTab(IconData icon, bool isActive) {
    return Container(
      width: 60,
      height: 48,
      decoration: BoxDecoration(
        color: isActive ? Colors.black : const Color(0xFF7CB342),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  Widget _buildIsometricRoom(Map<String, dynamic> room) {
    return Center(
      child: CustomPaint(
        size: Size(
          MediaQuery.of(context).size.width - 40,
          MediaQuery.of(context).size.height * 0.5,
        ),
        painter: IsometricRoomPainter(
          wallColor: room['color'],
          floorColor: room['floorColor'],
        ),
      ),
    );
  }

  Widget _buildFurnitureWidget(FurnitureItem furniture, bool isDragging) {
    return Container(
      width: furniture.width,
      height: furniture.height,
      decoration: BoxDecoration(
        color: isDragging ? Colors.white.withOpacity(0.8) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: isDragging
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: furniture.imageUrl != null && furniture.imageUrl!.startsWith("assets/")
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                furniture.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      furniture.emoji,
                      style: const TextStyle(fontSize: 36),
                    ),
                  );
                },
              ),
            )
          : Center(
              child: Text(
                furniture.emoji,
                style: const TextStyle(fontSize: 36),
              ),
            ),
    );
  }

  Offset _transformTapPosition(Offset tapPosition) {
    // Get the inverse transformation matrix to convert tap coords to content coords
    final Matrix4 invertedMatrix = Matrix4.inverted(_transformationController.value);

    // Apply inverse transformation
    final Vector3 position = invertedMatrix.transform3(Vector3(tapPosition.dx, tapPosition.dy, 0));

    // Account for container margin (20px horizontal)
    return Offset(position.x - 20, position.y);
  }

  void _placeFurniture(Offset position) {
    if (_selectedFurniture == null) return;

    // Transform tap position to content coordinates
    final transformedPosition = _transformTapPosition(position);

    // For floor-only items like couch, validate position is on floor
    if (_selectedFurniture!.id == "couch" && _roomContainerSize != Size.zero) {
      if (!_isPositionOnFloor(transformedPosition, _roomContainerSize)) {
        // Show feedback that placement is not allowed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couch can only be placed on the floor!'),
            duration: Duration(seconds: 1),
            backgroundColor: Color(0xFFFF4D8D),
          ),
        );
        return;
      }
    }

    final placedId = DateTime.now().millisecondsSinceEpoch.toString();
    final newFurniture = PlacedFurniture(
      furnitureId: _selectedFurniture!.id,
      furnitureType: _selectedFurniture!.type,
      x: _selectedFurniture!.id == "couch"
          ? _snapToGrid(Offset(
                  transformedPosition.dx - (_selectedFurniture!.width / 2),
                  transformedPosition.dy - (_selectedFurniture!.height / 2),
                )).dx
          : transformedPosition.dx - (_selectedFurniture!.width / 2),
      y: _selectedFurniture!.id == "couch"
          ? _snapToGrid(Offset(
                  transformedPosition.dx - (_selectedFurniture!.width / 2),
                  transformedPosition.dy - (_selectedFurniture!.height / 2),
                )).dy
          : transformedPosition.dy - (_selectedFurniture!.height / 2),
      placedId: placedId,
    );

    setState(() {
      _placedFurniture.add(newFurniture);
      _selectedFurniture = null;
      _showGrid = false;
    });

    _saveFurnitureToFirebase();
  }

  void _updateFurniturePosition(String placedId, double x, double y) {
    final index =
        _placedFurniture.indexWhere((f) => f.placedId == placedId);
    if (index != -1) {
      setState(() {
        _placedFurniture[index] = PlacedFurniture(
          furnitureId: _placedFurniture[index].furnitureId,
          furnitureType: _placedFurniture[index].furnitureType,
          x: _placedFurniture[index].furnitureId == "couch"
              ? _snapToGrid(Offset(x, y)).dx
              : x,
          y: _placedFurniture[index].furnitureId == "couch"
              ? _snapToGrid(Offset(x, y)).dy
              : y,
          placedId: placedId,
        );
      });
      _saveFurnitureToFirebase();
    }
  }

  Future<void> _saveFurnitureToFirebase() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;
    if (houseId == null) return;

    final roomName = _rooms[_currentRoomIndex]['name'];

    await FirebaseFirestore.instance
        .collection('houses')
        .doc(houseId)
        .collection('furniture')
        .doc(roomName.toLowerCase().replaceAll(' ', '_'))
        .set({
      'roomName': roomName,
      'furniture': _placedFurniture.map((f) => f.toMap()).toList(),
    });
  }

  Future<void> _loadFurnitureForRoom() async {
    final houseProvider = Provider.of<HouseProvider>(context, listen: false);
    final houseId = houseProvider.currentHouseId;
    if (houseId == null) return;

    final roomName = _rooms[_currentRoomIndex]['name'];

    final doc = await FirebaseFirestore.instance
        .collection('houses')
        .doc(houseId)
        .collection('furniture')
        .doc(roomName.toLowerCase().replaceAll(' ', '_'))
        .get();

    if (doc.exists) {
      final data = doc.data();
      if (data != null && data['furniture'] != null) {
        setState(() {
          _placedFurniture = (data['furniture'] as List)
              .map((f) => PlacedFurniture.fromMap(f as Map<String, dynamic>))
              .toList();
        });
      }
    } else {
      setState(() {
        _placedFurniture = [];
      });
    }
  }

  Widget _buildNavIcon(IconData icon, bool isActive) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF1B8D) : Colors.transparent,
        shape: BoxShape.circle,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.white : Colors.white60,
        size: 36,
      ),
    );
  }

  Widget _buildBeemoNavIcon(bool isActive) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFF1B8D) : Colors.transparent,
        shape: BoxShape.circle,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Center(
          child: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Center(child: BeemoLogo(size: 36)),
      )),
    );
  }
}

// Simplified Isometric Room Painter for single room view
class IsometricRoomPainter extends CustomPainter {
  final Color wallColor;
  final Color floorColor;

  IsometricRoomPainter({
    required this.wallColor,
    required this.floorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 3;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final roomWidth = size.width * 0.8;
    final roomDepth = size.width * 0.6;
    final roomHeight = size.height * 0.5;

    // Floor (diamond shape)
    final floorPath = Path();
    floorPath.moveTo(centerX, centerY + roomHeight * 0.3);
    floorPath.lineTo(centerX + roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);
    floorPath.lineTo(centerX, centerY - roomDepth / 2 + roomHeight * 0.3);
    floorPath.lineTo(centerX - roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);
    floorPath.close();

    paint.color = floorColor;
    canvas.drawPath(floorPath, paint);

    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.5;
    canvas.drawPath(floorPath, paint);

    // Left wall
    paint.style = PaintingStyle.fill;
    final leftWallPath = Path();
    leftWallPath.moveTo(centerX - roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);
    leftWallPath.lineTo(centerX, centerY - roomDepth / 2 + roomHeight * 0.3);
    leftWallPath.lineTo(centerX, centerY - roomDepth / 2 - roomHeight * 0.5);
    leftWallPath.lineTo(centerX - roomWidth / 2, centerY - roomDepth / 4 - roomHeight * 0.5);
    leftWallPath.close();

    paint.color = wallColor.withOpacity(0.7);
    canvas.drawPath(leftWallPath, paint);

    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    canvas.drawPath(leftWallPath, paint);

    // Right wall
    paint.style = PaintingStyle.fill;
    final rightWallPath = Path();
    rightWallPath.moveTo(centerX, centerY - roomDepth / 2 + roomHeight * 0.3);
    rightWallPath.lineTo(centerX + roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);
    rightWallPath.lineTo(centerX + roomWidth / 2, centerY - roomDepth / 4 - roomHeight * 0.5);
    rightWallPath.lineTo(centerX, centerY - roomDepth / 2 - roomHeight * 0.5);
    rightWallPath.close();

    paint.color = wallColor;
    canvas.drawPath(rightWallPath, paint);

    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    canvas.drawPath(rightWallPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Grid Painter for furniture placement - isometric grid aligned with floor
class GridPainter extends CustomPainter {
  final double gridSize;

  GridPainter(this.gridSize);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final roomWidth = size.width * 0.8;
    final roomDepth = size.width * 0.6;
    final roomHeight = size.height * 0.5;

    // Floor diamond points
    final bottom = Offset(centerX, centerY + roomHeight * 0.3);
    final right = Offset(centerX + roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);
    final top = Offset(centerX, centerY - roomDepth / 2 + roomHeight * 0.3);
    final left = Offset(centerX - roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3);

    final paint = Paint()
      ..color = const Color(0xFFFF4D8D).withOpacity(0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw isometric grid lines parallel to the diamond edges
    final numLines = 20; // Number of grid lines in each direction

    // Lines parallel to left-top edge (going from bottom-left to top-right)
    for (int i = -numLines; i <= numLines; i++) {
      final t = i / numLines;

      // Start from bottom edge and move parallel to left-top edge
      final startX = centerX + (roomWidth / 2) * t;
      final startY = bottom.dy + (right.dy - bottom.dy) * t;

      final endX = centerX + (roomWidth / 2) * t - roomWidth / 2;
      final endY = startY + (left.dy - bottom.dy);

      // Only draw if line intersects with the diamond
      final start = Offset(startX, startY);
      final end = Offset(endX, endY);

      canvas.drawLine(start, end, paint);
    }

    // Lines parallel to right-top edge (going from bottom-right to top-left)
    for (int i = -numLines; i <= numLines; i++) {
      final t = i / numLines;

      // Start from bottom edge and move parallel to right-top edge
      final startX = centerX + (roomWidth / 2) * t;
      final startY = bottom.dy + (left.dy - bottom.dy) * t;

      final endX = centerX + (roomWidth / 2) * t + roomWidth / 2;
      final endY = startY + (right.dy - bottom.dy);

      // Only draw if line intersects with the diamond
      final start = Offset(startX, startY);
      final end = Offset(endX, endY);

      canvas.drawLine(start, end, paint);
    }

    // Draw floor boundary highlight for visibility
    final floorPath = Path();
    floorPath.moveTo(bottom.dx, bottom.dy);
    floorPath.lineTo(right.dx, right.dy);
    floorPath.lineTo(top.dx, top.dy);
    floorPath.lineTo(left.dx, left.dy);
    floorPath.close();

    final highlightPaint = Paint()
      ..color = const Color(0xFFFF4D8D).withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(floorPath, highlightPaint);

    // Draw floor border
    final borderPaint = Paint()
      ..color = const Color(0xFFFF4D8D).withOpacity(0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(floorPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
