import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/blog.dart';
import '../services/blog_service.dart';
import '../widgets/radio_group.dart';
import '../services/rest/wordpress_rest.dart';
import '../services/rsd_detector.dart';
import '../state/app_state.dart';

/// Localized display label for a [BlogProtocol].
String protocolLabel(AppLocalizations l10n, BlogProtocol protocol) =>
    switch (protocol) {
      BlogProtocol.xmlrpc => l10n.protocolXmlrpc,
      BlogProtocol.rest => l10n.protocolRest,
    };

/// Localized display label for an [XmlRpcFlavor].
String flavorLabel(AppLocalizations l10n, XmlRpcFlavor flavor) =>
    switch (flavor) {
      XmlRpcFlavor.wordpress => l10n.flavorWordpress,
      XmlRpcFlavor.metaweblog => l10n.flavorMetaweblog,
      XmlRpcFlavor.movabletype => l10n.flavorMovabletype,
      XmlRpcFlavor.blogger => l10n.flavorBlogger,
    };

/// Localized display label for a [RestAuthMethod].
String restAuthLabel(AppLocalizations l10n, RestAuthMethod method) =>
    switch (method) {
      RestAuthMethod.applicationPassword => l10n.authAppPassword,
      RestAuthMethod.jwt => l10n.authJwt,
    };

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
    final l10n = AppLocalizations.of(context)!;
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
        _protocol = detection.restRoot != null && detection.xmlrpcUrl == null
            ? BlogProtocol.rest
            : BlogProtocol.xmlrpc;
        _step = 1;
      });
    } catch (e) {
      setState(() => _error = l10n.detectionFailed(e));
    } finally {
      setState(() => _detecting = false);
    }
  }

  Future<void> _connect() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _connecting = true;
      _error = null;
    });

    BlogService? service;
    try {
      final detection = _detection!;
      final password = _passController.text;

      // Build a temporary account and validate credentials by listing blogs.
      final apiUrl = _protocol == BlogProtocol.rest
          ? (detection.restRoot ??
                '${detection.homepageUrl.replaceAll(RegExp(r'/+$'), '')}/wp-json')
          : detection.xmlrpcUrl!;
      // S1: surface insecure (http) transport — credentials would be sent in
      // cleartext. The connection still proceeds (local/test servers).
      if (!apiUrl.startsWith('https') && kDebugMode) {
        debugPrint(
          'WARNING: connecting to blog endpoint "$apiUrl" over '
          'plaintext HTTP — credentials will be sent in cleartext.',
        );
      }
      final tempAccount = BlogAccount(
        id: 'temp',
        blogId: detection.blogId ?? '1',
        name: 'temp',
        homepageUrl: detection.homepageUrl,
        apiUrl: apiUrl,
        protocol: _protocol,
        username: _userController.text.trim(),
        flavor: _flavor,
        restAuth: _restAuth,
      );

      service = BlogService(tempAccount, password);
      final blogs = await service.getUsersBlogs();

      if (!mounted) return;
      if (blogs.isEmpty) {
        setState(() => _error = l10n.connectedNoBlogs);
        return;
      }

      setState(() {
        _blogs = blogs;
        _pickedBlog = blogs.length == 1 ? blogs.first : null;
        _step = 2;
      });
    } on WordPressRestException catch (e) {
      // Give actionable guidance for the two most common REST failures.
      if (!mounted) return;
      final msg = e.statusCode == 401
          ? l10n.restAuth401('$e')
          : e.statusCode == 404 && _restAuth == RestAuthMethod.jwt
          ? l10n.restJwt404('$e')
          : l10n.connectionFailed(e);
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = l10n.connectionFailed(e));
    } finally {
      // M1: the temporary service owns an HTTP client + JWT future; leak it
      // on every cancelled or errored connect. Release it here unconditionally.
      service?.dispose();
      setState(() => _connecting = false);
    }
  }

  Future<void> _finish() async {
    final picked = _pickedBlog;
    if (picked == null) return;
    final l10n = AppLocalizations.of(context)!;

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

      if (!mounted) return;
      // M2: addAccount() already runs refresh() (via selectAccount), so an
      // extra refresh here is a redundant second network fetch on every add.
      if (!widget.embedded) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = l10n.saveAccountFailed(e));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 640;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: widget.embedded
          ? AppBar(title: Text(l10n.appTitle), automaticallyImplyLeading: false)
          : AppBar(title: Text(l10n.addBlogAccount)),
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
                    l10n.welcome,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.welcomeSubtitle,
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
                      title: Text(l10n.blogCredentials),
                      isActive: _step >= 0,
                      state: _step > 0 ? StepState.complete : StepState.indexed,
                      content: _credentialsForm(),
                    ),
                    Step(
                      title: Text(l10n.connectionSettings),
                      isActive: _step >= 1,
                      state: _step > 1 ? StepState.complete : StepState.indexed,
                      content: _step == 1 ? _settingsForm() : const SizedBox(),
                    ),
                    Step(
                      title: Text(l10n.chooseBlog),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
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
    final l10n = AppLocalizations.of(context)!;
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: l10n.blogUrl,
              hintText: l10n.blogUrlHint,
              prefixIcon: const Icon(Icons.language),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.enterBlogUrl : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _userController,
            decoration: InputDecoration(
              labelText: l10n.username,
              prefixIcon: const Icon(Icons.person),
            ),
            autocorrect: false,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.enterUsername : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passController,
            decoration: InputDecoration(
              labelText: l10n.password,
              prefixIcon: const Icon(Icons.password),
              helperText: l10n.passwordHelper,
            ),
            obscureText: true,
            validator: (v) =>
                (v == null || v.isEmpty) ? l10n.enterPassword : null,
          ),
        ],
      ),
    );
  }

  Widget _settingsForm() {
    final d = _detection!;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detectionRow(l10n.blogEngine, d.engineName ?? l10n.unknown),
        _detectionRow(l10n.xmlrpcEndpoint, d.xmlrpcUrl ?? l10n.notDetected),
        _detectionRow(l10n.restApi, d.restRoot ?? l10n.notDetected),
        const SizedBox(height: 16),
        Text(
          l10n.connectionProtocol,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        RadioGroup<BlogProtocol>(
          groupValue: _protocol,
          onChanged: (BlogProtocol? value) {
            if (value == null) return;
            // Preserve the original per-tile disable: a protocol whose
            // endpoint was not detected cannot be selected.
            if (value == BlogProtocol.xmlrpc && d.xmlrpcUrl == null) return;
            if (value == BlogProtocol.rest && d.restRoot == null) return;
            setState(() => _protocol = value);
          },
          builder: (context) => Column(
            children: [
              RadioListTile<BlogProtocol>(
                value: BlogProtocol.xmlrpc,
                groupValue: RadioGroup.of<BlogProtocol>(context).groupValue,
                onChanged: RadioGroup.of<BlogProtocol>(context).onChanged,
                title: Text(l10n.xmlrpcClassic),
                subtitle: Text('${l10n.flavor}: ${flavorLabel(l10n, _flavor)}'),
              ),
              RadioListTile<BlogProtocol>(
                value: BlogProtocol.rest,
                groupValue: RadioGroup.of<BlogProtocol>(context).groupValue,
                onChanged: RadioGroup.of<BlogProtocol>(context).onChanged,
                title: Text(l10n.restV2),
                subtitle: Text(
                  '${l10n.endpoint}: ${d.restRoot ?? l10n.notAvailable}',
                ),
              ),
            ],
          ),
        ),
        if (_protocol == BlogProtocol.xmlrpc) ...[
          DropdownButtonFormField<XmlRpcFlavor>(
            initialValue: _flavor,
            decoration: InputDecoration(labelText: l10n.xmlrpcFlavor),
            items: XmlRpcFlavor.values
                .map(
                  (f) => DropdownMenuItem(
                    value: f,
                    child: Text(flavorLabel(l10n, f)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _flavor = v!),
          ),
        ],
        if (_protocol == BlogProtocol.rest) ...[
          DropdownButtonFormField<RestAuthMethod>(
            initialValue: _restAuth,
            decoration: InputDecoration(labelText: l10n.authentication),
            items: RestAuthMethod.values
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(restAuthLabel(l10n, m)),
                  ),
                )
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
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 2),
          ),
        ],
      ),
    );
  }

  Widget _blogPicker() {
    return RadioGroup<String>(
      groupValue: _pickedBlog?.blogId,
      onChanged: (v) {
        if (v == null) return;
        // `v` always originates from one of the radios above, so a miss here
        // is unreachable — but guard against it to avoid a StateError if the
        // blog list is ever rebuilt out from under the selection.
        setState(() {
          _pickedBlog = _blogs.firstWhere(
            (b) => b.blogId == v,
            orElse: () => _blogs.first,
          );
        });
      },
      builder: (context) => Column(
        children: _blogs
            .map(
              (blog) => RadioListTile<String>(
                value: blog.blogId,
                groupValue: RadioGroup.of<String>(context).groupValue,
                onChanged: RadioGroup.of<String>(context).onChanged,
                title: Text(blog.name),
                subtitle: Text(blog.url),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _actionButtons(bool isWide) {
    final l10n = AppLocalizations.of(context)!;
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
          label: Text(l10n.detectSettings),
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
          label: Text(l10n.connect),
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
          label: Text(l10n.finish),
        );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_step > 0)
          TextButton(
            onPressed: busy ? null : () => setState(() => _step--),
            child: Text(l10n.back),
          ),
        const SizedBox(width: 8),
        primary,
      ],
    );
  }
}
