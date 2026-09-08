import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://yypcgfobopfqwwltmmex.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl5cGNnZm9ib3BmcXd3bHRtbWV4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5MTgwNzIsImV4cCI6MjEwMjQ5NDA3Mn0._L9BOhOcIEtVlK0AQTpCbXbTFwNApHxmy5XjVpDH2bQ',
  );

  runApp(const MeuPDVCantina());
}

class MeuPDVCantina extends StatelessWidget {
  const MeuPDVCantina({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cantina PDV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(), 
    );
  }
}
