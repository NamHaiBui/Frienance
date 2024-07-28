import 'package:flutter/material.dart';

class DynamicScaffold extends StatefulWidget {
  const DynamicScaffold({
    super.key,
    required this.body,
  });
  final Widget body;
  @override
  State<DynamicScaffold> createState() => _DynamicScaffoldState();
}

class _DynamicScaffoldState extends State<DynamicScaffold> {
  bool _isMenuOpen = false;

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Dynamic AppBar Template'),
        elevation: 1,
        leading: const Padding(
            padding: EdgeInsets.all(8.0), child: Icon(Icons.person)
            // Image.network(
            //   'https://via.placeholder.com/50?text=Logo',
            //   fit: BoxFit.contain,
            // ),
            ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.blue),
            onPressed: _toggleMenu,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(child: widget.body),
              )
            ],
          ),
          if (_isMenuOpen) _buildUserMenu(),
        ],
      ),
    );
  }

  Widget _buildUserMenu() {
    return Positioned(
      top: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300), // Add animation
        width: _isMenuOpen ? 200 : 0, // Animate width
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.5),
              spreadRadius: 5,
              blurRadius: 7,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                // Handle profile action
                _toggleMenu();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                // Handle settings action
                _toggleMenu();
              },
            ),
            ListTile(
              leading: const Icon(Icons.help),
              title: const Text('Help'),
              onTap: () {
                // Handle help action
                _toggleMenu();
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text('Logout'),
              onTap: () {
                // Handle logout action
                _toggleMenu();
              },
            ),
          ],
        ),
      ),
    );
  }
}
