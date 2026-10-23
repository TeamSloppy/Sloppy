import Foundation
import Protocols
#if canImport(CSQLite3)
import CSQLite3
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
#endif

extension SQLiteStore {
#if canImport(CSQLite3)
    func bindText(_ value: String, at index: Int32, statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, sqliteTransient)
    }
#endif

#if canImport(CSQLite3)
    func bindOptionalText(_ value: String?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            bindText(value, at: index, statement: statement)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
#endif

#if canImport(CSQLite3)
    func bindOptionalInt(_ value: Int?, at index: Int32, statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
#endif

#if canImport(CSQLite3)
    func optionalText(statement: OpaquePointer?, index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }
#endif

#if canImport(CSQLite3)
    func optionalInt(statement: OpaquePointer?, index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int(statement, index))
    }
#endif

#if canImport(CSQLite3)
    func jsonString<T: Encodable>(_ value: T, fallback: String) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? fallback
    }
#endif

#if canImport(CSQLite3)
    func decodeJSON<T: Decodable>(_ type: T.Type, from value: String, fallback: T) -> T {
        (try? JSONDecoder().decode(type, from: Data(value.utf8))) ?? fallback
    }
#endif
}
