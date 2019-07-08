//
// This source file is part of swift-parsers, an open source project by Wayfair
//
// Copyright (c) 2019 Wayfair, LLC.
// Licensed under the 2-Clause BSD License
//
// See LICENSE.md for license information
//

public struct ParseError: Error {
    let message: String

    public init(_ message: String) {
        self.message = message
    }
}
