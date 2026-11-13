import Foundation
import SQLite3

@main
struct StorageInspectorTests {
    @MainActor
    static func main() throws {
        // 1. Property list XML and binary formatting
        let plistObject: [String: Any] = [
            "APIBaseURL": "https://api.example.test",
            "DebugEnabled": true,
            "SampleCount": 42,
        ]
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let plistData = try PropertyListSerialization.data(fromPropertyList: plistObject, format: format, options: 0)
            let formatted = try VPhoneStorageParser.formatPlist(plistData)
            precondition(formatted.contains("api.example.test") && formatted.contains("42"))
        }

        // 2. JSON formatting
        let jsonData = Data("{\"z\":1,\"a\":\"ok\"}".utf8)
        let formattedJSON = try VPhoneStorageParser.formatJSON(jsonData)
        precondition(formattedJSON.contains("\"a\"") && formattedJSON.contains("\"z\""))

        // 3. Real SQLite3 database inspection + row reading
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("vphone-storage-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let dbURL = tmpDir.appendingPathComponent("cache.sqlite")
        var db: OpaquePointer?
        precondition(sqlite3_open(dbURL.path, &db) == SQLITE_OK && db != nil)
        let createSQL = "CREATE TABLE tokens (id INTEGER PRIMARY KEY, user TEXT, jwt TEXT);"
        precondition(sqlite3_exec(db, createSQL, nil, nil, nil) == SQLITE_OK)
        let insertSQL = "INSERT INTO tokens (user, jwt) VALUES ('alice', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.sig');"
        precondition(sqlite3_exec(db, insertSQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let dbData = try Data(contentsOf: dbURL)
        let dbPreview = try VPhoneStorageParser.inspectSQLite(data: dbData)
        precondition(!dbPreview.encryptedOrUnreadable)
        precondition(dbPreview.tables.count == 1 && dbPreview.tables[0].name == "tokens" && dbPreview.tables[0].rowCount == 1)

        let rows = try VPhoneStorageParser.readSQLiteRows(data: dbData, table: "tokens")
        precondition(rows.columns == ["id", "user", "jwt"] && rows.rows.count == 1)
        precondition(rows.rows[0][1] == "alice")

        // 4. Encrypted/corrupted SQLite detection
        let encryptedPreview = try VPhoneStorageParser.inspectSQLite(data: Data(repeating: 0xAA, count: 4096))
        precondition(encryptedPreview.encryptedOrUnreadable)

        // 5. Sensitive artifact + POSIX permission scanning
        let secretPayload = Data("""
        -----BEGIN PRIVATE KEY-----
        synthetic-key-material
        -----END PRIVATE KEY-----
        bearer=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5OTkifQ.signature
        """.utf8)
        let hits = VPhoneStorageParser.scanFileContents(
            relativePath: "Documents/secrets.txt",
            fullPath: "/var/mobile/Containers/Data/Application/UUID/Documents/secrets.txt",
            permissions: "0666",
            data: secretPayload
        )
        precondition(hits.contains { $0.category.contains("World-Writable") })
        precondition(hits.contains { $0.category.contains("Private Key") })
        precondition(hits.contains { $0.category.contains("JWT") })

        let dbHits = VPhoneStorageParser.scanFileContents(
            relativePath: "Library/cache.sqlite",
            fullPath: "/var/mobile/Containers/Data/Application/UUID/Library/cache.sqlite",
            permissions: "0644",
            data: dbData
        )
        precondition(dbHits.contains { $0.category == "Unencrypted SQLite Database" })

        // 6. Custom SQL query execution & table mutation
        let selectRes = try VPhoneStorageParser.executeSQLite(data: dbData, sql: "SELECT user FROM tokens WHERE id = 1;")
        precondition(selectRes.isQuery && selectRes.rows.count == 1 && selectRes.rows[0][0] == "alice")

        let updateRes = try VPhoneStorageParser.executeSQLite(data: dbData, sql: "UPDATE tokens SET user = 'bob' WHERE id = 1;")
        precondition(!updateRes.isQuery && updateRes.rowsAffected == 1 && updateRes.modifiedData != nil)

        if let mutatedData = updateRes.modifiedData {
            let reCheck = try VPhoneStorageParser.readSQLiteRows(data: mutatedData, table: "tokens")
            precondition(reCheck.rows[0][1] == "bob")
        }

        print("Storage Inspector checks passed: XML/binary plist, SQLite3 table & row inspection, encrypted DB detection, secret/permission scanner, and custom SQL query runner.")
    }
}
