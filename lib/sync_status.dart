import 'package:floor/floor.dart';

@Entity(tableName: "SyncStatus", indices: [
  Index(
      name: "sync_unique",
      value: ["accountId", "type", "subjectId"],
      unique: true),
])
class SyncStatus {
  @PrimaryKey(autoGenerate: true)
  final int? id;
  final String accountId;
  final String type;
  final String subjectId;
  final String checkSum;

  SyncStatus(this.id, this.accountId, this.type, this.subjectId, this.checkSum);

  SyncStatus.create(
      {required this.accountId,
      required this.type,
      required this.subjectId,
      required this.checkSum})
      : this.id = null;

  SyncStatus withChecksum(String checksum) {
    return SyncStatus(id, accountId, type, subjectId, checksum);
  }
}

@dao
abstract class SyncStatusRepo {
  @Query(
      'SELECT * FROM SyncStatus WHERE accountId = :accountId AND type = :type AND subjectId = :subjectId')
  Future<SyncStatus> findSyncStatus(
      String accountId, String type, String subjectId);

  @Query(
      'SELECT * FROM SyncStatus WHERE accountId = :accountId AND type = :type')
  Future<List<SyncStatus>> listSyncStatusByType(String accountId, String type);

  @Insert(onConflict: OnConflictStrategy.replace)
  Future<void> insertSyncStatus(SyncStatus status);
}
