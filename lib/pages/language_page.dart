import 'package:flutter/material.dart';

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String _selectedLanguage = 'English';

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'af', 'name': 'Afrikaans', 'native': 'Afrikaans'},
    {'code': 'am', 'name': 'Amharic', 'native': 'አማርኛ'},
    {'code': 'ha', 'name': 'Hausa', 'native': 'Hausa'},
    {'code': 'ig', 'name': 'Igbo', 'native': 'Igbo'},
    {'code': 'sw', 'name': 'Swahili', 'native': 'Kiswahili'},
    {'code': 'yo', 'name': 'Yoruba', 'native': 'Yorùbá'},
    {'code': 'zu', 'name': 'Zulu', 'native': 'Zulu'},
    {'code': 'xh', 'name': 'Xhosa', 'native': 'Xhosa'},
    {'code': 'st', 'name': 'Sesotho', 'native': 'Sesotho'},
    {'code': 'sn', 'name': 'Shona', 'native': 'Shona'},
    {'code': 'so', 'name': 'Somali', 'native': 'Somali'},
    {'code': 'ar', 'name': 'Arabic', 'native': 'العربية'},
    {'code': 'fr', 'name': 'French', 'native': 'Français'},
    {'code': 'pt', 'name': 'Portuguese', 'native': 'Português'},
    {'code': 'es', 'name': 'Spanish', 'native': 'Español'},
    {'code': 'de', 'name': 'German', 'native': 'Deutsch'},
    {'code': 'it', 'name': 'Italian', 'native': 'Italiano'},
    {'code': 'zh', 'name': 'Chinese', 'native': '中文'},
    {'code': 'ja', 'name': 'Japanese', 'native': '日本語'},
    {'code': 'ko', 'name': 'Korean', 'native': '한국어'},
    {'code': 'hi', 'name': 'Hindi', 'native': 'हिन्दी'},
    {'code': 'ru', 'name': 'Russian', 'native': 'Русский'},
    {'code': 'tr', 'name': 'Turkish', 'native': 'Türkçe'},
    {'code': 'vi', 'name': 'Vietnamese', 'native': 'Tiếng Việt'},
    {'code': 'th', 'name': 'Thai', 'native': 'ไทย'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Language', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: ListView.builder(
        itemCount: _languages.length,
        itemBuilder: (context, index) {
          final language = _languages[index];
          final isSelected = language['name'] == _selectedLanguage;
          return ListTile(
            title: Text(language['name']!),
            subtitle: Text(language['native']!),
            trailing: isSelected
                ? const Icon(Icons.check, color: Colors.deepPurple)
                : null,
            onTap: () {
              setState(() {
                _selectedLanguage = language['name']!;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Language changed to ${language['name']}')),
              );
            },
          );
        },
      ),
    );
  }
}
