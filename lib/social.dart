import 'package:flutter/material.dart';

// Mock data models
class Post {
  final int id;
  final String user;
  final String content;
  final DateTime createdAt;

  Post({required this.id, required this.user, required this.content, required this.createdAt});
}

class Comment {
  final int postId;
  final String user;
  final String content;

  Comment({required this.postId, required this.user, required this.content});
}

// Dummy Data
List<Post> dummyPosts = [
  Post(id: 1, user: "Alice Johnson", content: "Hello everyone! This is my first post about health living!", createdAt: DateTime.now()),
  Post(id: 2, user: "Bob Smith", content: "Loving the new app features and healthy recipes!", createdAt: DateTime.now().subtract(Duration(minutes: 10))),
  Post(id: 3, user: "Charlie Brown", content: "What do you think about the latest nutrition tips?", createdAt: DateTime.now().subtract(Duration(hours: 1))),
];

List<Comment> dummyComments = [
  Comment(postId: 1, user: "Bob Smith", content: "Welcome to the community, Alice!"),
  Comment(postId: 1, user: "Charlie Brown", content: "Excited to see you here!"),
  Comment(postId: 2, user: "Alice Johnson", content: "Thanks for the feedback, Bob!"),
];

// Enhanced User Interface
class SocialMediaScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Community Feed'),
        backgroundColor: Colors.teal[800],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'), // Set the background image
            fit: BoxFit.cover,
          ),
        ),
        child: ListView.builder(
          itemCount: dummyPosts.length,
          itemBuilder: (context, index) {
            return PostCard(post: dummyPosts[index]);
          },
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final Post post;

  PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final postComments = dummyComments.where((comment) => comment.postId == post.id).toList();

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: 4,
      color: Colors.white.withOpacity(0.9), // Light transparency for better visibility
      child: Padding(
        padding: EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.user, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal[800])),
            SizedBox(height: 4),
            Text(post.content, style: TextStyle(color: Colors.teal[800])),
            SizedBox(height: 8),
            Text('${post.createdAt.toLocal()}'.split(' ')[0], style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () {}, // Implement your like functionality here
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.teal, // CTA button color
                    foregroundColor: Colors.white, // Button text color
                  ),
                  child: Text('Like'),
                ),
                TextButton(
                  onPressed: () {
                    _showCommentDialog(context, post.id);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.teal, // CTA button color
                    foregroundColor: Colors.white, // Button text color
                  ),
                  child: Text('Comment'),
                ),
              ],
            ),
            Divider(),
            ...postComments.map((comment) => Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Text('${comment.user}: ${comment.content}', style: TextStyle(color: Colors.teal[800])),
            )) // Display comments
          ],
        ),
      ),
    );
  }

  void _showCommentDialog(BuildContext context, int postId) {
    final TextEditingController _commentController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add a Comment'),
          content: TextField(
            controller: _commentController,
            decoration: InputDecoration(hintText: 'Type your comment here'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Logic to save comment if implemented
                Navigator.of(context).pop();
              },
              child: Text('Submit', style: TextStyle(color: Colors.teal[800])),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.teal[800])),
            ),
          ],
        );
      },
    );
  }
}
