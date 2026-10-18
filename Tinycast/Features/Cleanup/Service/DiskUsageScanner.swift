import Darwin
import Foundation

/// Sizes folders by the blocks they occupy, which is what removing them gives back.
nonisolated enum DiskUsageScanner {
    struct Measurement: Equatable, Sendable {
        var bytes: Int64 = 0
        /// A folder inside could not be read, so the total is a floor.
        var isPartial = false
    }

    /// At most `width` trees at once, delivered in batches so a list repaints at a bounded rate.
    @concurrent
    static func measure(
        _ paths: [String], width: Int = 6, flushInterval: Duration = .milliseconds(100),
        skipping: Set<String> = [],
        onMeasured: @escaping @Sendable @MainActor ([(String, Measurement)]) -> Void
    ) async {
        await withTaskGroup(of: (String, Measurement)?.self) { group in
            var pending = paths.makeIterator()
            for _ in 0..<width {
                guard let path = pending.next() else { break }
                group.addTask { (try? measure(path, skipping: skipping)).map { (path, $0) } }
            }
            var batch: [(String, Measurement)] = []
            let clock = ContinuousClock()
            var lastFlush = clock.now
            for await result in group {
                if let result { batch.append(result) }
                if let path = pending.next(), !Task.isCancelled {
                    group.addTask { (try? measure(path, skipping: skipping)).map { (path, $0) } }
                }
                guard !batch.isEmpty, clock.now - lastFlush >= flushInterval else { continue }
                let flushed = batch
                batch.removeAll(keepingCapacity: true)
                lastFlush = clock.now
                await onMeasured(flushed)
            }
            if !batch.isEmpty, !Task.isCancelled { await onMeasured(batch) }
        }
    }

    /// A symlink is sized as itself and never followed; a missing path throws.
    /// `skipping` names folders never opened, such as TCC-guarded ones; the total becomes a floor.
    static func measure(_ path: String, skipping: Set<String> = []) throws -> Measurement {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw POSIXError(.ENOENT) }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            return Measurement(bytes: Int64(info.st_blocks) * 512)
        }
        return try withoutMaterializing { try walk(path, skipping: skipping) }
    }

    private static let bufferSize = 64 * 1024

    private static func walk(_ root: String, skipping: Set<String>) throws -> Measurement {
        var measurement = Measurement()
        var seenLinks = Set<UInt64>()
        var folders = [root]
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        while let folder = folders.popLast() {
            try Task.checkCancellation()
            // A non-empty set means no Full Disk Access, and then a photo library prompts too.
            if !skipping.isEmpty, skipping.contains(folder) || folder.lowercased().hasSuffix(".photoslibrary") {
                measurement.isPartial = true
                continue
            }
            let descriptor = open(folder, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                measurement.isPartial = true
                continue
            }
            defer { close(descriptor) }
            var request = request
            while true {
                let count = getattrlistbulk(descriptor, &request, buffer.baseAddress!, buffer.count, 0)
                if count < 0 { measurement.isPartial = true }
                guard count > 0 else { break }
                var record = UnsafeRawPointer(buffer.baseAddress!)
                for _ in 0..<count {
                    tally(record, folder: folder, into: &measurement, seen: &seenLinks, folders: &folders)
                    record += Int(record.loadUnaligned(as: UInt32.self))
                }
            }
        }
        return measurement
    }

    private static let request: attrlist = {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr =
            attrgroup_t(truncatingIfNeeded: ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_NAME)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_ERROR)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_OBJTYPE)
            | attrgroup_t(truncatingIfNeeded: ATTR_CMN_FILEID)
        request.dirattr = attrgroup_t(truncatingIfNeeded: ATTR_DIR_MOUNTSTATUS)
        request.fileattr =
            attrgroup_t(truncatingIfNeeded: ATTR_FILE_LINKCOUNT)
            | attrgroup_t(truncatingIfNeeded: ATTR_FILE_ALLOCSIZE)
        return request
    }()

    /// Fields arrive in bit order within each group, and the error right after the returned set.
    private static func tally(
        _ record: UnsafeRawPointer, folder: String, into measurement: inout Measurement,
        seen: inout Set<UInt64>, folders: inout [String]
    ) {
        let returned = record.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
        var field = record + 4 + MemoryLayout<attribute_set_t>.size
        if returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_ERROR) != 0 {
            let error = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
            if error != 0 {
                measurement.isPartial = true
                return
            }
        }
        guard returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_NAME) != 0 else { return }
        let reference = field.loadUnaligned(as: attrreference_t.self)
        let name = (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
        field += MemoryLayout<attrreference_t>.size
        var type: UInt32 = 0
        if returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_OBJTYPE) != 0 {
            type = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        var fileID: UInt64 = 0
        if returned.commonattr & attrgroup_t(truncatingIfNeeded: ATTR_CMN_FILEID) != 0 {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }
        if type == VDIR.rawValue {
            if returned.dirattr & attrgroup_t(truncatingIfNeeded: ATTR_DIR_MOUNTSTATUS) != 0 {
                let status = field.loadUnaligned(as: UInt32.self)
                if status & UInt32(DIR_MNTSTATUS_MNTPOINT | DIR_MNTSTATUS_TRIGGER) != 0 { return }
            }
            folders.append(folder + "/" + String(cString: name))
            return
        }
        var links: UInt32 = 1
        if returned.fileattr & attrgroup_t(truncatingIfNeeded: ATTR_FILE_LINKCOUNT) != 0 {
            links = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        guard returned.fileattr & attrgroup_t(truncatingIfNeeded: ATTR_FILE_ALLOCSIZE) != 0 else { return }
        // A hard link's blocks are freed only with its last name, so each inode counts once.
        if links > 1, !seen.insert(fileID).inserted { return }
        measurement.bytes += field.loadUnaligned(as: Int64.self)
    }

    /// Per thread, and restored after: sizing must never download a dataless iCloud file.
    private static func withoutMaterializing<T>(_ body: () throws -> T) rethrows -> T {
        let type = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES
        let previous = getiopolicy_np(type, IOPOL_SCOPE_THREAD)
        setiopolicy_np(type, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer { if previous >= 0 { setiopolicy_np(type, IOPOL_SCOPE_THREAD, previous) } }
        return try body()
    }
}
