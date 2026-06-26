import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/log_widgets.dart';

class CafeLogsPage extends StatelessWidget {
  const CafeLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("سجل عمليات الكافيهات", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('cafe_logs')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var logs = snapshot.data!.docs;
          if (logs.isEmpty) return const Center(child: Text("لا توجد سجلات حالياً", style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              var log = logs[index].data() as Map<String, dynamic>;
              DateTime time = (log['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

              return ActivityLogCard(
                user: log['cafeName'] ?? "كافيه",
                action: log['action'] ?? "",
                details: "بواسطة: ${log['adminEmail']}\n${log['details']}",
                timestamp: time,
                icon: Icons.business_center_rounded,
                color: Colors.blueGrey,
              );
            },
          );
        },
      ),
    );
  }
}
