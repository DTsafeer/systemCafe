import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CafeLogsPage extends StatelessWidget {
  const CafeLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("سجل عمليات الكافيهات")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('cafe_logs')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var logs = snapshot.data!.docs;
          if (logs.isEmpty) return const Center(child: Text("لا توجد سجلات حالياً"));

          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              var log = logs[index].data() as Map<String, dynamic>;
              DateTime time = (log['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blueGrey,
                    child: Icon(Icons.history, color: Colors.white),
                  ),
                  title: Text("${log['cafeName']} - ${log['action']}"),
                  subtitle: Text("بواسطة: ${log['adminEmail']}\nالتفاصيل: ${log['details']}"),
                  trailing: Text(
                    DateFormat('MM/dd\nHH:mm').format(time),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}