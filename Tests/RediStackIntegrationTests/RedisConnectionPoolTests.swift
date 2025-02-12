//===----------------------------------------------------------------------===//
//
// This source file is part of the RediStack open source project
//
// Copyright (c) 2020 Apple Inc. and the RediStack project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of RediStack project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Logging
import NIOCore
import RediStackTestUtils
import XCTest

@testable import RediStack

final class RedisConnectionPoolTests: RediStackConnectionPoolIntegrationTestCase {
    func test_basicPooledOperation() throws {
        // We're going to insert a bunch of elements into a set, and then when all is done confirm that every
        // element exists.
        let operations = (0..<50).map { number in
            self.pool.sadd([number], to: #function)
        }
        let results = try EventLoopFuture<Int>.whenAllSucceed(operations, on: self.eventLoopGroup.next()).wait()
        XCTAssertEqual(results, Array(repeating: 1, count: 50))
        let whatRedisThinks = try self.pool.smembers(of: #function, as: Int.self).wait()
        XCTAssertEqual(whatRedisThinks.compactMap { $0 }.sorted(), Array(0..<50))
    }

    func test_closedPoolDoesNothing() throws {
        self.pool.close()
        XCTAssertThrowsError(try self.pool.increment(#function).wait()) { error in
            XCTAssertEqual(error as? RedisConnectionPoolError, .poolClosed)
        }
    }

    func test_nilConnectionRetryTimeoutStillWorks() throws {
        let pool = try self.makeNewPool(connectionRetryTimeout: nil)
        defer { pool.close() }
        XCTAssertNoThrow(try pool.get(#function).wait())
    }

    func test_noConnectionAttemptsUntilAddressesArePresent() throws {
        // Note the config here: we have no initial addresses, the connecton backoff delay is 10 seconds, and the retry timeout is only 5 seconds.
        // The effect of this config is that if we fail a connection attempt, we'll fail it forever.
        let pool = try self.makeNewPool(
            initialAddresses: [],
            initialConnectionBackoffDelay: .seconds(10),
            connectionRetryTimeout: .seconds(5),
            minimumConnectionCount: 0
        )
        defer { pool.close() }

        // As above we're gonna try to insert a bunch of elements into a set. This time,
        // the pool has no addresses yet. We expect that when we add an address later everything will work nicely.
        // We do fewer here.
        let operations = (0..<10).map { number in
            pool.sadd([number], to: #function)
        }

        // Now that we've kicked those off, let's hand over a new address.
        try pool.updateConnectionAddresses([
            SocketAddress.makeAddressResolvingHost(self.redisHostname, port: self.redisPort)
        ])

        // We should get the results.
        let results = try EventLoopFuture<Int>.whenAllSucceed(operations, on: self.eventLoopGroup.next()).wait()
        XCTAssertEqual(results, Array(repeating: 1, count: 10))
    }

    func testDelayedConnectionsFailOnClose() throws {
        // Note the config here: we have no initial addresses, the connecton backoff delay is 10 seconds, and the retry timeout is only 5 seconds.
        // The effect of this config is that if we fail a connection attempt, we'll fail it forever.
        let pool = try self.makeNewPool(
            initialAddresses: [],
            initialConnectionBackoffDelay: .seconds(10),
            connectionRetryTimeout: .seconds(5),
            minimumConnectionCount: 0
        )
        defer { pool.close() }

        // As above we're gonna try to insert a bunch of elements into a set. This time,
        // the pool has no addresses yet. We expect that when we add an address later everything will work nicely.
        // We do fewer here.
        let operations = (0..<10).map { number in
            pool.sadd([number], to: #function)
        }

        // Now that we've kicked those off, let's close.
        pool.close()

        let results = try EventLoopFuture<Int>.whenAllComplete(operations, on: self.eventLoopGroup.next()).wait()
        for result in results {
            switch result {
            case .success:
                XCTFail("Request succeeded")
            case .failure(let error) where error as? RedisConnectionPoolError == .poolClosed:
                ()  // Pass
            case .failure(let error):
                XCTFail("Unexpected failure: \(error)")
            }
        }
    }
}

// MARK: Leasing a connection

extension RedisConnectionPoolTests {
    func test_borrowedConnectionStillReturnsOnError() throws {
        enum TestError: Error { case expected }

        let maxConnectionCount = 4
        let pool = try self.makeNewPool(minimumConnectionCount: maxConnectionCount)
        defer { pool.close() }
        _ = try pool.ping().wait()

        let promise = pool.eventLoop.makePromise(of: Void.self)

        XCTAssertEqual(pool.availableConnectionCount, maxConnectionCount)
        defer { XCTAssertEqual(pool.availableConnectionCount, maxConnectionCount) }

        let future = pool.leaseConnection { _ in promise.futureResult }

        promise.fail(TestError.expected)
        XCTAssertThrowsError(try future.wait()) {
            XCTAssertTrue($0 is TestError)
        }
    }

    func test_borrowedConnectionClosureHasExclusiveAccess() throws {
        let maxConnectionCount = 4
        let pool = try self.makeNewPool(minimumConnectionCount: maxConnectionCount)
        defer { pool.close() }
        // populate the connection pool
        _ = try pool.ping().wait()

        // assert that we have the max number of connections available,
        XCTAssertEqual(pool.availableConnectionCount, maxConnectionCount)

        // borrow a connection, asserting that we've taken the connection out of the pool while we do "something" with it
        // and then assert afterwards that it's back in the pool

        let promises: [EventLoopPromise<Void>] = [pool.eventLoop.makePromise(), pool.eventLoop.makePromise()]
        let futures = promises.indices
            .map { index in
                pool
                    .leaseConnection { connection -> EventLoopFuture<Void> in
                        XCTAssertTrue(pool.availableConnectionCount < maxConnectionCount)

                        return promises[index].futureResult
                    }
            }

        for promise in promises {
            promise.succeed(())
        }
        _ = try EventLoopFuture<Void>
            .whenAllSucceed(futures, on: pool.eventLoop)
            .always { _ in
                XCTAssertEqual(pool.availableConnectionCount, maxConnectionCount)
            }
            .wait()
    }
}
