import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_contact/contacts.dart';
import 'package:full_text_search/full_text_search.dart';
import 'package:full_text_search/term_search_result.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sunny_dart/sunny_dart.dart' as sd;
import 'package:sunny_forms/permissions.dart';
import 'package:sunny_sdk_core/model_exports.dart';
import 'package:sunny_sdk_core/sunny_sdk_core.dart';
import 'package:sunny_service_stubs/models.dart';

StreamController<ContactEvent>? _contactEvents = StreamController.broadcast();

Stream<ContactEvent> get contactEventStream => _contactEvents!.stream;

DeviceContactService get deviceContactService => sd.sunny.get();

class DeviceContactService with sd.LoggingMixin, LifecycleAwareMixin {
  final IUserPreferencesService _prefs;
  final IAuthState _authState;

  DeviceContactService(this._prefs, this._authState) {
    _registerLifecycleHooks();
  }

  late StreamSubscription<ContactEvent> _contactEventsSub;
  DateTime? lastDeviceChange;

  String? get accountId => _authState.accountId;

//  _listenToContactEvents() async {
//    if (_contactEventsSub == null) {
//      if (await Permission.contacts.isEnabled) {
//        log.info("Have permissions for contacts - attempting to listen");
//
//      }
//    }
//  }

  Future<bool> checkSingleContactPermission(BuildContext context) async {
    final isDeviceContactEnabled = await _prefs.get(enableDeviceContacts);
    if (isDeviceContactEnabled.isBlank) {
      final status = await checkAndRequestPermissions(
        context,
        permission: Permission.contacts,
        title: (intl) => "Save to iOS Contacts?",
        subtitleWidget:
            Text("When you update a contact in Sunny, would you like the option to apply the change to your iOS contacts?"),
      );
      switch (status) {
        case SunnyPermissionStatus.rejected:
          await _prefs.set(enableDeviceContacts, false);
          return false;
        case SunnyPermissionStatus.granted:
          await _prefs.set(enableDeviceContacts, true);
          return true;
        case SunnyPermissionStatus.later:
          await _prefs.set(enableDeviceContacts, false);
          return false;
        default:
          return false;
      }
    } else {
      /// THey've opted out of the behavior
      if (isDeviceContactEnabled != "true") {
        return false;
      }

      PermissionStatus status = await Permission.contacts.status;
      return status == PermissionStatus.granted;
    }
  }

  Future<Iterable<TermSearchResult<Contact>>> findDeviceContactMatches(ISunnyContact sunnyContact, {int? limit}) async {
    final allDeviceContacts = Contacts.streamContacts(withThumbnails: false, withHiResPhoto: false);
    final tokens = [
      for (final t in sunnyContactTokenizer(sunnyContact).orEmpty())
        if (t is Token) t.value else "$t",
    ].whereNotBlank();
    final initial = [
      ...(await FullTextSearch.ofStream(
                  term: tokens.join(" "),
                  items: allDeviceContacts,
                  isMatchAll: false,
                  isStartsWith: true,
                  limit: limit ?? 2,
                  tokenize: deviceContactTokenizer)
              .execute())
          .where((r) => r.matchedTerms.isNotEmpty)
    ];
    initial.sort();

    final reloaded = await initial.map((r) async {
      final loaded = await Contacts.getContact(r.result.identifier!, withThumbnails: true);
      return TermSearchResult(loaded!, r.matchedTerms, r.matchedTokens, r.matchAll);
    }).awaitAll();

    return reloaded;
  }

  _registerLifecycleHooks() {
    autoSubscribe("contactEventsSubscription", () async {
      _contactEventsSub = Contacts.contactEvents.where((e) => e != null).cast<ContactEvent>().listen(
            (event) {
              log.info("Got contact updated event! $event");
              _contactEvents!.add(event);
            },
            onError: (Object err, StackTrace stack) {
              log.severe("Got error from contact subscription. Not passing along: $err", err, stack);
              _contactEvents!.addError(err, stack);
            },
            cancelOnError: false,
            onDone: () {
              log.warning("Contact events subscription ended.  Why?");
              _contactEvents = null;
            },
          );
      _authState.userStateStream.listen((profile) {
        if (profile.status == AuthStatus.none) {
          _contactEventsSub.pause();
        } else {
          _contactEventsSub.resume();
        }
      });
      return _contactEventsSub;
    });

//    autoSubscribe("permissionRead", () async {
//      onPermissionCheck.forEach((info) async {
//        if (info.permission == Permission.contacts && info.status.isEnabled) {
////        await _listenToContactEvents();
//        }
//      }).ignore();
//    });
  }
}

const enableDeviceContacts = UserPrefKey("enableDeviceContacts");

final SearchTermBuilder<ISunnyContact> sunnyContactTokenizer = (contact) {
  final tokens = <FTSToken>[];
  tokens.addToken(contact.firstName!, _fnToken);
  tokens.addToken(contact.lastName!, _lnToken);
  tokens.addToken(contact.fullName!, _nmToken);
  tokens.addToken(contact.companyName!, _coToken);
  tokens.addToken(contact.title!, _jtToken);

  if (contact.firstName.isNotNullOrBlank && contact.lastName.isNotNullOrBlank) {
    tokens.addToken("${contact.lastName}, ${contact.firstName}", _nmToken);
  }

  tokens.addNamed(_emToken, contact.identities!.expand((identity) => identity.emails!).map((email) => email.email));
  tokens.addNamed(_phToken,
      contact.identities!.expand((identity) => identity.phones!).expand((phone) => sd.tokenizePhoneNumber(phone.number)));
  return tokens;
};

const _fnToken = "firstName";
const _lnToken = "lastName";
const _nmToken = "Name";
const _coToken = "Company";
const _jtToken = "Job Title";
const _emToken = "Email";
const _phToken = "Phone";

typedef SearchTermBuilder<T> = List<dynamic> Function(T item);

SearchTermBuilder<T> defaultSearchTermBuilder<T>() => (T input) => ["$input"];

final SearchTermBuilder<Contact> deviceContactTokenizer = (contact) {
  final tokens = <FTSToken>[];
  tokens.addToken(contact.givenName!, _nmToken);
  tokens.addToken(contact.familyName!, _nmToken);
  tokens.addToken(contact.displayName!, _nmToken);
  tokens.addToken(contact.company!, _coToken);
  tokens.addToken(contact.jobTitle!, _jtToken);

  tokens.addNamed(_emToken, contact.emails.map((email) => email.value));
  tokens.addNamed(_phToken, contact.phones.expand((phone) => sd.tokenizePhoneNumber(phone.value)));
  return tokens;
};

/// Applies a boost if the matched token is in the firstName, lastName, or givenName
// ignore: unused_element
class _ContactNameScorer implements SearchScoring {
  final MKey userContactKey;

  @override
  void scoreTerm(FullTextSearch search, TermSearchResult term, Score current) {
    for (final match in term.matchedTokens) {
      /// We don't want to boost "contains" terms because we don't want to boost a weak match

      switch (match.key) {
        case EqualsMatch.matchKey:
        case StartsWithMatch.matchKey:
          final tokenName = match.matchedToken.name;
          switch (tokenName) {
            case _fnToken:
              current += Boost.amount(0.5, "firstNameMatch");
              break;
            case _lnToken:
            case _nmToken:
              current += Boost.amount(0.25, "nameMatch");
              break;
            default:
              break;
          }
          break;
        default:
          break;
      }
    }
  }

  const _ContactNameScorer(this.userContactKey);
}
