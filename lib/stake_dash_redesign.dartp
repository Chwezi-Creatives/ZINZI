import 'package:flutter/material.dart';

class StakeholderDashboardRedesign extends StatelessWidget {
  const StakeholderDashboardRedesign({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Stakeholder Dashboard'),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.white.withOpacity(0.95),
              BlendMode.dstATop,
            ),
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Welcome to the Stakeholder Dashboard!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal[900]),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Key Metrics',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Total Users: 1000', // Replace with actual data
                          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        ),
                        Text(
                          'Total Orders: 500', // Replace with actual data
                          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        ),
                        Text(
                          'Revenue: \$5000', // Replace with actual data
                          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Placeholder for additional action
                    // You can navigate to other pages or perform other actions
                  },
                  child: Text('View Detailed Analytics', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[800],
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Logout action (assuming you want to implement logout)
                    Navigator.pop(context); // Navigate back to the login page
                  },
                  child: Text('Logout', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[800],
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
