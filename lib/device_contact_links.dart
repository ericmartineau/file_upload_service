import 'package:floor/floor.dart';

@Entity(tableName: "DeviceContactLink", indices: [
  Index(name: "link_key", value: ["accountId", "sunnyId"], unique: true),
  Index(value: ["deviceContactId"]),
])
class DeviceContactLink {
  @PrimaryKey(autoGenerate: true)
  final int? id;
  final String accountId;
  final String sunnyId;
  final String deviceContactId;

  DeviceContactLink(
      this.id, this.accountId, this.sunnyId, this.deviceContactId);

  DeviceContactLink.create(
      {required this.accountId,
      required this.sunnyId,
      required this.deviceContactId})
      : this.id = null;
}

@dao
abstract class DeviceContactLinkRepo {
  @Query(
      'SELECT * FROM DeviceContactLink WHERE accountId = :accountId AND sunnyId = :sunnyId')
  Future<DeviceContactLink> findLocalLink(String accountId, String sunnyId);

  @Insert(onConflict: OnConflictStrategy.replace)
  Future<void> insert(DeviceContactLink status);
}
