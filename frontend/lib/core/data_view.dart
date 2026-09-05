import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'theme.dart';

class DataView extends ConsumerStatefulWidget {
  const DataView({super.key, required this.path, required this.builder});
  final String path;
  final Widget Function(Json, VoidCallback) builder;
  @override
  ConsumerState<DataView> createState() => _DataViewState();
}

class _DataViewState extends ConsumerState<DataView> {
  late Future<Json> future;
  void refresh() {
    if (mounted) {
      setState(() {
        future = ref.read(apiProvider).get(widget.path);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    future = ref.read(apiProvider).get(widget.path);
  }

  @override
  void didUpdateWidget(DataView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(revisionProvider, (_, __) => refresh());
    return FutureBuilder<Json>(
        future: future,
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return GlassCard(
                child: EmptyState(
                    'Could not load this view', errorMessage(snapshot.error!),
                    action: OutlinedButton(
                        onPressed: refresh, child: const Text('Try again'))));
          }
          if (!snapshot.hasData) {
            return const Padding(
                padding: EdgeInsets.all(80),
                child: Center(child: CircularProgressIndicator(color: mint)));
          }
          return widget.builder(snapshot.data!, refresh);
        });
  }
}
