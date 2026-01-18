import 'package:flutter/material.dart';

/// Design Tokens for consistency and relative scaling
class UIConfig {
  static const double gapXS = 4.0;
  static const double gapS = 8.0;
  static const double gapM = 16.0;
  static const double gapL = 24.0;
  static const double gapXL = 32.0;

  static const double radiusM = 12.0;
  static const double radiusL = 20.0;
  
  static const Color surface = Color(0xFFFBFBFE);
  static const Color cardBorder = Color(0xFFEDF0F7);
  static const Color brandPrimary = Color(0xFF1A1A1A); // High-end, focus-oriented black
  static const Color textBody = Color(0xFF4B5563);
  static const Color purposeHighlight = Color(0xFF6366F1);
}

void main() => runApp(const DissectApp());

class DissectApp extends StatelessWidget {
  const DissectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Public Sans', // Or Inter
        colorSchemeSeed: UIConfig.brandPrimary,
        scaffoldBackgroundColor: UIConfig.surface,
      ),
      home: const DissectHomePage(),
    );
  }
}

class DissectHomePage extends StatelessWidget {
  const DissectHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final double horizontalInset = MediaQuery.of(context).size.width * 0.05;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Purpose Overview", style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: UIConfig.gapL),
        children: [
          // 1. DISSECTION HERO: The "Intentionality" Gauge
          const IntentionalityHero(
            totalSpent: 4250.00,
            purposeMapped: 3800.00,
          ),

          const SizedBox(height: UIConfig.gapXL),

          // 2. PURPOSE DISTRIBUTION (The "What & Where")
          const SectionLabel(label: "Spending by Purpose"),
          const PurposeGrid(),

          const SizedBox(height: UIConfig.gapXL),

          // 3. THE DISSECTOR FEED (Recent Receipt Line-Items)
          const SectionLabel(label: "Recent Dissections"),
          const ReceiptDissectorItem(
            merchant: "Whole Foods",
            total: 124.50,
            date: "Today",
            items: [
              {"name": "Organic Kale", "purpose": "Wellness", "price": 4.50},
              {"name": "Ribeye Steak", "purpose": "Fine Dining", "price": 45.00},
              {"name": "Dish Soap", "purpose": "Household Maintenance", "price": 8.00},
            ],
          ),
        ],
      ),
    );
  }
}

// --- SPECIALIZED COMPONENTS ---

class IntentionalityHero extends StatelessWidget {
  final double totalSpent;
  final double purposeMapped;

  const IntentionalityHero({super.key, required this.totalSpent, required this.purposeMapped});

  @override
  Widget build(BuildContext context) {
    final double alignmentScore = (purposeMapped / totalSpent) * 100;

    return Container(
      padding: const EdgeInsets.all(UIConfig.gapL),
      decoration: BoxDecoration(
        color: UIConfig.brandPrimary,
        borderRadius: BorderRadius.circular(UIConfig.radiusL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Intentionality Score", style: TextStyle(color: Colors.white60, fontSize: 14)),
          const SizedBox(height: UIConfig.gapXS),
          Text("${alignmentScore.toInt()}%", 
            style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
          const SizedBox(height: UIConfig.gapM),
          Text(
            "You have linked \$${purposeMapped.toInt()} of your spending to specific life purposes this month.",
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class PurposeGrid extends StatelessWidget {
  const PurposeGrid({super.key});

  @override
  Widget build(BuildContext context) {
    // Example purposes - in a real app these are user-defined
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: UIConfig.gapM,
      crossAxisSpacing: UIConfig.gapM,
      childAspectRatio: 1.4,
      children: const [
        PurposeCard(title: "Wellness", amount: 840, icon: Icons.favorite_border, color: Colors.lightGreen),
        PurposeCard(title: "Productivity", amount: 1200, icon: Icons.bolt, color: Colors.blueAccent),
        PurposeCard(title: "Connection", amount: 450, icon: Icons.group_outlined, color: Colors.orangeAccent),
        PurposeCard(title: "Legacy", amount: 300, icon: Icons.auto_awesome, color: Colors.purpleAccent),
      ],
    );
  }
}

class PurposeCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;

  const PurposeCard({super.key, required this.title, required this.amount, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(UIConfig.gapM),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UIConfig.radiusM),
        border: Border.all(color: UIConfig.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text("\$${amount.toInt()}", style: TextStyle(color: UIConfig.textBody, fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }
}

class ReceiptDissectorItem extends StatelessWidget {
  final String merchant;
  final double total;
  final String date;
  final List<Map<String, dynamic>> items;

  const ReceiptDissectorItem({super.key, required this.merchant, required this.total, required this.date, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UIConfig.radiusM),
        border: Border.all(color: UIConfig.cardBorder),
      ),
      child: ExpansionTile(
        title: Text(merchant, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(date, style: const TextStyle(fontSize: 12)),
        trailing: Text("\$${total.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900)),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: UIConfig.gapM, vertical: UIConfig.gapM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("LINE-ITEM DISSECTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: UIConfig.gapS),
                ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: UIConfig.gapS),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text(item['purpose'], style: const TextStyle(fontSize: 11, color: UIConfig.purposeHighlight)),
                          ],
                        ),
                      ),
                      Text("\$${item['price'].toStringAsFixed(2)}", style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                )),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String label;
  const SectionLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: UIConfig.gapS, left: UIConfig.gapXS),
      child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.1)),
    );
  }
}