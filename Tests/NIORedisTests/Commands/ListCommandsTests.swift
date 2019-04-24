@testable import NIORedis
import XCTest

final class ListCommandsTests: XCTestCase {
    private var connection: RedisConnection!

    override func setUp() {
        do {
            connection = try RedisConnection.connect().wait()
        } catch {
            XCTFail("Failed to create RedisConnection! \(error)")
        }
    }

    override func tearDown() {
        _ = try? connection.send(command: "FLUSHALL").wait()
        try? connection.close().wait()
        connection = nil
    }

    func test_llen() throws {
        var length = try connection.llen(of: #function).wait()
        XCTAssertEqual(length, 0)
        _ = try connection.lpush([30], into: #function).wait()
        length = try connection.llen(of: #function).wait()
        XCTAssertEqual(length, 1)
    }

    func test_lindex() throws {
        var element = try connection.lindex(0, from: #function).wait()
        XCTAssertTrue(element.isNull)

        _ = try connection.lpush([10], into: #function).wait()

        element = try connection.lindex(0, from: #function).wait()
        XCTAssertFalse(element.isNull)
        XCTAssertEqual(Int(element), 10)
    }

    func test_lset() throws {
        XCTAssertThrowsError(try connection.lset(index: 0, to: 30, in: #function).wait())
        _ = try connection.lpush([10], into: #function).wait()
        XCTAssertNoThrow(try connection.lset(index: 0, to: 30, in: #function).wait())
        let element = try connection.lindex(0, from: #function).wait()
        XCTAssertEqual(Int(element), 30)
    }

    func test_lrem() throws {
        _ = try connection.lpush([10, 10, 20, 30, 10], into: #function).wait()
        var count = try connection.lrem(10, from: #function, count: 2).wait()
        XCTAssertEqual(count, 2)
        count = try connection.lrem(10, from: #function, count: 2).wait()
        XCTAssertEqual(count, 1)
    }

    func test_lrange() throws {
        var elements = try connection.lrange(within: (0, 10), from: #function).wait()
        XCTAssertEqual(elements.count, 0)

        _ = try connection.lpush([5, 4, 3, 2, 1], into: #function).wait()

        elements = try connection.lrange(within: (0, 4), from: #function).wait()
        XCTAssertEqual(elements.count, 5)
        XCTAssertEqual(Int(elements[0]), 1)
        XCTAssertEqual(Int(elements[4]), 5)

        elements = try connection.lrange(within: (2, 0), from: #function).wait()
        XCTAssertEqual(elements.count, 0)

        elements = try connection.lrange(within: (4, 5), from: #function).wait()
        XCTAssertEqual(elements.count, 1)

        elements = try connection.lrange(within: (0, -4), from: #function).wait()
        XCTAssertEqual(elements.count, 2)
    }

    func test_rpoplpush() throws {
        _ = try connection.lpush([10], into: "first").wait()
        _ = try connection.lpush([30], into: "second").wait()

        var element = try connection.rpoplpush(from: "first", to: "second").wait()
        XCTAssertEqual(Int(element), 10)
        XCTAssertEqual(try connection.llen(of: "first").wait(), 0)
        XCTAssertEqual(try connection.llen(of: "second").wait(), 2)

        element = try connection.rpoplpush(from: "second", to: "first").wait()
        XCTAssertEqual(Int(element), 30)
        XCTAssertEqual(try connection.llen(of: "second").wait(), 1)
    }

    func test_linsert() throws {
        _ = try connection.lpush([10], into: #function).wait()

        _ = try connection.linsert(20, into: #function, after: 10).wait()
        var elements = try connection.lrange(within: (0, 1), from: #function)
            .map { response in response.compactMap { Int($0) } }
            .wait()
        XCTAssertEqual(elements, [10, 20])

        _ = try connection.linsert(30, into: #function, before: 10).wait()
        elements = try connection.lrange(within: (0, 2), from: #function)
            .map { response in response.compactMap { Int($0) } }
            .wait()
        XCTAssertEqual(elements, [30, 10, 20])
    }

    func test_lpop() throws {
        var element = try connection.lpop(from: #function).wait()
        XCTAssertTrue(element.isNull)

        _ = try connection.lpush([10, 20, 30], into: #function).wait()

        element = try connection.lpop(from: #function).wait()
        XCTAssertFalse(element.isNull)
        XCTAssertEqual(Int(element), 30)
    }

    func test_lpush() throws {
        _ = try connection.rpush([10, 20, 30], into: #function).wait()

        let size = try connection.lpush([100], into: #function).wait()
        let element = try connection.lindex(0, from: #function).wait()
        XCTAssertEqual(size, 4)
        XCTAssertEqual(Int(element), 100)
    }

    func test_lpushx() throws {
        var size = try connection.lpushx(10, into: #function).wait()
        XCTAssertEqual(size, 0)

        _ = try connection.lpush([10], into: #function).wait()

        size = try connection.lpushx(30, into: #function).wait()
        XCTAssertEqual(size, 2)
        let element = try connection.rpop(from: #function)
            .map { return Int($0) }
            .wait()
        XCTAssertEqual(element, 10)
    }

    func test_rpop() throws {
        _ = try connection.lpush([10, 20, 30], into: #function).wait()

        let element = try connection.rpop(from: #function).wait()
        XCTAssertNotNil(element)
        XCTAssertEqual(Int(element), 10)

        _ = try connection.delete([#function]).wait()

        let result = try connection.rpop(from: #function).wait()
        XCTAssertTrue(result.isNull)
    }

    func test_rpush() throws {
        _ = try connection.lpush([10, 20, 30], into: #function).wait()

        let size = try connection.rpush([100], into: #function).wait()
        let element = try connection.lindex(3, from: #function).wait()
        XCTAssertEqual(size, 4)
        XCTAssertEqual(Int(element), 100)
    }

    func test_rpushx() throws {
        var size = try connection.rpushx(10, into: #function).wait()
        XCTAssertEqual(size, 0)

        _ = try connection.rpush([10], into: #function).wait()

        size = try connection.rpushx(30, into: #function).wait()
        XCTAssertEqual(size, 2)
        let element = try connection.lpop(from: #function)
            .map { return Int($0) }
            .wait()
        XCTAssertEqual(element, 10)
    }

    static var allTests = [
        ("test_llen", test_llen),
        ("test_lindex", test_lindex),
        ("test_lset", test_lset),
        ("test_lrem", test_lrem),
        ("test_lrange", test_lrange),
        ("test_rpoplpush", test_rpoplpush),
        ("test_linsert", test_linsert),
        ("test_lpop", test_lpop),
        ("test_lpush", test_lpush),
        ("test_lpushx", test_lpushx),
        ("test_rpop", test_rpop),
        ("test_rpush", test_rpush),
        ("test_rpushx", test_rpushx),
    ]
}
