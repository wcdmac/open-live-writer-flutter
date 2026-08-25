import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/blog.dart';
import '../services/blog_service.dart';
import '../services/rsd_detector.dart';
import '../state/app_state.dart';

/// Add-blog-account wizard. Port of OLW's WeblogConfiguration wizard:
/// URL + credentials -> RSD detection -> protocol choice -> blog pick.
class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key, this.embedded = false});

  /// When true the page is rendered as the home screen (no back button).
  final bool embedded;

  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passController = TextEditingController();

  BlogDetection? _detection;
  List<BlogInfo> _blogs = [];
  BlogInfo? _pickedBlog;
  BlogProtocol _protocol = BlogProtocol.xmlrpc;
  RestAuthMethod _restAuth = RestAuthMethod.applicationPassword;
  XmlRpcFlavor _flavor = XmlRpcFlavor.wordpress;

  bool _detecting = false;
  bool _connecting = false;
  String? _error;
  int _step = 0; // 0: credentials, 1: detected settings, 2: blog pick

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _detecting = true;
      _error = null;
    });

    try {
      var url = _urlController.text.trim();
      if (!url.startsWith('http')) url = 'https://$url';

      final detector = RsdDetector();
      final detection = await detector.detect(url);
      detector.close();

      setState(() {
        _detection = detection;
        _flavor = detection.flavor ?? XmlRpcFlavor.wordpress;
        _protocol =
            detection.restRoot != null && detection.xmlrpcUrl == null
                ? BlogProtocol.rest
                : BlogProtocol.xmlrpc;
        _step = 1;
      });
    } catch (e) {
      setState(() => _error = 'Detection failed: $e');
    } finally {
      setState(() => _detecting = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      final detection = _detection!;
      final password = _passController.text;

      // Build a temporary account and validate credentials by listing blogs.
      final tempAccount = BlogAccount(
        id: 'temp',
        blogId: detection.blogId ?? '1',
        name: 'temp',
        homepageUrl: detection.homepageUrl,
        apiUrl: _protocol == BlogProtocol.rest
            ? (detection.restRoot ??
                '${detection.homepageUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json')
            : detection.xmlrpcUrl!,
        protocol: _protocol,
        username: _userController.text.trim(),
        flavor: _flavor,
        restAuth: _restAuth,
      );

      final service = BlogService(tempAccount, password);
      final blogs = await service.getUsersBlogs();

      if (!mounted) return;
      if (blogs.isEmpty) {
        setState(() => _error =
            'Connected, but no blogs were returned for these credentials.');
        return;
      }

      setState(() {
        _blogs = blogs;
        _pickedBlog = blogs.length == 1 ? blogs.first : null;
        _step = 2;
      });
    } catch (e) {
      setState(() => _error = 'Connection failed: $e');
    } finally {
      setState(() => _connecting = false);
    }
  }

  Future<void> _finish() async {
    final picked = _pickedBlog;
    if (picked == null) return;

    setState(() => _connecting = true);
    try {
      final app = context.read<AppState>();
      final detection = _detection!;
      final account = BlogAccount(
        id: app.newAccountId(),
        blogId: picked.blogId,
        name: picked.name,
        homepageUrl: detection.homepageUrl,
        apiUrl: _protocol == BlogProtocol.rest
            ? (detection.restRoot ??
                '${detection.homepageUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json')
            : detection.xmlrpcUrl ?? picked.xmlrpcUrl!,
        protocol: _protocol,
        username: _userController.text.trim(),
        flavor: _flavor,
        restAuth: _restAuth,
      );

      await app.addAccount(account, _passController.text);
      await app.refresh();

      if (!mounted) return;
      if (!widget.embedded) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Failed to save account: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 640;

    return Scaffold(
      appBar: widget.embedded
          ? AppBar(
              title: const Text('Open Live Writer'),
              automaticallyImplyLeading: false,
            )
          : AppBar(title: const Text('Add blog account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.embedded) ...[
                  Icon(
                    Icons.edit_note,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome to Open Live Writer',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connect to your WordPress blog to start writing.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],
                Stepper(
                  currentStep: _step,
                  controlsBuilder: (context, details) => const SizedBox(),
                  physics: const NeverScrollableScrollPhysics(),
                  onStepTapped: (i) {
                    // Allow going back to earlier steps only.
                    if (i < _step) setState(() => _step = i);
                  },
                  steps: [
                    Step(
                      title: const Text('Blog & credentials'),
                      isActive: _step >= 0,
                      state: _step > 0 ? StepState.complete : StepState.indexed,
                      content: _credentialsForm(),
                    ),
                    Step(
                      title: const Text('Connection settings'),
                      isActive: _step >= 1,
                      state: _step > 1 ? StepState.complete : StepState.indexed,
                      content: _step == 1 ? _settingsForm() : const SizedBox(),
                    ),
                    Step(
                      title: const Text('Choose blog'),
                      isActive: _step >= 2,
                      state: _step > 2 ? StepState.complete : StepState.indexed,
                      content: _step == 2 ? _blogPicker() : const SizedBox(),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 24),
                _actionButtons(isWide),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _credentialsForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Blog homepage URL',
              hintText: 'https://example.com',
              prefixIcon: Icon(Icons.language),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter your blog URL' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _userController,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person),
            ),
            autocorrect: false,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passController,
            decoration: const InputDecoration(
              labelText: 'Password / Application Password',
              prefixIcon: Icon(Icons.password),
              helperText: 'For REST API use an Application Password '
                  '(WP Admin → Users → Profile → Application Passwords).',
            ),
            obscureText: true,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
        ],
      ),
    );
  }

  Widget _settingsForm() {
    final d = _detection!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detectionRow('Blog engine', d.engineName ?? 'Unknown'),
        _detectionRow('XML-RPC endpoint', d.xmlrpcUrl ?? 'Not detected'),
        _detectionRow('REST API', d.restRoot ?? 'Not detected'),
        const SizedBox(height: 16),
        Text('Connection protocol',
            style: Theme.of(context).textTheme.titleSmall),
        RadioListTile<BlogProtocol>(
          value: BlogProtocol.xmlrpc,
          groupValue: _protocol,
          title: const Text('XML-RPC (classic Open Live Writer)'),
          subtitle: Text('Flavor: ${_flavor.label}'),
          onChanged: d.xmlrpcUrl == null
              ? null
              : (v) => setState(() => _protocol = v!),
        ),
        RadioListTile<BlogProtocol>(
          value: BlogProtocol.rest,
          groupValue: _protocol,
          title: const Text('WordPress REST API v2'),
          subtitle: Text('Endpoint: ${d.restRoot ?? 'not available'}'),
          onChanged: d.restRoot == null
              ? null
              : (v) => setState(() => _protocol = v!),
        ),
        if (_protocol == BlogProtocol.xmlrpc) ...[
          DropdownButtonFormField<XmlRpcFlavor>(
            value: _flavor,
            decoration: const InputDecoration(labelText: 'XML-RPC API flavor'),
            items: XmlRpcFlavor.values
                .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                .toList(),
            onChanged: (v) => setState(() => _flavor = v!),
          ),
        ],
        if (_protocol == BlogProtocol.rest) ...[
          DropdownButtonFormField<RestAuthMethod>(
            value: _restAuth,
            decoration: const InputDecoration(labelText: 'Authentication'),
            items: RestAuthMethod.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: (v) => setState(() => _restAuth = v!),
          ),
        ],
      ],
    );
  }

  Widget _detectionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 2)),
        ],
      ),
    );
  }

  Widget _blogPicker() {
    return Column(
      children: _blogs
          .map((blog) => RadioListTile<String>(
                value: blog.blogId,
                groupValue: _pickedBlog?.blogId,
                title: Text(blog.name),
                subtitle: Text(blog.url),
                onChanged: (v) => setState(
                    () => _pickedBlog = _blogs.firstWhere((b) => b.blogId == v)),
              ))
          .toList(),
    );
  }

  Widget _actionButtons(bool isWide) {
    final busy = _detecting || _connecting;
    late final Widget primary;

    switch (_step) {
      case 0:
        primary = FilledButton.icon(
          onPressed: busy ? null : _detect,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.travel_explore),
          label: const Text('Detect blog settings'),
        );
      case 1:
        primary = FilledButton.icon(
          onPressed: busy ? null : _connect,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: const Text('Connect'),
        );
      default:
        primary = FilledButton.icon(
          onPressed: busy || _pickedBlog == null ? null : _finish,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Finish'),
        );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_step > 0)
          TextButton(
            onPressed: busy ? null : () => setState(() => _step--),
            child: const Text('Back'),
          ),
        const SizedBox(width: 8),
        primary,
      ],
    );
  }
}
