import MachO

/// Finds the types that conform to a protocol by reading the Swift conformance records
/// (`__TEXT,__swift5_proto`) of every image loaded into the process, except the system's.
///
/// Swift has no public API to enumerate conformances. The records' layout is part of Swift's
/// stable ABI: https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeMetadata.rst
enum ConformanceScanner {
    /// The non-generic structs, enums, and classes that conform to a protocol named `protocolName`.
    static func types(conformingTo protocolName: String) -> [Any.Type] {
        var types: [Any.Type] = []
        for index in 0 ..< _dyld_image_count() {
            guard let header = _dyld_get_image_header(index),
                  let imageName = _dyld_get_image_name(index),
                  !isSystemImage(String(cString: imageName))
            else { continue }
            var size: UInt = 0
            let machHeader = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            guard let section = getsectiondata(machHeader, "__TEXT", "__swift5_proto", &size) else { continue }
            let records = UnsafeRawPointer(section)
            for offset in stride(from: 0, to: Int(size), by: MemoryLayout<Int32>.size) {
                if let type = conformingType(record: records.advanced(by: offset), protocolName: protocolName) {
                    types.append(type)
                }
            }
        }
        return types
    }

    private static func isSystemImage(_ path: String) -> Bool {
        path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/")
            || path.contains(".simruntime/") || path.contains(".platform/")
    }

    /// Reads one conformance record: a relative pointer to a protocol conformance descriptor,
    /// whose fields are the protocol, the conforming type, the witness table pattern, and flags.
    private static func conformingType(record: UnsafeRawPointer, protocolName: String) -> Any.Type? {
        guard let conformance = relativePointer(at: record),
              let protocolDescriptor = relativePointer(at: conformance, indirectable: true),
              // A protocol descriptor's name follows its flags and parent.
              let name = relativePointer(at: protocolDescriptor.advanced(by: 8)),
              String(cString: name.assumingMemoryBound(to: CChar.self)) == protocolName
        else { return nil }

        let flags = conformance.load(fromByteOffset: 12, as: UInt32.self)
        let typeField = conformance.advanced(by: 4)
        let typeDescriptor: UnsafeRawPointer? = switch (flags >> 3) & 0x7 {
        case 0: relativePointer(at: typeField)
        case 1: relativePointer(at: typeField)?.load(as: UnsafeRawPointer?.self)
        default: nil // Objective-C classes
        }
        guard let typeDescriptor else { return nil }

        let descriptorFlags = typeDescriptor.load(as: UInt32.self)
        let kind = descriptorFlags & 0x1F
        let isGeneric = descriptorFlags & 0x80 != 0
        // 16: class, 17: struct, 18: enum. Generic types have no metadata without arguments.
        guard (16 ... 18).contains(kind), !isGeneric,
              // A type descriptor's metadata access function follows its flags, parent, and name.
              let accessFunction = relativePointer(at: typeDescriptor.advanced(by: 12))
        else { return nil }
        typealias MetadataAccessFunction = @convention(c) (Int) -> UnsafeRawPointer
        let metadata = unsafeBitCast(accessFunction, to: MetadataAccessFunction.self)(0)
        return unsafeBitCast(metadata, to: Any.Type.self)
    }

    /// Resolves a 32-bit offset relative to its own address. An indirectable pointer with its low
    /// bit set points at a pointer instead, which is null when the target was weakly linked away.
    private static func relativePointer(at field: UnsafeRawPointer, indirectable: Bool = false) -> UnsafeRawPointer? {
        let offset = Int(field.load(as: Int32.self))
        guard offset != 0 else { return nil }
        guard indirectable, offset & 1 == 1 else { return field.advanced(by: offset) }
        return field.advanced(by: offset & ~1).load(as: UnsafeRawPointer?.self)
    }
}
