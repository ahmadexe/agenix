import 'package:agenix/agenix.dart';
import 'package:flutter/material.dart';

class FetchMessagesScreen extends StatefulWidget {
  const FetchMessagesScreen({super.key});

  @override
  State<FetchMessagesScreen> createState() => _FetchMessagesScreenState();
}

class _FetchMessagesScreenState extends State<FetchMessagesScreen> {
  List<AgentMessage>? messages;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fetch Conversation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            messages == null
                ? ElevatedButton(
                  onPressed: () async {
                    final messages = await Agent().getMessages(
                      conversationId: '1',
                    );
                    setState(() {
                      this.messages = messages;
                    });
                  },
                  child: const Text('Fetch Conversation'),
                )
                : ListView.builder(
                  itemCount: messages!.length,
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    final message = messages![index];
                    return ListTile(
                      title: Text(message.content),
                      subtitle: Text(message.generatedAt.toString()),
                    );
                  },
                ),
      ),
    );
  }
}
