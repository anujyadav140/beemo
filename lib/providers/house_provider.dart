import 'package:flutter/material.dart';
import '../models/house_model.dart';
import '../services/firestore_service.dart';

class HouseProvider extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  House? _currentHouse;
  String? _currentHouseId;
  bool _isLoading = false;
  String? _error;

  House? get currentHouse => _currentHouse;
  String? get currentHouseId => _currentHouseId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasHouse => _currentHouse != null;

  void setCurrentHouseId(String houseId) {
    _currentHouseId = houseId;
    _listenToHouse(houseId);
  }

  void _listenToHouse(String houseId) {
    _firestoreService.getHouseStream(houseId).listen((house) {
      _currentHouse = house;
      notifyListeners();
    });
  }

  Future<String?> createHouse({
    required String name,
    required int bedrooms,
    required int bathrooms,
    required String userName,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      String houseId = await _firestoreService.createHouse(
        name: name,
        bedrooms: bedrooms,
        bathrooms: bathrooms,
        userName: userName,
      );

      setCurrentHouseId(houseId);

      _isLoading = false;
      notifyListeners();
      return houseId;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> joinHouse(String inviteCode, String userName) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _firestoreService.joinHouse(inviteCode, userName);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clear() {
    _currentHouse = null;
    _currentHouseId = null;
    notifyListeners();
  }
}
