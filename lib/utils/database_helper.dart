import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database?> get database async {
    if (kIsWeb) return null;
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database?> _initDatabase() async {
    if (kIsWeb) return null;

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path = join(await getDatabasesPath(), 'cafe_system.db');
    return await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 8) {
      final tables = ['categories', 'products', 'orders', 'order_items', 'activity_logs', 'expenses', 'payments', 'debts', 'debt_transactions', 'inventory'];
      for (var table in tables) {
        try {
          await db.execute('ALTER TABLE $table ADD COLUMN cafeId TEXT');
        } catch (e) {
          // Column might already exist
        }
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        cafeId TEXT,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        category TEXT,
        imagePath TEXT,
        isAvailable INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        tableNumber TEXT,
        totalAmount REAL NOT NULL,
        orderDate TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        paymentMethod TEXT,
        isArchived INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        orderId INTEGER NOT NULL,
        productName TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (orderId) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');
    await _createLogsTable(db);
    await _createExpensesTable(db);
    await _createPaymentsTable(db);
    await _createDebtsTable(db);
    await _createInventoryTable(db);
  }

  Future<void> _createLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        parentId TEXT,
        userId TEXT,
        userName TEXT,
        action TEXT,
        details TEXT,
        timestamp TEXT
      )
    ''');
  }

  Future<void> _createExpensesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT,
        date TEXT,
        processedBy TEXT
      )
    ''');
  }

  Future<void> _createPaymentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        customerName TEXT,
        amount REAL NOT NULL,
        method TEXT,
        date TEXT,
        tableNum TEXT
      )
    ''');
  }

  Future<void> _createDebtsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        customerName TEXT NOT NULL,
        totalDebt REAL DEFAULT 0,
        totalPaid REAL DEFAULT 0,
        lastUpdate TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        customerName TEXT,
        type TEXT,
        amount REAL,
        date TEXT
      )
    ''');
  }

  Future<void> _createInventoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cafeId TEXT,
        name TEXT NOT NULL,
        quantity REAL DEFAULT 0,
        unit TEXT,
        threshold REAL DEFAULT 5.0
      )
    ''');
  }

  // دالة موحدة لتسجيل النشاطات (سحابي + محلي)
  // تم التعديل ليكون الحفظ السحابي في الخلفية لضمان سرعة التطبيق
  Future<void> logActivity({
    required String cafeId,
    required String parentId,
    required String userId,
    required String userName,
    required String action,
    required String details,
  }) async {
    final timestamp = DateTime.now();
    final logData = {
      'cafeId': cafeId,
      'parentId': parentId,
      'userId': userId,
      'userName': userName,
      'action': action,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };

    // 1. الحفظ المحلي (للعمل بدون إنترنت) - ننتظره لضمان تسجيل العملية محلياً
    try {
      if (!kIsWeb) {
        Database? db = await database;
        await db?.insert('activity_logs', logData);
      }
    } catch (e) { print("Local Log Error: $e"); }

    // 2. الحفظ السحابي - لا ننتظره (Background) لكي لا يتسبب في تأخير الواجهة
    FirebaseFirestore.instance.collection('activity_logs').add({
      ...logData,
      'timestamp': FieldValue.serverTimestamp(),
    }).catchError((e) => print("Cloud Log Error: $e"));
  }

  Future<List<Map<String, dynamic>>> getLocalLogs(String cafeId) async {
    if (kIsWeb) return [];
    Database? db = await database;
    if (db == null) return [];
    return await db.query(
      'activity_logs', 
      where: 'cafeId = ?', 
      whereArgs: [cafeId],
      orderBy: 'timestamp DESC'
    );
  }

  Future<int> upsertInventoryLocal(Map<String, dynamic> item) async {
    if (kIsWeb) return 0;
    Database? db = await database;
    return await db?.insert('inventory', item, conflictAlgorithm: ConflictAlgorithm.replace) ?? 0;
  }

  Future<void> deleteInventoryLocal(String name, String cafeId) async {
    if (kIsWeb) return;
    Database? db = await database;
    await db?.delete('inventory', where: 'name = ? AND cafeId = ?', whereArgs: [name, cafeId]);
  }

  Future<void> updateInventoryQtyLocal(String name, double newQty, String cafeId) async {
    if (kIsWeb) return;
    Database? db = await database;
    await db?.update('inventory', {'quantity': newQty}, where: 'name = ? AND cafeId = ?', whereArgs: [name, cafeId]);
  }

  Future<void> decrementInventoryQtyLocal(String name, double amount, String cafeId) async {
    if (kIsWeb) return;
    Database? db = await database;
    await db?.execute(
      'UPDATE inventory SET quantity = quantity - ? WHERE name = ? AND cafeId = ?',
      [amount, name, cafeId]
    );
  }

  Future<void> clearPendingTableOrdersLocal(String tableName, String cafeId) async {
    if (kIsWeb) return;
    Database? db = await database;
    await db?.delete('orders', where: 'tableNumber = ? AND status = ? AND cafeId = ?', whereArgs: [tableName, 'pending', cafeId]);
  }

  Future<int> insertPayment(Map<String, dynamic> row) async {
    if (kIsWeb) return 0;
    Database? db = await database;
    return await db?.insert('payments', row) ?? 0;
  }

  Future<int> insertExpense(Map<String, dynamic> row) async {
    if (kIsWeb) return 0;
    Database? db = await database;
    return await db?.insert('expenses', row) ?? 0;
  }

  Future<void> updateDebtLocal(String name, double amount, bool isPayment, String cafeId) async {
    if (kIsWeb) return;
    Database? db = await database;
    if (db == null) return;
    
    final List<Map<String, dynamic>> results = await db.query('debts', 
        where: 'LOWER(customerName) = LOWER(?) AND cafeId = ?', 
        whereArgs: [name.trim(), cafeId]);
    
    if (results.isEmpty) {
      await db.insert('debts', {
        'cafeId': cafeId,
        'customerName': name.trim(),
        'totalDebt': isPayment ? 0 : amount,
        'totalPaid': isPayment ? amount : 0,
        'lastUpdate': DateTime.now().toIso8601String()
      });
    } else {
      double currentDebt = (results.first['totalDebt'] as num).toDouble();
      double currentPaid = (results.first['totalPaid'] as num).toDouble();
      
      await db.update('debts', {
        'totalDebt': isPayment ? currentDebt : currentDebt + amount,
        'totalPaid': isPayment ? currentPaid + amount : currentPaid,
        'lastUpdate': DateTime.now().toIso8601String()
      }, where: 'id = ?', whereArgs: [results.first['id']]);
    }

    await db.insert('debt_transactions', {
      'cafeId': cafeId,
      'customerName': name.trim(),
      'type': isPayment ? 'سداد' : 'دين جديد',
      'amount': amount,
      'date': DateTime.now().toIso8601String()
    });
  }

  Future<int> createOrder(Map<String, dynamic> order, List<dynamic> items) async {
    if (kIsWeb) return 0;
    Database? db = await database;
    if (db == null) return 0;
    return await db.transaction((txn) async {
      int orderId = await txn.insert('orders', order);
      for (var item in items) {
        await txn.insert('order_items', {
          'cafeId': order['cafeId'],
          'orderId': orderId,
          'productName': item['name'],
          'quantity': item['quantity'],
          'price': item['price'],
        });
      }
      return orderId;
    });
  }

  Future<List<String>> getCategories(String cafeId) async {
    if (kIsWeb) return ["عام"];
    Database? db = await database;
    if (db == null) return ["عام"];
    final List<Map<String, dynamic>> maps = await db.query('categories', where: 'cafeId = ?', whereArgs: [cafeId]);
    if (maps.isEmpty) return ["عام"];
    return maps.map((map) => map['name'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> queryAllProducts(String cafeId) async {
    if (kIsWeb) return [];
    Database? db = await database;
    if (db == null) return [];
    return await db.query('products', where: 'cafeId = ?', whereArgs: [cafeId]);
  }

  Future<int> insertProduct(Map<String, dynamic> row) async {
    if (kIsWeb) return 0;
    Database? db = await database;
    return await db?.insert('products', row) ?? 0;
  }
}
