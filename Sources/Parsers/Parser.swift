//
// This source file is part of swift-parsers, an open source project by Wayfair
//
// Copyright (c) 2019 Wayfair, LLC.
// Licensed under the 2-Clause BSD License
//
// See LICENSE.md for license information
//

import Prelude

/// a `Parser` that parses a “stream” of type `S` and returns a result of type `A`. Parsing may `throw` a `ParseError` if it fails
public struct Parser<S, A> {
    public let parse: (S) throws -> (A, S)

    /// initialize a `Parser` with a `parse` function that parses a “stream” of type `S`, returns a value of type `A`, and may throw if parsing fails
    ///
    /// - Parameter parse: a parse function
    public init(_ parse: @escaping (S) throws -> (A, S)) {
        self.parse = parse
    }
}

// MARK: - convenience: `Substring` parser

/// a `StringParser` is (secretly) a `Substring` parser, for performance reasons
public typealias StringParser<A> = Parser<Substring, A>

public extension Parser where S == Substring {
    /// convenience: run a `StringParser` (which is secretly actually a `Substring` parser) with a `String` input
    ///
    /// - Parameter input: `String` input
    /// - Returns: a parser result
    /// - Throws: a `ParserError` if parsing fails
    func run(_ input: String) throws -> (A, String) {
        let (result, rest) = try parse(Substring(input))
        return (result, String(rest))
    }
}

// MARK: - primitive parsers

/// the “root” parse implementation for most `Parser`s. `characterThat(satisfies:)` generates a parser by accepting a `predicate` that should return `true` if the `Character` the parser is looking at should be successfully parsed. If `predicate` passes, the parser returns the `Character` and consumes it from the stream
///
/// - Parameter predicate: a function on `Character` that returns a `Bool` if parsing should succeed
/// - Returns: a primitive `Character` parser
func characterThat(satisfies predicate: @escaping (Character) throws -> Bool) -> StringParser<Character> {
    return .init { stream in
        guard let first = stream.first, try predicate(first) else {
            let message = "parse failed, head of the stream was: “\(stream.prefix(20))”"
            throw ParseError(message)
        }
        return (first, stream.dropFirst())
    }
}

/// generate a `Character` `Parser` that will successfully parse any character *not* in the passed `list`
///
/// - Parameter list: a list of `Character`s (in the form of a `String`) that should fail parsing. All other `Character`s will pass
/// - Returns: a `Character` `Parser`
public func noneOf(_ list: String) -> StringParser<Character> {
    return characterThat { !list.contains($0) }
}

/// generate a `Character` `Parser` that will successfully parse any character in the passed `list`
///
/// - Parameter list: a list of `Character`s (in the form of a `String`) that should successfully parse. All other `Character`s will fail
/// - Returns: a `Character` `Parser`
public func oneOf(_ list: String) -> StringParser<Character> {
    return characterThat { list.contains($0) }
}

/// generate a `String` `Parser` that will parse the `String` value passed as `exactly`
///
/// - Parameter exactly: a `String` to attempt to parse from the front of the stream
/// - Returns: a `String` `Parser`
public func string(_ exactly: String) -> StringParser<String> {
    return .init { stream in
        guard stream.hasPrefix(exactly) else {
            let message = "parse failed, was expecting the prefix “\(exactly)” but the stream started with: “\(stream.prefix(20))”"
            throw ParseError(message)
        }
        return (exactly, stream.dropFirst(exactly.count))
    }
}

// MARK: - semantic parsers

/// generate a `Double` `Parser` that will attempt to parse a `Double` from the front of the stream
public let double: StringParser<Double> = oneOf("0123456789.").oneOrMore.flatMap { chars in
    return .init { stream in
        guard let doubleValue = Double(String(chars)) else {
            let message = "parse failed, the string “\(String(chars))” is not a valid `Double`"
            throw ParseError(message)
        }
        return (doubleValue, stream)
    }
}

/// convenience function to generate a `String` `Parser` for the given `string` which will also consume any amount of trailing whitespace
///
/// - Parameter exactly: the `String` value to attempt to parse
/// - Returns: a `Parser` that attempts to parse the given `String` and also consumes any trailing whitespace
public func stringIgnoringTrailingWhitespace(_ exactly: String) -> StringParser<String> {
    return string(exactly) <* whitespace.zeroOrMore
}

/// a `Parser` that parses one whitespace character
public let whitespace: StringParser<Character> = oneOf(" \t\n\r")

// MARK: - combinators

public extension Parser {
    /// generate a `Parser` that returns `true` when the root parser (`self`) succeeds and `false` if it fails
    var asBool: Parser<S, Bool> {
        return self.asTrue.fallback(false)
    }

    /// generate a `Parser` that returns `true` when the root parser (`self`) succeeds, but throws an error if it fails
    var asTrue: Parser<S, Bool> {
        return self.map { _ in true }
    }

    /// generate a `Parser` that returns `false` when the root parser (`self`) succeeds (if the presence of a token indicates falsehood), but throws an error if it fails
    var asFalse: Parser<S, Bool> {
        return self.map { _ in false }
    }

    /// generate a `Parser` that parses zero or more occurrences of the root parser (`self`)
    var zeroOrMore: Parser<S, [A]> {
        return .init { stream in
            var results = [A]()
            var rest = stream
            while let (result, nextRest) = try? self.parse(rest) {
                results.append(result)
                rest = nextRest
            }
            return (results, rest)
        }
    }

    /// generate a `Parser` that parses one or more occurrences of the root parser (`self`)
    var oneOrMore: Parser<S, [A]> {
        return .init { stream in
            var results = [A]()
            var rest = stream
            let (firstResult, firstRest) = try self.parse(rest)
            results.append(firstResult)
            rest = firstRest
            while let (result, nextRest) = try? self.parse(rest) {
                results.append(result)
                rest = nextRest
            }
            return (results, rest)
        }
    }

    var once: Parser<S, [A]> {
        return repeated(1)
    }

    /// generate a `Parser` that parses exactly `times` occurrences of the root parser (`self`)
    func repeated(_ times: Int) -> Parser<S, [A]> {
        return .init { stream in
            var results = [A]()
            var rest = stream
            var iteration = 0
            while iteration < times, let (result, nextRest) = try? self.parse(rest) {
                results.append(result)
                rest = nextRest
                iteration += 1
            }
            guard iteration == times else {
                throw ParseError("Did not consume \(times) items, consumed \(iteration): \(results), \(rest)")
            }
            return (results, rest)
        }
    }

    /// generate a `Parser` that first attempts to parse (and discard the results of) `open`, then attempts to parse `self`, then attempts to parse (and discard the results of) `close`
    ///
    /// - Parameters:
    ///   - open: a `Parser` to attempt to run prior to parsing `self` from the stream
    ///   - close: a `Parser` to attempt to run after parsing `self` from the stream
    /// - Returns: a `Parser` which parses (then discards) `open`, parses `self`, then parses (and discards) `close`
    func between<Y, Z>(_ open: Parser<S, Y>, _ close: Parser<S, Z>) -> Parser<S, A> {
        return open *> self <* close
    }

    /// generate a `Parser` that, if it fails, returns the “fallback” value `defaultValue`, rather than `throw`ing
    ///
    /// - Parameter defaultValue: the default value to return when parsing `self` fails
    /// - Returns: a `Parser` that will return `defaultValue` if parsing fails
    func fallback(_ defaultValue: A) -> Parser<S, A> {
        return .init { stream in
            do {
                let (result, rest) = try self.parse(stream)
                return (result, rest)
            } catch {
                return (defaultValue, stream)
            }
        }
    }

    /// generate a `Parser` that runs `self`, and prior to returning its result, performs the given `transform` on the result of that
    ///
    /// - Parameter transform: a transformation function on `A`
    /// - Returns: a `Parser` that returns values of type `B`
    func map<B>(_ transform: @escaping (A) -> B) -> Parser<S, B> {
        return .init { stream in
            let (result, rest) = try self.parse(stream)
            return (transform(result), rest)
        }
    }
}

// MARK: - monad

public extension Parser {
    /// generate a `Parser` based on the result of another `Parser`.
    ///
    /// - Parameter transform: a transformation function
    /// - Returns: a `Parser` that returns values of type `B`
    func flatMap<B>(_ transform: @escaping (A) -> Parser<S, B>) -> Parser<S, B> {
        return .init { stream in
            let (result, rest) = try self.parse(stream)
            return try transform(result).parse(rest)
        }
    }
}

public func >>-<S, A, B>(_ lhs: Parser<S, A>, _ rhs: @escaping (A) -> Parser<S, B>) -> Parser<S, B> {
    return lhs.flatMap(rhs)
}

// MARK: - applicative

/// the “pure” `Parser` on `A` (a `Parser` that simply returns the value `value` and does not consume the stream)
///
/// - Parameter value: the value to return
/// - Returns: a `Parser` on `A`
public func pure<S, A>(_ value: A) -> Parser<S, A> {
    return .init { stream in
        return (value, stream)
    }
}

public func <*><S, A, B>(_ transform: Parser<S, (A) -> B>, _ value: Parser<S, A>) -> Parser<S, B> {
    return transform >>- { f in
        value >>- { a in
            pure(f(a))
        }
    }
}

public func <*<S, A, B>(_ lhs: Parser<S, A>, _ rhs: Parser<S, B>) -> Parser<S, A> {
    return pure(curry(const)) <*> lhs <*> rhs
}

public func *><S, A, B>(_ lhs: Parser<S, A>, _ rhs: Parser<S, B>) -> Parser<S, B> {
    return pure(curry(flip(const))) <*> lhs <*> rhs
}

public func liftA<S, A, B, C>(_ f: @escaping (A) -> (B) -> C, _ first: Parser<S, A>, _ second: Parser<S, B>) -> Parser<S, C> {
    return pure(f) <*> first <*> second
}

public func liftA<S, A, B, C>(_ f: @escaping (A, B) -> C, _ first: Parser<S, A>, _ second: Parser<S, B>) -> Parser<S, C> {
    return liftA(curry(f), first, second)
}

public func liftA<S, A, B, C, D>(_ f: @escaping (A) -> (B) -> (C) -> D, _ first: Parser<S, A>, _ second: Parser<S, B>, _ third: Parser<S, C>) -> Parser<S, D> {
    return pure(f) <*> first <*> second <*> third
}

public func liftA<S, A, B, C, D>(_ f: @escaping (A, B, C) -> D, _ first: Parser<S, A>, _ second: Parser<S, B>, _ third: Parser<S, C>) -> Parser<S, D> {
    return liftA(curry(f), first, second, third)
}

// MARK: - alternative

/// “choice” implemented for `Parser`s. Attempt to run the `lhs` `Parser`, and if that fails, attempt to run the `rhs` `Parser` instead, returning the first successful value
///
/// - Parameters:
///   - lhs: the first `Parser` to attempt
///   - rhs: the second `Parser` to attempt
/// - Returns: a `Parser` that attempts `lhs` and, if that fails, attempts `rhs`
public func <|><S, A>(_ lhs: Parser<S, A>, _ rhs: Parser<S, A>) -> Parser<S, A> {
    return .init { stream in
        do {
            return try lhs.parse(stream)
        } catch {
            return try rhs.parse(stream)
        }
    }
}

extension Parser: Semigroup where A: Semigroup {
    public static func <>(_ lhs: Parser<S, A>, _ rhs: Parser<S, A>) -> Parser<S, A> {
        // Take the result from lhs, pipe the remaining stream through rhs to get the next result, then concatenate the left and right results together
        return liftA(<>, lhs, rhs)
    }
}

extension Parser: Monoid where A: Monoid {
    public static var empty: Parser<S, A> {
        return pure(A.empty)
    }
}
