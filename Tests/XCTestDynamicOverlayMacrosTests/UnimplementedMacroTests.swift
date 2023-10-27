import MacroTesting
import XCTest
import XCTestDynamicOverlayMacros

final class UnimplementedMacroTests: XCTestCase {
  override func invokeTest() {
    withMacroTesting(
      // isRecording: true,
      macros: [UnimplementedMacro.self]
    ) {
      super.invokeTest()
    }
  }

  func testBasics() {
    assertMacro {
      """
      struct Client {
        @Unimplemented
        var endpoint: () -> Void
      }
      """
    } expansion: {
      """
      struct Client {
        var endpoint: () -> Void {
          @storageRestrictions(initializes: _endpoint)
          init(initialValue) {
            _endpoint = initialValue
          }
          get {
            _endpoint
          }
          set {
            var implemented = _$Implemented("endpoint")
            _endpoint = {
              implemented.fulfill()
              return newValue()
            }
          }
        }

        private var _endpoint: () -> Void = {
          XCTestDynamicOverlay.XCTFail("Unimplemented: 'endpoint'")
        }
      }
      """
    }
  }

  func testArguments() {
    assertMacro {
      """
      struct Client {
        @Unimplemented
        var endpoint: (String, Int, Bool) -> Void
      }
      """
    } expansion: {
      """
      struct Client {
        var endpoint: (String, Int, Bool) -> Void {
          @storageRestrictions(initializes: _endpoint)
          init(initialValue) {
            _endpoint = initialValue
          }
          get {
            _endpoint
          }
          set {
            var implemented = _$Implemented("endpoint")
            _endpoint = {
              implemented.fulfill()
              return newValue($0, $1, $2)
            }
          }
        }

        private var _endpoint: (String, Int, Bool) -> Void = { _, _, _ in
          XCTestDynamicOverlay.XCTFail("Unimplemented: 'endpoint'")
        }
      }
      """
    }
  }

  func testReturnValueNoDefault() {
    assertMacro {
      """
      struct Client {
        @Unimplemented
        var endpoint: (String) -> Bool
      }
      """
    } diagnostics: {
      """
      struct Client {
        @Unimplemented
        ──────────────┬
                      ╰─ 🛑 Missing argument for parameter 'default' in call
                         ✏️ Insert 'default: <#Bool#>'
        var endpoint: (String) -> Bool
      }
      """
    } fixes: {
      """
      struct Client {
        @Unimplemented(default: <#Bool#>)
      }
      """
    } expansion: {
      """
      struct Client {(default: <#Bool#>)
      }
      """
    }
  }

  func testReturnValueDefault() {
    assertMacro {
      """
      struct Client {
        @Unimplemented(default: true)
        var endpoint: (String) -> Bool
      }
      """
    } expansion: {
      """
      struct Client {
        var endpoint: (String) -> Bool {
          @storageRestrictions(initializes: _endpoint)
          init(initialValue) {
            _endpoint = initialValue
          }
          get {
            _endpoint
          }
          set {
            var implemented = _$Implemented("endpoint")
            _endpoint = {
              implemented.fulfill()
              return newValue($0)
            }
          }
        }

        private var _endpoint: (String) -> Bool = { _ in
          XCTestDynamicOverlay.XCTFail("Unimplemented: 'endpoint'")
          return true
        }
      }
      """
    }
  }

  func testThrowingNoDefault() {
    assertMacro {
      """
      struct Client {
        @Unimplemented
        var endpoint: (String) throws -> Bool
      }
      """
    } expansion: {
      """
      struct Client {
        var endpoint: (String) throws -> Bool {
          @storageRestrictions(initializes: _endpoint)
          init(initialValue) {
            _endpoint = initialValue
          }
          get {
            _endpoint
          }
          set {
            var implemented = _$Implemented("endpoint")
            _endpoint = {
              implemented.fulfill()
              return newValue($0)
            }
          }
        }

        private var _endpoint: (String) throws -> Bool = { _ in
          XCTestDynamicOverlay.XCTFail("Unimplemented: 'endpoint'")
          throw XCTestDynamicOverlay.Unimplemented("endpoint")
        }
      }
      """
    }
  }

  func testNotAClosure() {
    assertMacro {
      """
      struct Client {
        @Unimplemented(default: true)
        var endpoint: Bool
      }
      """
    } diagnostics: {
      """
      struct Client {
        @Unimplemented(default: true)
        ┬────────────────────────────
        ╰─ 🛑 '@Unimplemented' must be attached to closure property
        var endpoint: Bool
      }
      """
    }
  }

  func testWithDefaultAssignment() {
    assertMacro {
      """
      struct Client {
        @Unimplemented
        var endpoint: () -> Bool = { false }
      }
      """
    } diagnostics: {
      """
      struct Client {
        @Unimplemented
        var endpoint: () -> Bool = { false }
                                 ┬──────────
                                 ╰─ 🛑 '@Unimplemented' property must not have initial value
                                    ✏️ Remove initial value
      }
      """
    } fixes: {
      """
      struct Client {
        @Unimplemented
        var endpoint: () -> Bool \n\
      }
      """
    }
  }

  func testSendableClosure() {
    assertMacro {
      """
      struct DataManager: Sendable {
        @Unimplemented var load: @Sendable (URL) throws -> Data
      }
      """
    } expansion: {
      """
      struct DataManager: Sendable {
        var load: @Sendable (URL) throws -> Data {
          @storageRestrictions(initializes: _load)
          init(initialValue) {
            _load = initialValue
          }
          get {
            _load
          }
          set {
            var implemented = _$Implemented("load")
            _load = {
              implemented.fulfill()
              return newValue($0)
            }
          }
        }

        private var _load: @Sendable (URL) throws -> Data = { _ in
          XCTestDynamicOverlay.XCTFail("Unimplemented: 'load'")
          throw XCTestDynamicOverlay.Unimplemented("load")
        }
      }
      """
    }
  }

  func testActorClosure() {
    assertMacro {
      """
      struct DataManager: Sendable {
        @Unimplemented var load: @MainActor (URL) throws -> Data
      }
      """
    } expansion: {
      """
      struct DataManager: Sendable {
        var load: @MainActor (URL) throws -> Data {
          @storageRestrictions(initializes: _load)
          init(initialValue) {
            _load = initialValue
          }
          get {
            _load
          }
          set {
            var implemented = _$Implemented("load")
            _load = {
              implemented.fulfill()
              return newValue($0)
            }
          }
        }

        private var _load: @MainActor (URL) throws -> Data = { _ in
          XCTestDynamicOverlay.XCTFail("Unimplemented: 'load'")
          throw XCTestDynamicOverlay.Unimplemented("load")
        }
      }
      """
    }
  }
}
