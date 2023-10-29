import SwiftDiagnostics
import SwiftOperators
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public enum DependencyEndpointMacro {
}

extension DependencyEndpointMacro: AccessorMacro {
  public static func expansion<D: DeclSyntaxProtocol, C: MacroExpansionContext>(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: D,
    in context: C
  ) throws -> [AccessorDeclSyntax] {
    guard
      let property = declaration.as(VariableDeclSyntax.self),
      let binding = property.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmed,
      let type = binding.typeAnnotation?.type,
      let functionType =
        (type.as(FunctionTypeSyntax.self)
        ?? type.as(AttributedTypeSyntax.self)?.baseType.as(FunctionTypeSyntax.self))?.trimmed,
      let functionReturnType = functionType.returnClause.type.as(IdentifierTypeSyntax.self)
    else {
      return []
    }

    let functionReturnTypeIsVoid = ["Void", "()"].qualified("Swift")
      .contains(functionReturnType.name.text)
    var effectSpecifiers = ""
    if functionType.effectSpecifiers?.throwsSpecifier != nil {
      effectSpecifiers.append("try ")
    }
    if functionType.effectSpecifiers?.asyncSpecifier != nil {
      effectSpecifiers.append("await ")
    }
    let parameterList = (0..<functionType.parameters.count).map { "$\($0)" }.joined(separator: ", ")

    return [
      """
      @storageRestrictions(initializes: $\(identifier))
      init(initialValue) {
      $\(identifier) = Endpoint(initialValue: initialValue) { newValue in
      let implemented = _$Implemented("\(identifier)")
      return {
      implemented.fulfill()
      \(raw: functionReturnTypeIsVoid ? "": "return ")\
      \(raw: effectSpecifiers)newValue(\(raw: parameterList))
      }
      }
      }
      """,
      """
      get {
      $\(identifier).rawValue
      }
      """,
      """
      set {
      $\(identifier).rawValue = newValue
      }
      """,
      // TODO: func \(identifier)
    ]
  }
}

extension DependencyEndpointMacro: PeerMacro {
  public static func expansion<D: DeclSyntaxProtocol, C: MacroExpansionContext>(
    of node: AttributeSyntax,
    providingPeersOf declaration: D,
    in context: C
  ) throws -> [DeclSyntax] {
    guard
      let property = declaration.as(VariableDeclSyntax.self),
      let binding = property.bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmed,
      let type = binding.typeAnnotation?.type,
      let functionType =
        (type.as(FunctionTypeSyntax.self)
        ?? type.as(AttributedTypeSyntax.self)?.baseType.as(FunctionTypeSyntax.self))?.trimmed,
      let functionReturnType = functionType.returnClause.type.as(IdentifierTypeSyntax.self)
    else {
      context.diagnose(
        Diagnostic(
          node: node,
          message: SimpleDiagnosticMessage(
            message: """
              '@DependencyEndpoint' must be attached to closure property
              """,
            diagnosticID: "closure-property",
            severity: .error
          )
        )
      )
      return []
    }

    let functionReturnTypeIsVoid = ["Void", "()"].qualified("Swift")
      .contains(functionReturnType.name.text)
    var unimplementedDefault: ClosureExprSyntax
    if let initializer = binding.initializer {
      guard var closure = initializer.value.as(ClosureExprSyntax.self)
      else {
        // TODO: Diagnose?
        return []
      }
      if
        !functionReturnTypeIsVoid,
        closure.statements.count == 1,
        var statement = closure.statements.first,
        let expression = statement.item.as(ExprSyntax.self)
      {
        statement.item = CodeBlockItemSyntax.Item(
          ReturnStmtSyntax(
            returnKeyword: .keyword(.return, trailingTrivia: .space),
            expression: expression
          )
        )
        closure.statements = closure.statements.with(\.[closure.statements.startIndex], statement)
      }
      unimplementedDefault = closure
    } else {
      unimplementedDefault = ClosureExprSyntax(
        leftBrace: .leftBraceToken(trailingTrivia: .space),
        signature: functionType.parameters.isEmpty
        ? nil
        : ClosureSignatureSyntax(
          attributes: [],
          parameterClause: .simpleInput(
            ClosureShorthandParameterListSyntax(
              (1...functionType.parameters.count).map { n in
                ClosureShorthandParameterSyntax(
                  name: .wildcardToken(),
                  trailingComma: n < functionType.parameters.count
                    ? .commaToken()
                    : nil,
                  trailingTrivia: .space
                )
              }
            )
          ),
          inKeyword: .keyword(.in, trailingTrivia: .space)
        ),
        statements: []
      )
      if functionType.effectSpecifiers?.throwsSpecifier != nil {
        unimplementedDefault.statements.append(
          """
          throw XCTestDynamicOverlay.Unimplemented("\(identifier)")
          """
        )
      } else if !functionReturnTypeIsVoid {
        unimplementedDefault.statements.append(
          CodeBlockItemSyntax(
            item: CodeBlockItemSyntax.Item(
              EditorPlaceholderExprSyntax(
                placeholder: TokenSyntax(
                  stringLiteral: "<#\(functionReturnType.name.text)#>"
                ),
                trailingTrivia: .space
              )
            )
          )
        )
        context.diagnose(
          Diagnostic(
            node: binding,
            message: SimpleDiagnosticMessage(
              message: """
                Missing initial value for non-throwing '\(identifier)'
                """,
              diagnosticID: "missing-default",
              severity: .error
            ),
            fixIt: FixIt(
              message: SimpleFixItMessage(
                message: """
                  Insert '= \(unimplementedDefault.description)'
                  """,
                fixItID: "add-missing-default"
              ),
              changes: [
                .replace(
                  oldNode: Syntax(binding),
                  newNode: Syntax(
                    binding.with(
                      \.initializer, InitializerClauseSyntax(
                        leadingTrivia: .space,
                        equal: .equalToken(trailingTrivia: .space),
                        value: unimplementedDefault
                      )
                    )
                  )
                )
              ]
            )
          )
        )
        return []
      }
    }
    unimplementedDefault.statements.insert(
      """
      XCTestDynamicOverlay.XCTFail("Unimplemented: '\(identifier)'")
      """,
      at: unimplementedDefault.statements.startIndex
    )

    var effectSpecifiers = ""
    if functionType.effectSpecifiers?.throwsSpecifier != nil {
      effectSpecifiers.append("try ")
    }
    if functionType.effectSpecifiers?.asyncSpecifier != nil {
      effectSpecifiers.append("await ")
    }
    let parameterList = (0..<functionType.parameters.count).map { "$\($0)" }.joined(separator: ", ")

    return [
      """
      var $\(identifier) = Endpoint<\(raw: functionType)>(
      initialValue: \(unimplementedDefault)
      ) { newValue in
      let implemented = _$Implemented("\(identifier)")
      return {
      implemented.fulfill()
      \(raw: functionReturnTypeIsVoid ? "": "return ")\
      \(raw: effectSpecifiers)newValue(\(raw: parameterList))
      }
      }
      """
    ]
  }
}
