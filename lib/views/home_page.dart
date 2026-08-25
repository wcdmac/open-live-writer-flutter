import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/blog.dart';
import '../models/blog_post.dart';
import '../state/app_state.dart';
import 'add_account_page.dart';
import 'post_editor_page.dart';

/// Dashboard: blog switcher + post list, mirroring OLW's main window.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.hasAccount &&
          app.posts.isEmpty &&
          !app.loading &&
          app.error == null) {
        app.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.hasAccount) {
      return const AddAccountPage(embedded: true);
    }

    return Scaffold(
      appBar: AppBar(
        title: _BlogSwitcher(app: app),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: app.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: app.loading ? null : () => app.refresh(),
          ),
          IconButton(
            tooltip: 'Manage accounts',
            icon: const Icon(Icons.settings),
            onPressed: () => _openAccountSettings(context, app),
          ),
        ],
      ),
      body: _buildBody(context, app),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.edit),
        label: const Text('New post'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PostEditorPage()),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppState app) {
    if (app.error != null && app.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                app.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => app.refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (app.loading && app.posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (app.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined,
                size: 56, color: Theme.of(context).disabledColor),
            const SizedBox(height: 8),
            Text('No posts yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Create your first post with the button below.'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => app.refresh(),
      child: ListView.separated(
        itemCount: app.posts.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final post = app.posts[index];
          return _PostTile(post: post, app: app);
        },
      ),
    );
  }

  Future<void> _openAccountSettings(BuildContext context, AppState app) async {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Accounts & settings',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...app.accounts.map((account) => ListTile(
                  leading: CircleAvatar(
                    child: Text(account.name.isEmpty
                        ? '?'
                        : account.name[0].toUpperCase()),
                  ),
                  title: Text(account.name),
                  subtitle: Text(
                    '${account.username} • ${account.protocol.label}'
                    '${account.protocol == BlogProtocol.xmlrpc ? ' (${account.flavor.label})' : ''}',
                  ),
                  trailing: account.id == app.currentAccount?.id
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () {
                    app.selectAccount(account);
                    Navigator.of(context).pop();
                  },
                )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add blog account'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const AddAccountPage(embedded: false)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(
                  'Remove "${app.currentAccount?.name ?? ''}"'),
              onTap: () {
                final id = app.currentAccount?.id;
                Navigator.of(context).pop();
                if (id != null) app.removeAccount(id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BlogSwitcher extends StatelessWidget {
  const _BlogSwitcher({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final account = app.currentAccount!;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        // Show quick switcher.
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...app.accounts.map((a) => ListTile(
                      leading: CircleAvatar(
                          child: Text(
                              a.name.isEmpty ? '?' : a.name[0].toUpperCase())),
                      title: Text(a.name),
                      subtitle: Text(a.homepageUrl),
                      trailing: a.id == account.id
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: () {
                        app.selectAccount(a);
                        Navigator.of(context).pop();
                      },
                    )),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add another blog'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            const AddAccountPage(embedded: false)));
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  account.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  account.protocol.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.app});

  final BlogPost post;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd().add_jm();
    final categoryNames =
        post.categories.map(app.categoryName).take(3).join(', ');

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          Expanded(
            child: Text(
              post.title.isEmpty ? '(untitled)' : post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          _StatusChip(status: post.status),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.displayExcerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (post.datePublished != null)
                  dateFmt.format(post.datePublished!.toLocal()),
                if (categoryNames.isNotEmpty) categoryNames,
                if (post.isPage) 'Page',
              ].join(' • '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      isThreeLine: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostEditorPage(existingPost: post),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PostStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      PostStatus.publish => (Colors.green, PostStatus.publish.label),
      PostStatus.draft => (Colors.orange, PostStatus.draft.label),
      PostStatus.pending => (Colors.amber, PostStatus.pending.label),
      PostStatus.private => (Colors.purple, PostStatus.private.label),
      PostStatus.scheduled => (Colors.blue, PostStatus.scheduled.label),
      PostStatus.trash => (Colors.grey, PostStatus.trash.label),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withValues(alpha: 1),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
