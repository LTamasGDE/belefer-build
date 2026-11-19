import 'package:flutter/material.dart';

import '../../domain/accounts.dart';
import '../../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/belefer_colors.dart';
import '../widgets/common.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/rows.dart';

IconData accountIcon(AccountKind kind) => switch (kind) {
  AccountKind.personal => Icons.person_rounded,
  AccountKind.savings => Icons.savings_rounded,
  AccountKind.shared => Icons.people_alt_rounded,
};

/// Számla felvétele vagy szerkesztése (alsó lapon).
Future<void> showAccountEditor(BuildContext context, {Account? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AccountEditor(existing: existing),
  );
}

/// A számlák kezelése: név, fajta, felismerő szavak, alapértelmezett.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final accounts = state.accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('Számlák')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-account'),
        heroTag: 'fab-accounts',
        onPressed: () => showAccountEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Új számla'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, 104),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xs,
                    Space.sm,
                    Space.xs,
                    Space.md,
                  ),
                  child: Text(
                    'Ha több számlád van (pl. saját, megtakarítás, közös a '
                    'pároddal), a tételek számlánként is szűrhetők. Az '
                    'automatikusan érkező tételek a felismerő szavak alapján '
                    'kerülnek a jó számlára (iPhone-on a Walletben látható '
                    'kártyanév, Androidon a Revolut értesítésében szereplő '
                    'szó vagy kártyaszám vége); ha egyik sem illik, az '
                    'alapértelmezett számlára.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
                if (accounts.isEmpty)
                  const EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Még nincs számla',
                    message:
                        'Számlák nélkül minden tétel egy közös listában van. '
                        'Vedd fel pl.: Saját Revolut (alapértelmezett), '
                        'Megtakarítás, Közös.',
                  )
                else
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (index, account) in accounts.indexed) ...[
                          if (index > 0) const RowDivider(),
                          LinkRow(
                            key: ValueKey('account-row-${account.id}'),
                            icon: accountIcon(account.kind),
                            title: account.name,
                            subtitle: [
                              account.kind.label,
                              if (account.isDefault) 'alapértelmezett',
                              '${state.usageOfAccount(account.id!)} tétel',
                              if (account.matchers.isNotEmpty)
                                'felismerés: ${account.matchers.join(', ')}',
                            ].join(' · '),
                            onTap: () =>
                                showAccountEditor(context, existing: account),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({this.existing});

  final Account? existing;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _matchers;
  late AccountKind _kind;
  late bool _isDefault;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final state = AppScope.read(context);
    _name = TextEditingController(text: existing?.name ?? '');
    _matchers = TextEditingController(
      text: existing?.matchers.join(', ') ?? '',
    );
    _kind = existing?.kind ?? AccountKind.personal;
    _isDefault = existing?.isDefault ?? state.accounts.isEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _matchers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final account = Account(
      id: widget.existing?.id,
      name: _name.text.trim(),
      kind: _kind,
      matchers: [
        for (final part in _matchers.text.split(RegExp(r'[,;\n]')))
          if (part.trim().isNotEmpty) part.trim(),
      ],
      isDefault: _isDefault,
    );
    await AppScope.read(context).saveAccount(account);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final state = AppScope.read(context);
    final confirmed = await confirmAction(
      context,
      title: 'Törlöd a(z) „${existing.name}” számlát?',
      message:
          'A tételei megmaradnak, csak számla nélküliek lesznek '
          '(az alapértelmezett számlánál látszanak).',
      confirmLabel: 'Törlés',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await state.deleteAccount(existing.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final editing = widget.existing != null;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.page, 0, Space.page, bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                editing ? 'Számla szerkesztése' : 'Új számla',
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                key: const ValueKey('account-name'),
                controller: _name,
                autofocus: !editing,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Név',
                  hintText: 'Pl. Saját Revolut, Közös',
                  counterText: '',
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? 'Adj nevet.' : null,
              ),
              const SizedBox(height: Space.lg),
              Text('Fajta', style: textTheme.labelLarge),
              const SizedBox(height: Space.sm),
              ChoiceWrap<AccountKind>(
                semanticLabel: 'A számla fajtája',
                options: [
                  for (final kind in AccountKind.values) (kind, kind.label),
                ],
                selected: _kind,
                onSelected: (value) => setState(() => _kind = value),
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                key: const ValueKey('account-matchers'),
                controller: _matchers,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Felismerő szavak (vesszővel elválasztva)',
                  hintText: 'Pl. Revolut Közös, Joint, 4821',
                  helperMaxLines: 3,
                  helperText:
                      'iPhone: a kártya neve a Walletben. Android: szó vagy '
                      'kártyaszám vége a Revolut értesítéséből (a Napló '
                      'megmutatja, mit küld).',
                ),
              ),
              const SizedBox(height: Space.md),
              Panel(
                padding: EdgeInsets.zero,
                child: ToggleRow(
                  icon: Icons.star_rounded,
                  title: 'Alapértelmezett számla',
                  subtitle:
                      'Ide kerül minden automatikus tétel, amelyre egyik '
                      'felismerő szó sem illik, és a számla nélküli tételek.',
                  value: _isDefault,
                  switchKey: const ValueKey('account-default'),
                  onChanged: (value) => setState(() => _isDefault = value),
                ),
              ),
              const SizedBox(height: Space.xl),
              FilledButton.icon(
                key: const ValueKey('save-account'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Mentés'),
              ),
              if (editing) ...[
                const SizedBox(height: Space.sm),
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: colors.danger),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Számla törlése'),
                ),
              ],
              const SizedBox(height: Space.xl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Számla szerinti szűrő (Összes / számlánként), ha van legalább egy számla.
class AccountFilterBar extends StatelessWidget {
  const AccountFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.accounts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ChoiceWrap<int?>(
          semanticLabel: 'Számla',
          options: [
            (null, 'Összes számla'),
            for (final account in state.accounts) (account.id, account.name),
          ],
          selected: state.selectedAccountId,
          onSelected: state.selectAccount,
        ),
      ),
    );
  }
}
