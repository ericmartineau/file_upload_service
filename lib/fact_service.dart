import 'dart:async';
import 'dart:core';

import 'package:collection_diff/collection_diff.dart';
import 'package:facts/facts.dart';
import 'package:full_text_search/full_text_search.dart';
import 'package:observable_collections/observable_collections.dart';
import 'package:sunny_sdk_core/model_exports.dart';
import 'package:sunny_service_stubs/models.dart';
import 'package:sunny_services/bundle_state.dart';

const contactKeyPath = JsonPath<MKey>.internal(["contactKey"], "/contactKey");

class FactService with LoggingMixin implements IFactService {
  final FactApi _factApi;
  final ApiRegistry _apis;
  final IFactSchemaApi _factSchemaApi;
  final SunnyObservableMap<String, IFactSchema> _factSchemas;

  final SunnyObservableMap<String, IFactSchema> attributeSchemas;

  /// Schemas that represent organizations
  final SunnyObservableMap<String, IFactSchema> orgSchemas;
  final SunnyObservableMap<String, IFactSchema> historySchemas;
  final SunnyObservableMap<String, IFactSchema> remindSchemas;
  final StreamController<IFact> _updatedFactController = StreamController.broadcast();
  final SafeCompleter<bool> _loaded = SafeCompleter();

  final IBundleState bundleState;

  /// Maps schemas that belong to bundles.  Basically, the schema represented by [MSchemaRef] requires at least one
  /// of the bundles represented by [Set<MKey>] to be purchased and installed.
  final Map<MSchemaRef, Set<MKey>> _schemaToBundleKeys = {};

  Set<MKey> getSchemaRequiredBundles(MSchemaRef ref) {
    return _schemaToBundleKeys[ref] ?? const {};
  }

  FactService(FactApi factApi, IFactSchemaApi factSchemaApi, ApiRegistry apis, [IBundleState? bundleState])
      : this._(factApi, factSchemaApi, apis, SunnyObservableMap(debugLabel: "factSchemas"), bundleState!);

  FactService._(this._factApi, this._factSchemaApi, this._apis, this._factSchemas, this.bundleState)
      : attributeSchemas = _factSchemas.stream.map((input) => input.cast<String, IFactSchema>()).filterEntries((ref, schema) {
          return (schema.isAttribute == true) && schema.templates?.isNotEmpty == true;
        }).observe("attributeSchemas"),
        historySchemas = _factSchemas.stream.map((input) => input.cast<String, IFactSchema>()).filterEntries((ref, schema) {
          return schema.isHistorical == true && schema.templates?.isNotEmpty == true;
        }).observe("historySchemas"),
        remindSchemas = _factSchemas.stream.map((input) => input.cast<String, IFactSchema>()).filterEntries((ref, schema) {
          return schema.isActionable && schema.templates?.isNotEmpty == true;
        }).observe("remindSchemas"),
        orgSchemas = _factSchemas.stream.map((input) => input.cast<String, IFactSchema>()).filterEntries((ref, schema) {
          return schema.isOrg && schema.templates?.isNotEmpty == true;
        }).observe("remindSchemas") {
    refreshFactSchemas();
  }

  Stream<IFact> get factStream => _updatedFactController.stream;

  void factChanged(IFact fact) {
    _updatedFactController.add(fact);
  }

  List<IFactSchema> get factSchemas => _factSchemas.values.toList();

  /// Based on current installation, returns a list of schemas that are not allowed because the user
  /// has not installed the appropriate plugin
  Set<MSchemaRef> get restrictedSchemas {
    final installedBundles = bundleState.installedBundleKeys;
    return {
      ..._schemaToBundleKeys.whereEntries((ref, required) {
        if (required.isEmpty) {
          return false;
        } else {
          final anyInstalled = required.any((required) {
            return installedBundles.contains(required);
          });
          return !anyInstalled;
        }
      }).keys,
    };
  }

  Future<IFact> saveFact(IFact fact) async {
    try {
//      if (fact.factSchema.links.any((link) => link.path == contactKeyPath)) {
//        fact.contactKey = contact.mkey;
//      }
      fact.dateCreated = DateTime.now();
      IFact updated;
      if (fact.id == null) {
        updated = await _factApi.create(fact);
      } else {
        await _factApi.update(fact.id!, fact);
        updated = fact;
      }
      _updatedFactController.add(updated);
      return updated;
    } catch (e) {
      log.info(e);
      rethrow;
    }
  }

  Future<bool> get isLoaded => _loaded.future;

  Future<Facts> getFactsForContact(MKey contactId) async {
    await isLoaded;

    final result = await _factApi.factsByRecordKey(recordKey: contactId.value);
    final sanitized = result.data?.mapNotNull((fact) {
          final schema = _factSchemas["${fact.mtype}"];
          if (schema == null) {
            log.warning("Ignoring fact with missing type: ${fact.mtype}");
            return null;
          }
          fact.factSchema = schema;
          return fact;
        }) ??
        [];
    return Facts.of(count: sanitized.length, data: [...sanitized]);
  }

  Future<Iterable<IFact>> listFacts(MSchemaRef mtype, {double? offset, double? limit}) async {
    return (await _apis.get(mtype).list(offset: offset, limit: limit)).data!.map((entity) {
      return entity as IFact;
    });
  }

  ValueStream<Facts> streamFactsForContact(MKey contactId) {
    return ValueStream.of(
      getFactsForContact(contactId),
      factStream.where((fact) => fact.contactKey == contactId).asyncMapSample((_) async {
        return await getFactsForContact(contactId);
      }),
    );
  }

  ValueStream<Facts> streamFactsForUser(MKey userId) {
    return ValueStream.of(
      getFactsForContact(userId),
      factStream.where((fact) => fact.involves(userId)).asyncMapSample((_) async {
        return await getFactsForContact(userId);
      }),
    );
  }

  /// Looks for fact schemas that match [queryText].  Searches name, label, factTokens
  Future<List<FactDateSchemaQuery>> findFactSchemas(String queryText) async {
    await isLoaded;
    if (queryText.isNotEmpty != true) return [];
    return (await attributeSchemas.values.whereNotRestricted().search(queryText, isMatchAll: true)).toList();
  }

  /// Looks for fact schemas that match [queryText].  Searches name, label, factTokens
  Future<List<FactSchemaAndDate>> resolveMetaDates(Iterable<MetaDateRef> refs) async {
    final metaDates = [
      for (final ref in refs) await getFactMetaDate(ref),
    ];
    return metaDates;
  }

  Future<FactSchemaAndDate> getFactMetaDate(MetaDateRef ref) async {
    final schema = await loadFactSchema(ref.factRef);
    final date = schema.dates!.firstOrNull((metaDate) => metaDate.path == ref.path);
    return FactSchemaAndDate(schema, date ?? illegalState<IFactMetaDate>("Missing expected fact metadate: $ref"));
  }

  @override
  IFactSchema? getFactSchema(MSchemaRef? ref) {
    final schema = _factSchemas["$ref"];
    if (schema == null) {
      // Trigger a reload
      refreshFactSchemas();
    }
    return schema;
  }

  @override
  FutureOr<IFactSchema> loadFactSchema(MSchemaRef ref) {
    final schema = _factSchemas["$ref"];
    if (schema != null) {
      return schema;
    } else {
      // Trigger a reload
      return refreshFactSchemas().then((_) {
        return _factSchemas["$ref"]!;
      });
    }
  }

  @override
  Future deleteFact(IFact fact) async {
    await _factApi.delete(fact.mkey!.value);
    // fact.mmeta.isDeleted = true;
    _updatedFactController.add(fact);
  }

  Future refreshFactSchemas() async {
    _loaded.start();
    await _factSchemaApi.list(offset: 100).then((schemas) async {
      var schemasByKey = schemas.data.keyed((schema) => "${schema.ref}");
      await _factSchemas.sync(schemasByKey);
      _loaded.complete(true);
      log.info("FACT: Loaded ${_factSchemas.length} fact schemas");
    });
  }

  String getFactEmoji(MSchemaRef? ref) => _factEmoji[ref]!;
}

final _factEmoji = <MSchemaRef, String>{
  BirthdayRef: '🎂',
  FamilyRef: '💍',
};

// /// Finds dates within fact schemas - this implementation retains the original term
// class FactDateSchemaQuery {
//   final String originalQuery;
//   final String matchedTerm;
//   final IFactSchema factSchema;
//   final FactMetaDate metaDate;
//   final IFact fact;
//
//   FactDateSchemaQuery(
//       this.originalQuery, this.matchedTerm, this.factSchema, this.metaDate,
//       [this.fact]);
//
//   FactDateSchemaQuery.ofSchema(this.metaDate, this.factSchema, [this.fact])
//       : originalQuery = metaDate.remindLabel,
//         matchedTerm = metaDate.remindLabel;
//
//   FactDateSchemaQuery withFact(IFact fact) {
//     return FactDateSchemaQuery(this.originalQuery, this.matchedTerm,
//         this.factSchema, this.metaDate, fact);
//   }
// }

extension FactStreamExtension on Stream<IFact> {
  Stream<IFact> byRecordId(MKey recordId) => where((fact) => fact.contactKey == recordId);
}

extension FactExtensions on IFact? {
  Uri? get imageUri {
    final self = this;
    if (self == null) return null;
    if (self is HasImage) {
      return null;
      // return (self as HasImage).imageContent?.imageUrl?.toUri();
    } else if (self is HasImages) {
      return null;
      // return (self as HasImages).imageList?.firstOrNull()?.imageUrl?.toUri();
    } else {
      return null;
    }
  }

  List<HistoryEvent> getHistoryEvents() {
    return this!.factSchema.dates!.where((date) => date.isHistorical == true).mapNotNull((metaDate) {
      final result =
          metaDate.isFlexible == true ? this!.getFlexiDate(metaDate) : this!.getDate(metaDate, sunnyLocalization.userLocation!);
      if (result == null) {
        return null;
      }
      if (result is FlexiDate) {
        return HistoryEvent.ofFlexiDate(sourceFact: this!, metaDate: metaDate, flexiDate: result);
      } else if (result is DateTime) {
        return HistoryEvent.ofDateTime(sourceFact: this!, metaDate: metaDate, date: result);
      } else {
        return illegalState<HistoryEvent>("Expected FlexiDate or DateTime, but was ${result.runtimeType}");
      }
    }).toList();
  }
}

///Wraps a fact and a date, exposes as a SmartDateItem
class HistoryEvent with DiffDelegateMixin implements SmartNotesItem {
  final IFact sourceFact;
  final IFactMetaDate metaDate;
  final DateTime? date;
  final FlexiDate? flexiDate;

  HistoryEvent.ofDateTime({required this.sourceFact, required this.metaDate, required this.date}) : flexiDate = null;

  HistoryEvent.ofFlexiDate({required this.sourceFact, required this.metaDate, required this.flexiDate}) : date = null;

  // @override
  // Widget buildTile(BuildContext context,
  //     {Contact contact, changed, VoidCallback onTap, Widget trailing}) {
  //   return sourceFact.buildTile(context,
  //       contact: contact, onTap: onTap, changed: changed, trailing: trailing);
  // }

  @override
  clone() => this;

  @override
  get diffKey => [sourceFact.id, date, flexiDate, metaDate].whereNotNull().toList();

  @override
  String? get id => sourceFact.mkey?.value;

  @override
  MKey get mkey => sourceFact.mkey!;

  // @override
  // String shortTitle(IContact contact) => "Unknown";

  @override
  bool get showTimestamp => true;

  @override
  DateTime? get smartNoteDate => flexiDate?.toDateTime() ?? date;

  // @override
  // String subtitle(Contact contact) => sourceFact._subtitle(contact);

  @override
  void takeFrom(source) => notImplemented();

  // @override
  // String title(IContact contact) => sourceFact?._title(contact);
  //
  // @override
  // Widget titleTrailing(BuildContext context, IContact contact) => null;
}

extension _FactLabelExt on IFact {
  // String shortTitle(Contact contact) {
  //   final self = this;
  //   return self is LabeledFact ? (self as LabeledFact).title(contact) : null;
  // }

  // String _title(IContact contact) {
  //   final self = this;
  //   return self is LabeledFact ? (self as LabeledFact).title(contact) : null;
  // }
  //
  // String _subtitle(Contact contact) {
  //   final self = this;
  //   return self is LabeledFact ? (self as LabeledFact).subtitle(contact) : null;
  // }
}

extension IterableOfFactSchemasExtension on Iterable<IFactSchema> {
  Iterable<IFactSchema> whereNotRestricted() {
    final restricted = factService.restrictedSchemas;
    return this.orEmpty().where((schema) {
      return !restricted.contains(schema.ref);
    });
  }
}

extension FactSchemaIterableExtension on Iterable<IFactSchema> {
  Future<Iterable<FactDateSchemaQuery>> search(String term, {bool isMatchAll = false}) async {
    final tuples = this.expand((schema) => schema.dates!.map((date) => Tuple(schema, date)));

    final matches = await FullTextSearch<Tuple<IFactSchema, IFactMetaDate>>.ofStream(
      term: term,
      items: Stream.fromIterable(tuples),
      isMatchAll: isMatchAll,
      tokenize: (tuple) => [
        ...tuple.first.tokenize(),
        ...tuple.second.tokenize(),
      ],
    ).execute();
    return [
      ...matches.map((result) {
        final schema = result.result.first;
        final metaDate = result.result.second;
        return FactDateSchemaQuery(term, result.matchedTerms.join(" "), schema, metaDate);
      }),
    ];
  }
}
