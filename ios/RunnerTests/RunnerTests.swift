import Flutter
import StoreKit
import StoreKitTest
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}

/// Real-StoreKit end-to-end subscription test (Apple's StoreKit Test, not
/// App Store sandbox), run by .github/workflows/storekit-e2e.yml.
///
/// The app is built with integration_test/storekit_e2e_test.dart as its Dart
/// entry point. That Dart test drives the real app (AppStoreService, the
/// in_app_purchase plugin, StoreKit 2) and controls Apple's SKTestSession
/// through the "datewise/storekit_test" channel this test registers on the
/// app's Flutter engine: reset, Ask to Buy, time rate, expire, renew, refund,
/// cancel auto-renew. When the Dart scenarios finish they send their results
/// here and each one becomes an XCTest assertion.
///
/// The session uses ios/Runner/DateWise.storekit (datewise_premium_monthly).
/// When the app was built from lib/main.dart nothing answers the channel and
/// this test is skipped.
final class StoreKitE2ETests: XCTestCase {

  func testStoreKitSubscriptionEndToEnd() throws {
    let messenger = try XCTUnwrap(Self.waitForMessenger(timeout: 60), "No FlutterViewController in the app")
    let bridge = StoreKitTestBridge()
    bridge.install(on: messenger)

    // The Dart test pings the channel first; without it this build is the
    // normal app, not the StoreKit end-to-end build.
    Self.spin(until: { bridge.pinged }, timeout: 90)
    guard bridge.pinged else {
      throw XCTSkip("integration_test/storekit_e2e_test.dart is not the Dart entry point of this build")
    }

    Self.spin(until: { bridge.results != nil }, timeout: 30 * 60)
    let results = try XCTUnwrap(bridge.results, "The Dart StoreKit scenarios did not report within 30 minutes")
    XCTAssertFalse(results.isEmpty, "No StoreKit scenarios ran")
    for (name, outcome) in results.sorted(by: { $0.key < $1.key }) {
      let passed = outcome == "success"
      print("[storekit-e2e] \(passed ? "PASS" : "FAIL"): \(name)")
      XCTAssertTrue(passed, "\(name): \(outcome)")
    }
  }

  private static func spin(until done: () -> Bool, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while !done() && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
  }

  private static func waitForMessenger(timeout: TimeInterval) -> FlutterBinaryMessenger? {
    var found: FlutterBinaryMessenger?
    spin(until: {
      found = flutterViewController()?.binaryMessenger
      return found != nil
    }, timeout: timeout)
    return found
  }

  private static func flutterViewController() -> FlutterViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    for window in windows {
      if let vc = window.rootViewController as? FlutterViewController { return vc }
      if let vc = window.rootViewController?.children.compactMap({ $0 as? FlutterViewController }).first {
        return vc
      }
    }
    return nil
  }
}

/// Answers the Dart test's SKTestSession commands. Everything runs on the
/// main thread (platform channel handlers and the XCTest run loop).
final class StoreKitTestBridge {
  private var session: SKTestSession?
  private var channel: FlutterMethodChannel?
  private(set) var pinged = false
  private(set) var results: [String: String]?

  func install(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "datewise/storekit_test", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(FlutterError(code: "gone", message: nil, details: nil)) }
      do {
        result(try self.handle(call))
      } catch {
        result(FlutterError(code: "storekit_test", message: "\(call.method): \(error)", details: nil))
      }
    }
    self.channel = channel
  }

  private static func configURL() throws -> URL {
    if let url = Bundle(for: StoreKitTestBridge.self).url(forResource: "DateWise", withExtension: "storekit") {
      return url
    }
    // Simulator processes can read the Mac's file system: use the
    // configuration file checked in next to the app's sources.
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Runner/DateWise.storekit")
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw NSError(domain: "StoreKitTestBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(url.path)"])
    }
    return url
  }

  private func activeSession() throws -> SKTestSession {
    if let session = session { return session }
    let created = try SKTestSession(contentsOf: try Self.configURL())
    session = created
    return created
  }

  private func reset(_ s: SKTestSession) {
    s.resetToDefaultState()
    s.clearTransactions()
    s.disableDialogs = true
    s.askToBuyEnabled = false
    s.timeRate = .realTime
    s.storefront = "USA"
    s.locale = Locale(identifier: "en_US")
  }

  private func handle(_ call: FlutterMethodCall) throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "ping":
      pinged = true
      return "pong"
    case "reset":
      reset(try activeSession())
      return nil
    case "setAskToBuy":
      let s = try activeSession()
      s.askToBuyEnabled = (args["enabled"] as? Bool) ?? false
      return nil
    case "setTimeRate":
      let s = try activeSession()
      switch args["rate"] as? String {
      case "monthlyRenewalEveryThirtySeconds": s.timeRate = .monthlyRenewalEveryThirtySeconds
      default: s.timeRate = .realTime
      }
      return nil
    case "transactions":
      return try activeSession().allTransactions().map { t -> [String: Any] in
        var m: [String: Any] = [
          "id": t.identifier,
          "originalId": t.originalTransactionIdentifier,
          "productId": t.productIdentifier,
          "pendingAskToBuy": t.pendingAskToBuyConfirmation,
          "autoRenew": t.autoRenewingEnabled,
          "state": t.state.rawValue,
          "purchaseMs": Int(t.purchaseDate.timeIntervalSince1970 * 1000),
        ]
        if let d = t.expirationDate { m["expirationMs"] = Int(d.timeIntervalSince1970 * 1000) }
        if let d = t.cancelDate { m["cancelMs"] = Int(d.timeIntervalSince1970 * 1000) }
        return m
      }
    case "expire":
      try activeSession().expireSubscription(productIdentifier: try Self.string(args, "productId"))
      return nil
    case "forceRenew":
      try activeSession().forceRenewalOfSubscription(productIdentifier: try Self.string(args, "productId"))
      return nil
    case "refund":
      try activeSession().refundTransaction(identifier: try Self.int(args, "id"))
      return nil
    case "approveAskToBuy":
      try activeSession().approveAskToBuyTransaction(identifier: try Self.int(args, "id"))
      return nil
    case "declineAskToBuy":
      try activeSession().declineAskToBuyTransaction(identifier: try Self.int(args, "id"))
      return nil
    case "disableAutoRenew":
      try activeSession().disableAutoRenewForTransaction(identifier: try Self.int(args, "id"))
      return nil
    case "log":
      print("[storekit-e2e] \(args["message"] as? String ?? "")")
      return nil
    case "done":
      results = (args["results"] as? [String: String]) ?? [:]
      return nil
    default:
      throw NSError(domain: "StoreKitTestBridge", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown method"])
    }
  }

  private static func string(_ args: [String: Any], _ key: String) throws -> String {
    guard let v = args[key] as? String else {
      throw NSError(domain: "StoreKitTestBridge", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing \(key)"])
    }
    return v
  }

  private static func int(_ args: [String: Any], _ key: String) throws -> Int {
    guard let v = args[key] as? Int else {
      throw NSError(domain: "StoreKitTestBridge", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing \(key)"])
    }
    return v
  }
}
