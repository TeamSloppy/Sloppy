import Foundation
#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum PlatformDynamicLibrary {
    static func open(_ path: String) -> UnsafeMutableRawPointer? {
        #if os(Windows)
        return path.withCString(encodedAs: UTF16.self) { name in
            LoadLibraryExW(name, nil, DWORD(LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS))
                .map { UnsafeMutableRawPointer($0) }
        }
        #else
        return dlopen(path, RTLD_NOW | RTLD_LOCAL)
        #endif
    }

    static func symbol(_ handle: UnsafeMutableRawPointer, _ name: String) -> UnsafeMutableRawPointer? {
        #if os(Windows)
        return GetProcAddress(handle.assumingMemoryBound(to: HINSTANCE__.self), name).map { unsafeBitCast($0, to: UnsafeMutableRawPointer.self) }
        #else
        return dlsym(handle, name)
        #endif
    }

    static func close(_ handle: UnsafeMutableRawPointer) {
        #if os(Windows)
        _ = FreeLibrary(handle.assumingMemoryBound(to: HINSTANCE__.self))
        #else
        dlclose(handle)
        #endif
    }

    static var lastError: String {
        #if os(Windows)
        return "Windows library loader error \(GetLastError())"
        #else
        return dlerror().map { String(cString: $0) } ?? "Unknown library loader error"
        #endif
    }
}
