//cspell:disable
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Keep for other potential uses like clipboard
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io'; // Keep for Platform checks if needed elsewhere, otherwise removable
// Assuming 'onboard.dart' exists and contains a LandingPage widget
// If not, you might need to replace `LandingPage()` with a relevant widget or remove the back navigation.
import 'onboard.dart'; // Make sure this import points to your actual landing page file

// Main App Widgethi 
class NutritionChatApp extends StatefulWidget {
  const NutritionChatApp({Key? key}) : super(key: key);

  @override
  State<NutritionChatApp> createState() => _NutritionChatAppState();
}

class _NutritionChatAppState extends State<NutritionChatApp> {
  bool isDarkMode = false;

  // --- Color Constants ---
  // Light Theme
  static const Color lightScaffoldBackgroundColor = Color(0xFFF0F4F7);
  static const Color appBarColorLight = Color(0xFF00796B); // Teal variant
  static const Color userBubbleColorLight =
      Color(0xFF128C7E); // WhatsApp Teal Green
  static final Color botBubbleColorLight = Colors.grey[200]!; // Light Grey
  static const Color inputFieldColorLight = Color(0xFFFFFFFF); // White
  static const Color inputTextColorLight = Colors.black87;
  static const Color hintTextColorLight = Colors.grey;
  static const Color sendButtonColorLight = Color(0xFF00796B); // Teal variant

  // Dark Theme
  static const Color darkScaffoldBackgroundColor =
      Color(0xFF121212); // Dark Grey
  static const Color appBarColorDark = Color(0xFF004D40); // Darker Teal
  static const Color userBubbleColorDark =
      Color(0xFF005C4B); // Dark Greenish Teal
  static const Color botBubbleColorDark =
      Color(0xFF262D31); // Very Dark Grey/Blue
  static const Color inputFieldColorDark =
      Color(0xFF1E1E1E); // Slightly Lighter Dark
  static const Color inputTextColorDark = Colors.white;
  static const Color hintTextColorDark = Colors.grey;
  static const Color sendButtonColorDark =
      Color(0xFF00796B); // Teal variant (consistent)
  // --- End Color Constants ---

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nutrition Chat Agent',
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: lightScaffoldBackgroundColor,
        textTheme: GoogleFonts.robotoTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: inputTextColorLight),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: appBarColorLight,
          foregroundColor: Colors.white, // Color for title and icons
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: TextStyle(color: hintTextColorLight.withOpacity(0.8)),
        ),
        cardTheme: const CardTheme(
          color: inputFieldColorLight, // Used for input field background
        ),
        iconTheme: const IconThemeData(
            color: sendButtonColorLight), // Default icon color
        colorScheme: ColorScheme.fromSeed(
            seedColor: appBarColorLight,
            brightness: Brightness.light,
            primary: appBarColorLight,
            secondary: userBubbleColorLight,
            surface: inputFieldColorLight,
            onSurface: inputTextColorLight,
            background: lightScaffoldBackgroundColor,
            onBackground: inputTextColorLight),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: darkScaffoldBackgroundColor,
        textTheme: GoogleFonts.robotoTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: inputTextColorDark),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: appBarColorDark,
          foregroundColor: Colors.white, // Color for title and icons
          elevation: 1,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: TextStyle(color: hintTextColorDark.withOpacity(0.8)),
        ),
        cardTheme: const CardTheme(
          color: inputFieldColorDark, // Used for input field background
        ),
        iconTheme: const IconThemeData(
            color: sendButtonColorDark), // Default icon color for dark theme
        colorScheme: ColorScheme.fromSeed(
            seedColor: appBarColorDark,
            brightness: Brightness.dark,
            primary: appBarColorDark,
            secondary: userBubbleColorDark,
            surface: inputFieldColorDark,
            onSurface: inputTextColorDark,
            background: darkScaffoldBackgroundColor,
            onBackground: inputTextColorDark),
      ),
      home: ChatScreen(
        onThemeToggle: () => setState(() => isDarkMode = !isDarkMode),
      ),
    );
  }
}

// Chat Screen Widget
class ChatScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const ChatScreen({Key? key, required this.onThemeToggle}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  // Removed TTS, STT, AudioPlayer instances
  bool _isLoading = false;
  final String webhookUrl =
      'https://chwezi.app.n8n.cloud/webhook/fc1e9b92-2a76-4496-90a1-f590c3fcbc53'; // Replace with your actual webhook URL

  @override
  void initState() {
    super.initState();
    // Add initial greeting message
    _messages.add(const ChatMessage(
      text:
          'Hi, i am Sensei your Wellness Coach, ask me anything !',
      isUser: false,
    ));
    // Removed TTS/STT initialization calls
  }

  // Send message to webhook and handle response
  Future<void> _sendMessage(String message) async {
    message = message.trim();
    if (message.isEmpty) return;

    // Removed TTS stop logic

    final userMessage = ChatMessage(text: message, isUser: true);

    _controller.clear(); // Clear input field
    if (mounted) {
      setState(() {
        _isLoading = true; // Show loading indicator
        _messages.add(userMessage); // Add user message to chat
      });
    }

    // Removed sending sound playback
    _scrollToBottom(); // Scroll to show the latest message

    try {
      final response = await http
          .post(
            Uri.parse(webhookUrl),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8'
            }, // Ensure UTF-8
            body: jsonEncode({'message': message}),
          )
          .timeout(const Duration(seconds: 30)); // Increased timeout

      String botResponseText;
      if (response.statusCode == 200) {
        try {
          // Explicitly decode as UTF-8
          final responseBody = utf8.decode(response.bodyBytes);
          if (responseBody.isNotEmpty) {
            final data = jsonDecode(responseBody);
            // Check structure of response (adjust based on your n8n webhook)
            if (data != null &&
                data is Map &&
                data.containsKey('output') &&
                data['output'] is String) {
              botResponseText = data['output'];
            } else if (data != null &&
                data is Map &&
                data.containsKey('response') &&
                data['response'] is String) {
              // Alternative key check
              botResponseText = data['response'];
            } else {
              // If the response is just a plain string in the body
              if (data is String) {
                botResponseText = data;
              } else {
                botResponseText =
                    'Received unclear data structure from server.';
                print("Server Response format unexpected: $responseBody");
              }
            }
          } else {
            botResponseText = 'Received an empty response from the server.';
          }
        } catch (e) {
          // Handle cases where the response might not be JSON but plain text
          final responseBody = utf8.decode(response.bodyBytes);
          if (responseBody.isNotEmpty) {
            botResponseText =
                responseBody; // Treat non-JSON response as plain text
            print("Response was not JSON, treated as plain text.");
          } else {
            botResponseText = 'Error processing server response.';
            print("Response Processing Error: $e");
            print("Received Body (raw): ${response.body}"); // Log raw body
          }
        }
      } else {
        // Handle HTTP errors
        botResponseText = 'Oops! Server error. Status: ${response.statusCode}.';
        print("Server Error: ${response.statusCode}, Body: ${response.body}");
      }
      // Add bot message only if component is still mounted
      if (mounted) _addBotMessage(botResponseText);
    } catch (e) {
      print("Network/Timeout Error: $e");
      // Add error message only if component is still mounted
      if (mounted)
        _addBotMessage(
            'Sorry, I couldn\'t connect to Sensei right now. Please check your connection and try again.');
    } finally {
      // Ensure loading indicator is turned off even if errors occur
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _scrollToBottom(); // Scroll after adding bot message or error
    }
  }

  // Add bot message to UI
  void _addBotMessage(String text) {
    if (!mounted) return; // Check if the widget is still in the tree

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: false));
    });

    // Removed TTS queue logic

    _scrollToBottom();
  }

  // Scroll chat list to the bottom
  void _scrollToBottom() {
    // Ensure scroll controller has clients and scheduling the scroll after the frame build
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          // Double check after callback
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // Removed _toggleListening function

  @override
  void dispose() {
    // Dispose controllers
    _controller.dispose();
    _scrollController.dispose();
    // Removed STT/TTS/AudioPlayer dispose calls
    super.dispose();
  }

  // Build the main chat screen UI
  @override
  Widget build(BuildContext context) {
    // Use PopScope for handling back navigation
    return PopScope(
      canPop: false, // Prevent default back button behavior
      onPopInvoked: (didPop) {
        if (!didPop) {
          // Navigate back to LandingPage with consistent transition
          Navigator.of(context).pushReplacement(LandingPage.createRoute());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SENSEI'), // AppBar title
          centerTitle: true,
          // Back button to navigate to LandingPage
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (context) =>
                        LandingPage()), // Ensure LandingPage exists
              );
            },
            tooltip: 'Go Back',
          ),
          // Theme toggle button
          actions: [
            IconButton(
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              onPressed: widget.onThemeToggle,
              tooltip: 'Toggle Theme',
            ),
          ],
        ),
        body: Column(
          children: [
            // Chat messages list
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  // Use the AnimatedChatBubble for each message
                  return AnimatedChatBubble(
                    message: _messages[index],
                    // Use index or a unique message ID as key for animations
                    key: ValueKey(_messages[index].hashCode + index),
                  );
                },
              ),
            ),
            // Loading indicator when bot is typing
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.teal, // Consistent with bot theme
                      child:
                          Icon(Icons.smart_toy, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Sensei is thinking...",
                      style: TextStyle(
                        color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color
                                ?.withOpacity(0.7) ??
                            Colors.grey[600],
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.teal, // Consistent color
                      ),
                    ),
                  ],
                ),
              ),
            // Input field area
            _buildInputField(),
          ],
        ),
      ),
    );
  }

  // Build the input field widget
  Widget _buildInputField() {
    // Get colors from the current theme
    final inputFieldBgColor = Theme.of(context).cardTheme.color;
    final inputTextColor = Theme.of(context).textTheme.bodyMedium?.color;
    final hintColor = Theme.of(context).inputDecorationTheme.hintStyle?.color;
    final iconColor = Theme.of(context).iconTheme.color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: inputFieldBgColor,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1), // Shadow position
            blurRadius: 2, // Shadow blur
            color: Colors.black.withOpacity(0.05), // Shadow color
          )
        ],
      ),
      child: SafeArea(
        // Ensure input field is above system intrusions (like keyboard)
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.center, // Align items vertically center
          children: [
            // Removed Microphone button
            // Text input field
            Expanded(
              child: TextField(
                controller: _controller,
                style: TextStyle(color: inputTextColor), // Text color
                decoration: InputDecoration(
                  hintText: 'Ask Sensei...', // Placeholder text
                  hintStyle: TextStyle(color: hintColor), // Hint text color
                  border: InputBorder.none, // No border for the text field
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12.0, // Added padding now that mic is gone
                    vertical: 10.0, // Adjust padding for alignment
                  ),
                  isDense: true, // Reduces the vertical height
                ),
                onSubmitted:
                    _sendMessage, // Send message on keyboard submit action
                textInputAction:
                    TextInputAction.send, // Show send button on keyboard
                maxLines: 5, // Allow multiple lines up to 5
                minLines: 1, // Start with a single line
                keyboardType: TextInputType.multiline, // Use multiline keyboard
                textCapitalization:
                    TextCapitalization.sentences, // Capitalize sentences
              ),
            ),
            // Send button - enabled only when text is entered and not loading
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final bool canSend =
                    value.text.trim().isNotEmpty && !_isLoading;
                return IconButton(
                  icon: Icon(
                    Icons.send_rounded,
                    color: canSend
                        ? iconColor
                        : Colors.grey, // Change color when disabled
                  ),
                  onPressed: canSend
                      ? () =>
                          _sendMessage(_controller.text) // Send message on tap
                      : null, // Disable button if no text or loading
                  tooltip: 'Send message',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Data class for Chat Message
class ChatMessage {
  final String text;
  final bool isUser;

  const ChatMessage({
    required this.text,
    required this.isUser,
  });

  // Optional: Override equality and hashCode for ValueKey usage if needed
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isUser == other.isUser;

  @override
  int get hashCode => text.hashCode ^ isUser.hashCode;
}

// Animated Chat Bubble Widget (Updated for Both Bullet Types)
class AnimatedChatBubble extends StatefulWidget {
  final ChatMessage message;
  const AnimatedChatBubble({Key? key, required this.message}) : super(key: key);

  @override
  State<AnimatedChatBubble> createState() => _AnimatedChatBubbleState();
}

class _AnimatedChatBubbleState extends State<AnimatedChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400), // Animation duration
      vsync: this, // Use this state as the ticker provider
    );

    // Define slide-in animation based on whether it's a user or bot message
    final beginOffset = widget.message.isUser
        ? const Offset(0.5, 0.1) // User message slides from right
        : const Offset(-0.5, 0.1); // Bot message slides from left

    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero, // End at the natural position
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic, // Animation curve
    ));

    // Define fade-in animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn, // Animation curve
      ),
    );

    // Start the animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose(); // Dispose animation controller
    super.dispose();
  }

  // --- HELPER FUNCTION TO PARSE AND BUILD MESSAGE CONTENT (HANDLES BOTH BULLET TYPES) ---
  Widget _buildMessageContent(
      BuildContext context, String text, Color textColor) {
    final baseStyle = TextStyle(
      color: textColor,
      fontSize: 14.0,
      height: 1.3,
    );
    final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);

    final lines = text.split('\n');
    final List<Widget> contentWidgets = [];

    // --- Define REGEX patterns for both list types ---
    // Pattern 1: Hyphen bullet "- **Title**: Desc" (2 capture groups: title, description)
    final hyphenBulletPattern = RegExp(r'^\s*-\s*\*\*(.+?)\*\*[:]?\s*(.*)');
    // Pattern 2: Numbered bullet "4. **Title**: Desc" (3 capture groups: number, title, description)
    final numberedBulletPattern =
        RegExp(r'^\s*(\d+\.)\s*\*\*(.+?)\*\*[:]?\s*(.*)');

    // print("Processing text: '''$text'''"); // Debugging

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      // print('  Line $i: "$line"'); // Debugging

      // --- Try matching patterns ---
      final hyphenMatch = hyphenBulletPattern.firstMatch(line);
      final numberedMatch = numberedBulletPattern.firstMatch(line);

      // --- Determine vertical padding ---
      // Use slightly more padding for list items compared to normal text lines
      final listPaddingTop = contentWidgets.isNotEmpty ? 6.0 : 0.0;
      final normalPaddingTop = contentWidgets.isNotEmpty ? 4.0 : 0.0;

      // --- Check which pattern matched (if any) ---
      if (hyphenMatch != null && hyphenMatch.groupCount == 2) {
        // --- Format as HYPHEN bullet ---
        final title = hyphenMatch.group(1)?.trim() ?? '';
        final description = hyphenMatch.group(2)?.trim() ?? '';
        // print('    -> Matched HYPHEN! Title: "$title", Desc: "$description"'); // Debugging

        contentWidgets.add(
          Padding(
            padding: EdgeInsets.only(top: listPaddingTop),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6.0, top: 1.0),
                  child: Text("•", style: boldStyle), // Use bullet symbol
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: baseStyle,
                      children: <TextSpan>[
                        TextSpan(text: title, style: boldStyle),
                        if (description.isNotEmpty)
                          TextSpan(text: ': $description'),
                        if (description.isEmpty)
                          const TextSpan(text: ':'), // Keep colon
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (numberedMatch != null && numberedMatch.groupCount == 3) {
        // --- Format as NUMBERED bullet ---
        final number = numberedMatch.group(1)?.trim() ?? '';
        final title = numberedMatch.group(2)?.trim() ?? '';
        final description = numberedMatch.group(3)?.trim() ?? '';
        // print('    -> Matched NUMBERED! Num: "$number", Title: "$title", Desc: "$description"'); // Debugging

        contentWidgets.add(
          Padding(
            padding: EdgeInsets.only(top: listPaddingTop),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6.0, top: 1.0),
                  child: Text(number, style: boldStyle), // Use captured number
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: baseStyle,
                      children: <TextSpan>[
                        TextSpan(text: title, style: boldStyle),
                        if (description.isNotEmpty)
                          TextSpan(text: ': $description'),
                        if (description.isEmpty)
                          const TextSpan(text: ':'), // Keep colon
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (line.trim().isNotEmpty) {
        // --- Format as NORMAL text ---
        // print('    -> Not a bullet or empty.'); // Debugging
        contentWidgets.add(
          Padding(
            padding:
                EdgeInsets.only(top: normalPaddingTop), // Use normal padding
            child: SelectableText(
              line.trim(),
              style: baseStyle,
            ),
          ),
        );
      }
      // Implicitly ignore empty lines
    }

    if (contentWidgets.isEmpty) {
      // print('  -> No content widgets generated.'); // Debugging
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Align content to the left
      children: contentWidgets,
    );
  }
  // --- END HELPER FUNCTION ---

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Get bubble colors (ensure these constants are accessible)
    final userBubbleColor = isDarkMode
        ? _NutritionChatAppState.userBubbleColorDark
        : _NutritionChatAppState.userBubbleColorLight;
    final botBubbleColor = isDarkMode
        ? _NutritionChatAppState.botBubbleColorDark
        : _NutritionChatAppState.botBubbleColorLight;

    final bubbleColor =
        widget.message.isUser ? userBubbleColor : botBubbleColor;
    final textColor = widget.message.isUser
        ? Colors.white
        : Theme.of(context).textTheme.bodyMedium?.color ??
            (isDarkMode ? Colors.white : Colors.black87);

    final botAvatar = CircleAvatar(
      radius: 14,
      backgroundColor: Colors.teal[700], // Slightly darker teal for avatar
      child:
          const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 18),
    );
    final userAvatar = CircleAvatar(
      radius: 14,
      backgroundColor: Colors.grey.shade600,
      child: const Icon(Icons.person_outline, color: Colors.white, size: 18),
    );

    final MainAxisAlignment rowMainAxisAlignment =
        widget.message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start;

    // Apply animations
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: 5.0), // Vertical spacing between bubbles
          child: Row(
            mainAxisAlignment:
                rowMainAxisAlignment, // Align left for bot, right for user
            crossAxisAlignment:
                CrossAxisAlignment.end, // Align avatar with bottom of bubble
            children: [
              // Show bot avatar on the left for bot messages
              if (!widget.message.isUser)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: botAvatar,
                ),
              // Flexible container for the chat bubble itself
              Flexible(
                child: Container(
                  // Margin to push bubble away from the edge opposite the avatar
                  margin: EdgeInsets.only(
                    left: widget.message.isUser
                        ? 40.0
                        : 0, // Margin left for user
                    right: widget.message.isUser
                        ? 0
                        : 40.0, // Margin right for bot
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0, // Horizontal padding inside bubble
                    vertical: 10.0, // Vertical padding inside bubble
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor, // Bubble background color
                    // Custom border radius for "speech bubble" effect
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18.0),
                      topRight: const Radius.circular(18.0),
                      bottomLeft: widget.message.isUser
                          ? const Radius.circular(
                              18.0) // Rounded bottom-left for user
                          : const Radius.circular(
                              4.0), // Sharp bottom-left for bot
                      bottomRight: widget.message.isUser
                          ? const Radius.circular(
                              4.0) // Sharp bottom-right for user
                          : const Radius.circular(
                              18.0), // Rounded bottom-right for bot
                    ),
                    // Subtle shadow for depth
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  // *** Use the helper function to build the content ***
                  child: _buildMessageContent(
                      context, widget.message.text, textColor),
                ),
              ),
              // Show user avatar on the right for user messages
              if (widget.message.isUser)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: userAvatar,
                ),
            ],
          ),
        ),
      ),
    );
  }
}