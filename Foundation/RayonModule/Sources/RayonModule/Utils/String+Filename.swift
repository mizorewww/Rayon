//
//  String+Filename.swift
//  RayonModule
//
//  Shared filename validation, previously duplicated in the macOS and iOS apps.
//

import Foundation

public extension String {
    var isValidAsFilename: Bool {
        var invalidCharacters = CharacterSet(charactersIn: ":/")
        invalidCharacters.formUnion(.newlines)
        invalidCharacters.formUnion(.illegalCharacters)
        invalidCharacters.formUnion(.controlCharacters)
        return rangeOfCharacter(from: invalidCharacters) == nil && !isEmpty
    }
}
