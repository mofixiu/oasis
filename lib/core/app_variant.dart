/// Compile-time product variant.
///
/// Defaults to v2, the short-stay app, which is the only one that ships now.
/// v1 (the rental app) is switched off: see `docs/v1_disabled.md` for how to
/// bring it back. `--dart-define=APP_VARIANT=v1` alone is not enough, because
/// the v1 shell in `main_scaffold.dart` is commented out.
const String oasisAppVariant = String.fromEnvironment(
  'APP_VARIANT',
  defaultValue: 'v2',
);

const bool isOasisV2 = oasisAppVariant == 'v2';
