import 'package:rotransit/l10n/app_localizations.dart';

import 'app_user_message.dart';

extension AppUserMessageLocalization on AppLocalizations {
  String localizeUserMessage(AppUserMessageId id) {
    return switch (id) {
      AppUserMessageId.serverUnreachable => errorServerUnreachable,
      AppUserMessageId.serverTimeout => errorServerTimeout,
      AppUserMessageId.unexpectedError => errorUnexpectedError,
    };
  }
}
