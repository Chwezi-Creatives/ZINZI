import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:io';
import 'onboard.dart';

class NutritionChatApp extends StatefulWidget {
  const NutritionChatApp({Key? key}) : super(key: key);

  @override
  State<NutritionChatApp> createState() => _NutritionChatAppState();
}

class _NutritionChatAppState extends State<NutritionChatApp> {
  bool isDarkMode = false;

  // Colors
  static const Color lightScaffoldBackgroundColor = Color(0xFFF0F4F7);
  static const Color darkScaffoldBackgroundColor = Color(0xFF1E1E1E);
  static const Color appBarColorLight = Color(0xFF00796B);
  static const Color appBarColorDark = Color(0xFF00796B);
  static const Color userBubbleColorLight = Color(0xFF128C7E);
  static const Color userBubbleColorDark = Color(0xFF25D366);
  static const Color botBubbleColorDark = Color(0xFF303030);
  static final Color botBubbleColorLight = Colors.grey[200] as Color;
  static const Color inputFieldColorLight = Color(0xFFFFFFFF);
  static const Color inputFieldColorDark = Color(0xFF272727);
  static const Color inputTextColorLight = Colors.black87;
  static const Color inputTextColorDark = Colors.white;
  static const Color hintTextColorLight = Colors.grey;
  static const Color hintTextColorDark = Colors.grey;
  static const Color sendButtonColor = Color(0xFF00796B);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nutrition Chat Agent',
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: lightScaffoldBackgroundColor,
        textTheme: GoogleFonts.robotoTextTheme(
          const TextTheme(
            bodyMedium: TextStyle(color: Colors.black87),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: appBarColorLight,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(color: hintTextColorLight),
        ),
        cardTheme: const CardTheme(
          color: inputFieldColorLight,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: darkScaffoldBackgroundColor,
        textTheme: GoogleFonts.robotoTextTheme(
          const TextTheme(
            bodyMedium: TextStyle(color: Colors.white),
          ), // Added missing parenthesis here
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: appBarColorDark,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(color: hintTextColorDark),
        ),
        cardTheme: const CardTheme(
          color: inputFieldColorDark,
        ),
      ),
      home: ChatScreen(
        onThemeToggle: () => setState(() => isDarkMode = !isDarkMode),
      ),
    );
  }
}

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
  final FlutterTts _flutterTts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isLoading = false;
  bool _isListening = false;
  final List<String> _ttsQueue = [];
  bool _isSpeaking = false;
  final String webhookUrl =
      'https://chwezi.app.n8n.cloud/webhook/fc1e9b92-2a76-4496-90a1-f590c3fcbc53';

  @override
  void initState() {
    super.initState();
    _messages.add(const ChatMessage(
      text: 'Hi! I\'m your Nutrition Chat Agent. How can I assist you today?',
      isUser: false,
    ));
    _initializeTTS();
  }

  Future<void> _initializeTTS() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setVolume(1.0);

    if (Platform.isAndroid) {
      await _flutterTts.setEngine("com.google.android.tts");
    } else if (Platform.isIOS) {
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers
        ],
      );
    }
  }

  String _enhanceTextWithSSML(String text) {
    return '''
    <speak>
      <prosody rate="medium" pitch="medium">${text.replaceAll('&', '&').replaceAll('<', '<').replaceAll('>', '>')}</prosody>
    </speak>
    ''';
  }

  List<String> _chunkText(String text) {
    List<String> sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    List<String> chunks = [];
    String currentChunk = '';
    const maxChunkLength = 150;

    for (String sentence in sentences) {
      if (sentence.length > maxChunkLength) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk);
          currentChunk = '';
        }
        List<String> words = sentence.split(' ');
        String tempChunk = '';
        for (String word in words) {
          if ((tempChunk.length + word.length + 1) < maxChunkLength) {
            tempChunk += (tempChunk.isEmpty ? '' : ' ') + word;
          } else {
            chunks.add(tempChunk);
            tempChunk = word;
          }
        }
        if (tempChunk.isNotEmpty) chunks.add(tempChunk);
      } else if ((currentChunk.length + sentence.length + 1) < maxChunkLength) {
        currentChunk += (currentChunk.isEmpty ? '' : ' ') + sentence;
      } else {
        chunks.add(currentChunk);
        currentChunk = sentence;
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk);
    }

    return chunks.where((chunk) => chunk.trim().isNotEmpty).toList();
  }

  Future<void> _playSound(String assetPath) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setSource(AssetSource(assetPath));
      await _audioPlayer.resume();
    } catch (e) {
      print("Error playing sound '$assetPath': $e");
    }
  }

  Future<void> _playPreSpeechSound() async {
    await _playSound('sounds/notification.mp3');
  }

  Future<void> _playPostSpeechSound() async {
    await _playSound('sounds/complete.mp3');
  }

  void _addToTTSQueue(String text) {
    _ttsQueue.add(text);
    if (!_isSpeaking) {
      _processTTSQueue();
    }
  }

  Future<void> _processTTSQueue() async {
    if (_ttsQueue.isEmpty || !_isSpeaking) {
      _isSpeaking = false;
      return;
    }

    _isSpeaking = true;
    String nextText = _ttsQueue.removeAt(0);

    _flutterTts.setCompletionHandler(() async {
      await _playPostSpeechSound();
      if (_ttsQueue.isNotEmpty) {
        _processTTSQueue();
      } else {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    _flutterTts.setErrorHandler((msg) {
      print("TTS Error: $msg");
      setState(() {
        _isSpeaking = false;
      });
      _ttsQueue.clear();
    });

    try {
      await _playPreSpeechSound();
      await _flutterTts.speak(nextText);
    } catch (e) {
      print("Error initiating TTS speak: $e");
      setState(() {
        _isSpeaking = false;
      });
      _ttsQueue.clear();
    }
  }

  Future<void> _sendMessage(String message) async {
    message = message.trim();
    if (message.isEmpty) return;

    final userMessage = ChatMessage(text: message, isUser: true);

    _controller.clear();
    setState(() {
      _isLoading = true;
      _messages.add(userMessage);
    });

    _playSound('sounds/send1.mp3');
    _scrollToBottom();

    try {
      final response = await http
          .post(
            Uri.parse(webhookUrl),
            headers: {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'message': message}),
          )
          .timeout(const Duration(seconds: 20));

      String botResponseText;
      if (response.statusCode == 200) {
        try {
          final responseBody = utf8.decode(response.bodyBytes);
          if (responseBody.isNotEmpty) {
            final data = jsonDecode(responseBody);
            if (data != null &&
                data is Map &&
                data.containsKey('output') &&
                data['output'] is String) {
              botResponseText = data['output'];
            } else {
              botResponseText = 'Received unclear data from server.';
              print("Server Response format unexpected: $responseBody");
            }
          } else {
            botResponseText = 'Received an empty response from the server.';
          }
        } catch (e) {
          botResponseText = 'Error decoding server response.';
          print("JSON Decode Error: $e");
          print("Received Body: ${response.body}");
        }
      } else {
        botResponseText =
            'Oops! Server error. Status: ${response.statusCode}. Body: ${response.body}';
        print("Server Error: ${response.statusCode}, Body: ${response.body}");
      }
      _addBotMessage(botResponseText);
    } catch (e) {
      print("Network/Timeout Error: $e");
      _addBotMessage('Error connecting to Sensei: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _scrollToBottom();
    }
  }

  void _addBotMessage(String text) {
    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: false));
    });

    List<String> chunks = _chunkText(text);
    for (String chunk in chunks) {
      _addToTTSQueue(chunk);
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('Speech status: $status');
          if (status == stt.SpeechToText.listeningStatus) {
            setState(() => _isListening = true);
          } else {
            if (_isListening) {
              setState(() => _isListening = false);
            }
          }
        },
        onError: (error) {
          print('Speech error: $error');
          setState(() => _isListening = false);
        },
      );

      if (available) {
        _speech.listen(
          onResult: (result) {
            if (mounted) {
              setState(() {
                _controller.text = result.recognizedWords;
                _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: _controller.text.length));
              });
            }
          },
          listenFor: const Duration(seconds: 15),
          pauseFor: const Duration(seconds: 3),
          localeId: 'en_US',
        );
      } else {
        print("Speech recognition not available.");
        setState(() => _isListening = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    _speech.cancel();
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => LandingPage()),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SENSEI',
              style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => LandingPage()),
              );
            },
          ),
          actions: [
            IconButton(
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode
                    : Icons.dark_mode,
              ),
              onPressed: widget.onThemeToggle,
              tooltip: 'Toggle Theme',
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return AnimatedChatBubble(
                    message: _messages[index],
                    key: ValueKey(index),
                  );
                },
              ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.teal,
                      child:
                          Icon(Icons.smart_toy, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Sensei is typing...",
                      style: TextStyle(
                        color: Colors.teal,
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
            _buildInputField(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final inputFieldBgColor = Theme.of(context).cardTheme.color ??
        (isDarkMode
            ? _NutritionChatAppState.inputFieldColorDark
            : _NutritionChatAppState.inputFieldColorLight);
    final inputTextColor = Theme.of(context).textTheme.bodyMedium?.color ??
        (isDarkMode ? Colors.white : Colors.black87);
    final hintColor = Theme.of(context).hintColor;
    final iconColor = _NutritionChatAppState.sendButtonColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: inputFieldBgColor,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 2,
            color: Colors.black.withOpacity(0.05),
          )
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            /*IconButton(
              icon: Icon(
                _isListening ? Icons.mic_off : Icons.mic,
                color: iconColor,
              ),
              onPressed: _toggleListening,
              tooltip: _isListening ? 'Stop listening' : 'Start listening',
            ),*/
            Expanded(
              child: TextField(
                controller: _controller,
                style: TextStyle(color: inputTextColor),
                decoration: InputDecoration(
                  hintText: 'Ask Sensei...',
                  hintStyle: TextStyle(color: hintColor.withOpacity(0.8)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 10.0,
                  ),
                  isDense: true,
                ),
                onSubmitted: _sendMessage,
                textInputAction: TextInputAction.send,
                maxLines: 5,
                minLines: 1,
                keyboardType: TextInputType.multiline,
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                return IconButton(
                  icon: const Icon(
                    Icons.send,
                    color: _NutritionChatAppState.sendButtonColor,
                  ),
                  onPressed: value.text.trim().isNotEmpty && !_isLoading
                      ? () => _sendMessage(_controller.text)
                      : null,
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

class ChatMessage {
  final String text;
  final bool isUser;

  const ChatMessage({
    required this.text,
    required this.isUser,
  });
}

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
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    final beginOffset = widget.message.isUser
        ? const Offset(0.5, 0.1)
        : const Offset(-0.5, 0.1);

    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
      backgroundColor: Colors.teal,
      child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
    );
    final userAvatar = CircleAvatar(
      radius: 14,
      backgroundColor: Colors.grey.shade600,
      child: const Icon(Icons.person, color: Colors.white, size: 18),
    );

    final MainAxisAlignment rowMainAxisAlignment =
        widget.message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.0),
          child: Row(
            mainAxisAlignment: rowMainAxisAlignment,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!widget.message.isUser)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: botAvatar,
                ),
              Flexible(
                child: Container(
                  margin: EdgeInsets.only(
                    left: widget.message.isUser ? 40.0 : 0,
                    right: widget.message.isUser ? 0 : 40.0,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14.0,
                    vertical: 10.0,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18.0),
                      topRight: const Radius.circular(18.0),
                      bottomLeft: widget.message.isUser
                          ? const Radius.circular(18.0)
                          : const Radius.circular(4.0),
                      bottomRight: widget.message.isUser
                          ? const Radius.circular(4.0)
                          : const Radius.circular(18.0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SelectableText(
                    widget.message.text,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14.0,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
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
