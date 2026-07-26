import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Brouillons locaux des écrans de création DEM Pro (commande simple / tournée),
/// pour ne pas perdre la saisie si l'utilisateur quitte l'écran en cours de route.
class DemProDraftStorage {
  static const _orderKey = 'dem_pro_order_draft';
  static const _batchKey = 'dem_pro_batch_draft';

  static Future<void> saveOrderDraft(Map<String, dynamic> draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderKey, jsonEncode(draft));
  }

  static Future<Map<String, dynamic>?> getOrderDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> clearOrderDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_orderKey);
  }

  static Future<void> saveBatchDraft(Map<String, dynamic> draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_batchKey, jsonEncode(draft));
  }

  static Future<Map<String, dynamic>?> getBatchDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_batchKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> clearBatchDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_batchKey);
  }
}
